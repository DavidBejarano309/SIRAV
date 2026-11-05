-- =====================================================================
-- SIRAV - Sistema Integral de Reservas y Alquiler de Vehículos
-- Script 04_procedimientos.sql  (SIRAV-20 y SIRAV-24)
-- Motor: PostgreSQL 16 (PL/pgSQL) | Ejecutar después de 03_funciones.sql
-- Autores: David Bejarano, Jose David Rodriguez
--
-- Flujo de la propuesta:
--   sp_crear_reserva      -> SOLICITADA
--   sp_confirmar_reserva  -> CONFIRMADA
--   sp_cancelar_reserva   -> CANCELADA (desde SOLICITADA o CONFIRMADA)
--   sp_iniciar_alquiler   -> alquiler ACTIVO, reserva ACTIVA
--   sp_cerrar_alquiler    -> cargos + pago de prueba, alquiler CERRADO,
--                            reserva CERRADA
--
-- Transacciones: cada CALL es atómico. Si se lanza una excepción, PostgreSQL
-- deshace todo lo que hizo el procedimiento (ROLLBACK implícito). Los
-- procedimientos no hacen COMMIT internamente para que la aplicación pueda
-- agruparlos en una transacción mayor (por ejemplo, registrar la inspección
-- en MongoDB y luego cerrar el alquiler).
--
-- Concurrencia: sp_crear_reserva y sp_confirmar_reserva bloquean la fila
-- del vehículo (SELECT ... FOR UPDATE); dos sesiones que reservan el mismo
-- vehículo se atienden en orden. La restricción ex_reserva_solapada es la
-- última barrera (su error 23P01 se traduce a e_reserva_solapada).
--
-- Auditoría: cada procedimiento recibe param_id_usuario y lo publica en la
-- variable de sesión sirav.id_usuario (y la observación en
-- sirav.observacion). trg_auditar_reserva (05_triggers.sql) las lee.
--
-- Excepciones: ver catálogo en 03_funciones.sql (SQLSTATE SR001-SR008).
-- =====================================================================

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET search_path TO sirav, public;

-- ---------------------------------------------------------------------
-- sp_registrar_contexto (interno)
-- Publica usuario y observación para la auditoría de esta transacción.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_contexto(
  param_id_usuario  BIGINT,
  param_observacion TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('sirav.id_usuario',  COALESCE(param_id_usuario::text, ''), TRUE);
  PERFORM set_config('sirav.observacion', COALESCE(param_observacion, ''),      TRUE);
END;
$$;

-- ---------------------------------------------------------------------
-- sp_crear_reserva  (RF-03, RN-01, RN-02, RN-04)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_crear_reserva(
  param_id_cliente   BIGINT,
  param_id_vehiculo  BIGINT,
  param_fecha_inicio DATE,
  param_fecha_fin    DATE,
  param_id_usuario   BIGINT,
  INOUT param_id_reserva BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  vd_hoy              DATE := (now() AT TIME ZONE 'America/Bogota')::date;
  vn_id_categoria     vehiculo.id_categoria%TYPE;
  vv_estado_operativo vehiculo.estado_operativo%TYPE;
  vn_id_tarifa        tarifa.id_tarifa%TYPE;
  vb_mantenimiento    BOOLEAN;
BEGIN
  -- Validación de parámetros
  IF param_fecha_inicio IS NULL OR param_fecha_fin IS NULL OR param_fecha_fin < param_fecha_inicio THEN
    RAISE EXCEPTION 'e_parametro_invalido: la fecha final debe ser igual o posterior a la inicial'
      USING ERRCODE = 'SR007';
  END IF;
  IF param_fecha_inicio < vd_hoy THEN
    RAISE EXCEPTION 'e_parametro_invalido: no se puede reservar en fechas pasadas (%)', param_fecha_inicio
      USING ERRCODE = 'SR007';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cliente c WHERE c.id_cliente = param_id_cliente) THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: el cliente % no existe', param_id_cliente
      USING ERRCODE = 'SR008';
  END IF;

  -- Bloqueo del vehículo: serializa reservas simultáneas del mismo carro
  SELECT v.id_categoria, v.estado_operativo
    INTO vn_id_categoria, vv_estado_operativo
    FROM vehiculo v
   WHERE v.id_vehiculo = param_id_vehiculo
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: el vehículo % no existe', param_id_vehiculo
      USING ERRCODE = 'SR008';
  END IF;
  IF vv_estado_operativo = 'INACTIVO' THEN
    RAISE EXCEPTION 'e_vehiculo_no_disponible: el vehículo % está inactivo', param_id_vehiculo
      USING ERRCODE = 'SR005';
  END IF;

  -- RN-02: mantenimiento en esas fechas
  SELECT EXISTS (
    SELECT 1 FROM mantenimiento m
     WHERE m.id_vehiculo = param_id_vehiculo
       AND m.estado <> 'CANCELADO'
       AND daterange(m.fecha_inicio, m.fecha_fin, '[]') && daterange(param_fecha_inicio, param_fecha_fin, '[]')
  ) INTO vb_mantenimiento;

  IF vb_mantenimiento THEN
    RAISE EXCEPTION 'e_mantenimiento_solapado: el vehículo % tiene mantenimiento entre % y %',
      param_id_vehiculo, param_fecha_inicio, param_fecha_fin
      USING ERRCODE = 'SR002';
  END IF;

  -- RN-01: reservas vigentes solapadas
  IF NOT fn_vehiculo_disponible(param_id_vehiculo, param_fecha_inicio, param_fecha_fin) THEN
    RAISE EXCEPTION 'e_reserva_solapada: el vehículo % ya está reservado entre % y %; elija otro vehículo o cambie las fechas',
      param_id_vehiculo, param_fecha_inicio, param_fecha_fin
      USING ERRCODE = 'SR001';
  END IF;

  -- RN-04: tarifa vigente de la categoría al inicio de la reserva
  vn_id_tarifa := fn_obtener_tarifa_vigente(vn_id_categoria, param_fecha_inicio);

  CALL sp_registrar_contexto(param_id_usuario, 'Reserva creada');

  INSERT INTO reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin, estado)
  VALUES (param_id_cliente, param_id_vehiculo, vn_id_tarifa, param_fecha_inicio, param_fecha_fin, 'SOLICITADA')
  RETURNING id_reserva INTO param_id_reserva;

EXCEPTION
  WHEN exclusion_violation THEN   -- 23P01: carrera que superó el bloqueo
    RAISE EXCEPTION 'e_reserva_solapada: el vehículo % ya está reservado en esas fechas', param_id_vehiculo
      USING ERRCODE = 'SR001';
END;
$$;

-- ---------------------------------------------------------------------
-- sp_confirmar_reserva  (RN-03: SOLICITADA -> CONFIRMADA)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_confirmar_reserva(
  param_id_reserva BIGINT,
  param_id_usuario BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  r_reserva reserva%ROWTYPE;
BEGIN
  SELECT * INTO r_reserva FROM reserva WHERE id_reserva = param_id_reserva FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: la reserva % no existe', param_id_reserva
      USING ERRCODE = 'SR008';
  END IF;
  IF r_reserva.estado <> 'SOLICITADA' THEN
    RAISE EXCEPTION 'e_transicion_invalida: la reserva % está % y solo se confirma desde SOLICITADA',
      param_id_reserva, r_reserva.estado
      USING ERRCODE = 'SR003';
  END IF;

  -- Revalidación: pudo registrarse un mantenimiento después de la solicitud
  PERFORM 1 FROM vehiculo WHERE id_vehiculo = r_reserva.id_vehiculo FOR UPDATE;
  IF NOT fn_vehiculo_disponible(r_reserva.id_vehiculo, r_reserva.fecha_inicio, r_reserva.fecha_fin, param_id_reserva) THEN
    RAISE EXCEPTION 'e_vehiculo_no_disponible: el vehículo % ya no está libre entre % y %',
      r_reserva.id_vehiculo, r_reserva.fecha_inicio, r_reserva.fecha_fin
      USING ERRCODE = 'SR005';
  END IF;

  CALL sp_registrar_contexto(param_id_usuario, 'Reserva confirmada por operador');

  UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = param_id_reserva;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_cancelar_reserva  (RN-03: SOLICITADA o CONFIRMADA -> CANCELADA)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_reserva(
  param_id_reserva BIGINT,
  param_id_usuario BIGINT,
  param_motivo     TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  vv_estado reserva.estado%TYPE;
BEGIN
  SELECT estado INTO vv_estado FROM reserva WHERE id_reserva = param_id_reserva FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: la reserva % no existe', param_id_reserva
      USING ERRCODE = 'SR008';
  END IF;
  IF vv_estado NOT IN ('SOLICITADA', 'CONFIRMADA') THEN
    RAISE EXCEPTION 'e_transicion_invalida: la reserva % está % y solo se cancela desde SOLICITADA o CONFIRMADA',
      param_id_reserva, vv_estado
      USING ERRCODE = 'SR003';
  END IF;

  CALL sp_registrar_contexto(param_id_usuario, COALESCE('Cancelada: ' || param_motivo, 'Reserva cancelada'));

  UPDATE reserva SET estado = 'CANCELADA' WHERE id_reserva = param_id_reserva;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_iniciar_alquiler  (entrega: CONFIRMADA -> ACTIVA, crea alquiler 1:1)
-- La inspección de entrega la guarda la aplicación en MongoDB con el
-- id_alquiler que devuelve este procedimiento.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_iniciar_alquiler(
  param_id_reserva         BIGINT,
  param_km_salida          INTEGER,
  param_combustible_salida NUMERIC,
  param_id_usuario         BIGINT,
  INOUT param_id_alquiler  BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  vd_hoy        DATE := (now() AT TIME ZONE 'America/Bogota')::date;
  r_reserva     reserva%ROWTYPE;
  vn_km_actual  vehiculo.kilometraje_actual%TYPE;
BEGIN
  SELECT * INTO r_reserva FROM reserva WHERE id_reserva = param_id_reserva FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: la reserva % no existe', param_id_reserva
      USING ERRCODE = 'SR008';
  END IF;
  IF r_reserva.estado <> 'CONFIRMADA' THEN
    RAISE EXCEPTION 'e_transicion_invalida: la reserva % está % y solo se entrega desde CONFIRMADA',
      param_id_reserva, r_reserva.estado
      USING ERRCODE = 'SR003';
  END IF;
  IF vd_hoy > r_reserva.fecha_fin THEN
    RAISE EXCEPTION 'e_parametro_invalido: la reserva % terminó el %; no se puede entregar',
      param_id_reserva, r_reserva.fecha_fin
      USING ERRCODE = 'SR007';
  END IF;

  SELECT kilometraje_actual INTO vn_km_actual
    FROM vehiculo WHERE id_vehiculo = r_reserva.id_vehiculo FOR UPDATE;

  IF param_km_salida IS NULL OR param_km_salida < vn_km_actual THEN
    RAISE EXCEPTION 'e_parametro_invalido: km de salida % menor que el kilometraje registrado %',
      param_km_salida, vn_km_actual
      USING ERRCODE = 'SR007';
  END IF;
  IF param_combustible_salida IS NULL OR param_combustible_salida NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'e_parametro_invalido: el combustible debe estar entre 0 y 100 %%'
      USING ERRCODE = 'SR007';
  END IF;

  CALL sp_registrar_contexto(param_id_usuario, 'Vehículo entregado al cliente');

  INSERT INTO alquiler (id_reserva, fecha_entrega, km_salida, combustible_salida, estado)
  VALUES (param_id_reserva, now(), param_km_salida, param_combustible_salida, 'ACTIVO')
  RETURNING id_alquiler INTO param_id_alquiler;

  UPDATE vehiculo SET kilometraje_actual = param_km_salida WHERE id_vehiculo = r_reserva.id_vehiculo;
  UPDATE reserva  SET estado = 'ACTIVA' WHERE id_reserva = param_id_reserva;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_cerrar_alquiler  (devolución y cierre: RN-04 y RN-05)
--   - Exige el id de la inspección de devolución ya guardada en MongoDB
--     (RN-05: solo se cierra después de registrar devolución e inspección).
--   - Calcula el cargo por retraso con fn_calcular_cargo_retraso.
--   - Registra el cargo por daños si la inspección los reportó.
--   - Genera el pago de prueba = costo base + todos los cargos.
--   - Deja alquiler CERRADO, reserva CERRADA y actualiza el kilometraje.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cerrar_alquiler(
  param_id_alquiler          BIGINT,
  param_km_entrada           INTEGER,
  param_combustible_entrada  NUMERIC,
  param_id_inspeccion        VARCHAR,
  param_id_usuario           BIGINT,
  param_monto_danos          NUMERIC     DEFAULT 0,
  param_tipo_pago            VARCHAR     DEFAULT 'PRUEBA',
  param_fecha_devolucion     TIMESTAMPTZ DEFAULT NULL,
  INOUT param_monto_total    NUMERIC     DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
  r_alquiler          alquiler%ROWTYPE;
  r_reserva           reserva%ROWTYPE;
  vd_fecha_devolucion TIMESTAMPTZ := COALESCE(param_fecha_devolucion, now());
  vn_costo_base       NUMERIC(12,2);
  vn_cargo_retraso    NUMERIC(12,2);
  vn_total_cargos     NUMERIC(12,2);
BEGIN
  SELECT * INTO r_alquiler FROM alquiler WHERE id_alquiler = param_id_alquiler FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: el alquiler % no existe', param_id_alquiler
      USING ERRCODE = 'SR008';
  END IF;
  IF r_alquiler.estado <> 'ACTIVO' THEN
    RAISE EXCEPTION 'e_cierre_invalido: el alquiler % ya está %', param_id_alquiler, r_alquiler.estado
      USING ERRCODE = 'SR004';
  END IF;
  IF param_id_inspeccion IS NULL OR btrim(param_id_inspeccion) = '' THEN
    RAISE EXCEPTION 'e_cierre_invalido: falta la inspección de devolución (RN-05)'
      USING ERRCODE = 'SR004';
  END IF;
  IF param_km_entrada IS NULL OR param_km_entrada < r_alquiler.km_salida THEN
    RAISE EXCEPTION 'e_parametro_invalido: km de entrada % menor que km de salida %',
      param_km_entrada, r_alquiler.km_salida
      USING ERRCODE = 'SR007';
  END IF;
  IF param_combustible_entrada IS NULL OR param_combustible_entrada NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'e_parametro_invalido: el combustible debe estar entre 0 y 100 %%'
      USING ERRCODE = 'SR007';
  END IF;
  IF vd_fecha_devolucion < r_alquiler.fecha_entrega THEN
    RAISE EXCEPTION 'e_parametro_invalido: la devolución no puede ser anterior a la entrega'
      USING ERRCODE = 'SR007';
  END IF;
  IF COALESCE(param_monto_danos, 0) < 0 THEN
    RAISE EXCEPTION 'e_parametro_invalido: el monto de daños no puede ser negativo'
      USING ERRCODE = 'SR007';
  END IF;

  SELECT * INTO r_reserva FROM reserva WHERE id_reserva = r_alquiler.id_reserva FOR UPDATE;

  -- Registrar la devolución (todavía ACTIVO para que el cálculo la vea)
  UPDATE alquiler
     SET fecha_devolucion    = vd_fecha_devolucion,
         km_entrada          = param_km_entrada,
         combustible_entrada = param_combustible_entrada
   WHERE id_alquiler = param_id_alquiler;

  -- RN-04: cargo por retraso
  vn_cargo_retraso := fn_calcular_cargo_retraso(param_id_alquiler, vd_fecha_devolucion);
  IF vn_cargo_retraso > 0 THEN
    INSERT INTO cargo_adicional (id_alquiler, concepto, descripcion, monto)
    VALUES (param_id_alquiler, 'RETRASO',
            format('Devolución %s días tarde (50 %% de la tarifa diaria)',
                   (vd_fecha_devolucion AT TIME ZONE 'America/Bogota')::date - r_reserva.fecha_fin),
            vn_cargo_retraso);
  END IF;

  -- Daños reportados en la inspección de devolución
  IF COALESCE(param_monto_danos, 0) > 0 THEN
    INSERT INTO cargo_adicional (id_alquiler, concepto, descripcion, monto)
    VALUES (param_id_alquiler, 'DANO', 'Daños según inspección ' || param_id_inspeccion, param_monto_danos);
  END IF;

  -- Pago de prueba = costo base + todos los cargos del alquiler
  vn_costo_base := fn_calcular_costo(r_reserva.id_tarifa, r_reserva.fecha_inicio, r_reserva.fecha_fin);
  SELECT COALESCE(SUM(c.monto), 0) INTO vn_total_cargos
    FROM cargo_adicional c WHERE c.id_alquiler = param_id_alquiler;
  param_monto_total := vn_costo_base + vn_total_cargos;

  INSERT INTO pago (id_alquiler, monto, tipo, estado)
  VALUES (param_id_alquiler, param_monto_total, param_tipo_pago, 'APROBADO');

  UPDATE alquiler SET estado = 'CERRADO' WHERE id_alquiler = param_id_alquiler;
  UPDATE vehiculo SET kilometraje_actual = param_km_entrada WHERE id_vehiculo = r_reserva.id_vehiculo;

  CALL sp_registrar_contexto(param_id_usuario,
       format('Alquiler cerrado; inspección %s; total %s', param_id_inspeccion, param_monto_total));
  UPDATE reserva SET estado = 'CERRADA' WHERE id_reserva = r_reserva.id_reserva;
END;
$$;

COMMENT ON PROCEDURE sp_crear_reserva(BIGINT, BIGINT, DATE, DATE, BIGINT, BIGINT)
  IS 'Crea una reserva SOLICITADA validando RN-01, RN-02 y RN-04';
COMMENT ON PROCEDURE sp_confirmar_reserva(BIGINT, BIGINT)
  IS 'SOLICITADA -> CONFIRMADA, revalida disponibilidad';
COMMENT ON PROCEDURE sp_cancelar_reserva(BIGINT, BIGINT, TEXT)
  IS 'SOLICITADA o CONFIRMADA -> CANCELADA';
COMMENT ON PROCEDURE sp_iniciar_alquiler(BIGINT, INTEGER, NUMERIC, BIGINT, BIGINT)
  IS 'Entrega del vehículo: crea el alquiler ACTIVO y pasa la reserva a ACTIVA';
COMMENT ON PROCEDURE sp_cerrar_alquiler(BIGINT, INTEGER, NUMERIC, VARCHAR, BIGINT, NUMERIC, VARCHAR, TIMESTAMPTZ, NUMERIC)
  IS 'Devolución y cierre: cargos (RN-04), pago de prueba y RN-05';
