-- =====================================================================
-- SIRAV - Sistema Integral de Reservas y Alquiler de Vehículos
-- Script 03_funciones.sql  (SIRAV-19)
-- Motor: PostgreSQL 16 (PL/pgSQL) | Ejecutar después de 02_insercion.sql
-- Autores: David Bejarano, Jose David Rodriguez
--
-- Convenciones: param_ parámetros, fn_ funciones, e_ excepciones,
--               vn_ número, vd_ fecha, vb_ booleano, vv_ texto, r_ registro.
--
-- Catálogo de excepciones de SIRAV (lo usan funciones, procedimientos y
-- triggers). PL/pgSQL no permite declarar excepciones con nombre como
-- PL/SQL, así que cada una tiene un SQLSTATE propio de la clase "SR" y su
-- mensaje empieza por el nombre e_ para que la aplicación lo identifique.
--
--   SQLSTATE  Excepción                    Regla
--   SR001     e_reserva_solapada           RN-01
--   SR002     e_mantenimiento_solapado     RN-02
--   SR003     e_transicion_invalida        RN-03
--   SR004     e_cierre_invalido            RN-05
--   SR005     e_vehiculo_no_disponible     vehículo inactivo o en uso
--   SR006     e_tarifa_no_vigente          RN-04
--   SR007     e_parametro_invalido         datos de entrada
--   SR008     e_registro_no_encontrado     id inexistente
-- =====================================================================

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET search_path TO sirav, public;

-- ---------------------------------------------------------------------
-- fn_obtener_tarifa_vigente
-- Devuelve el id de la tarifa vigente de una categoría en una fecha.
-- Apoyo para sp_crear_reserva y fn_calcular_costo (RN-04).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_obtener_tarifa_vigente(
  param_id_categoria BIGINT,
  param_fecha        DATE
) RETURNS BIGINT
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  vn_id_tarifa BIGINT;
BEGIN
  SELECT t.id_tarifa
    INTO vn_id_tarifa
    FROM tarifa t
   WHERE t.id_categoria = param_id_categoria
     AND param_fecha BETWEEN t.vigente_desde AND COALESCE(t.vigente_hasta, 'infinity'::date);

  IF vn_id_tarifa IS NULL THEN
    RAISE EXCEPTION 'e_tarifa_no_vigente: la categoría % no tiene tarifa vigente el %',
      param_id_categoria, param_fecha
      USING ERRCODE = 'SR006';
  END IF;

  RETURN vn_id_tarifa;
END;
$$;

COMMENT ON FUNCTION fn_obtener_tarifa_vigente(BIGINT, DATE)
  IS 'Id de la tarifa vigente de una categoría en una fecha (RN-04)';

-- ---------------------------------------------------------------------
-- fn_vehiculo_disponible
-- TRUE si el vehículo puede reservarse en [fecha_inicio, fecha_fin]:
--   - existe y no está INACTIVO
--   - no tiene reservas SOLICITADA, CONFIRMADA o ACTIVA solapadas (RN-01)
--   - no tiene mantenimientos PROGRAMADOS o EN_CURSO solapados (RN-02)
-- param_id_reserva_excluir permite ignorar una reserva propia (al
-- reprogramar o confirmar). Las fechas se tratan como rango cerrado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_vehiculo_disponible(
  param_id_vehiculo        BIGINT,
  param_fecha_inicio       DATE,
  param_fecha_fin          DATE,
  param_id_reserva_excluir BIGINT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  vv_estado_operativo vehiculo.estado_operativo%TYPE;
  vb_hay_reserva      BOOLEAN;
  vb_hay_mantenimiento BOOLEAN;
BEGIN
  IF param_fecha_inicio IS NULL OR param_fecha_fin IS NULL OR param_fecha_fin < param_fecha_inicio THEN
    RAISE EXCEPTION 'e_parametro_invalido: rango de fechas inválido (% a %)',
      param_fecha_inicio, param_fecha_fin
      USING ERRCODE = 'SR007';
  END IF;

  SELECT v.estado_operativo
    INTO vv_estado_operativo
    FROM vehiculo v
   WHERE v.id_vehiculo = param_id_vehiculo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: el vehículo % no existe', param_id_vehiculo
      USING ERRCODE = 'SR008';
  END IF;

  IF vv_estado_operativo = 'INACTIVO' THEN
    RETURN FALSE;
  END IF;

  SELECT EXISTS (
    SELECT 1
      FROM reserva r
     WHERE r.id_vehiculo = param_id_vehiculo
       AND r.estado IN ('SOLICITADA', 'CONFIRMADA', 'ACTIVA')
       AND (param_id_reserva_excluir IS NULL OR r.id_reserva <> param_id_reserva_excluir)
       AND daterange(r.fecha_inicio, r.fecha_fin, '[]')
           && daterange(param_fecha_inicio, param_fecha_fin, '[]')
  ) INTO vb_hay_reserva;

  SELECT EXISTS (
    SELECT 1
      FROM mantenimiento m
     WHERE m.id_vehiculo = param_id_vehiculo
       AND m.estado IN ('PROGRAMADO', 'EN_CURSO')
       AND daterange(m.fecha_inicio, m.fecha_fin, '[]')
           && daterange(param_fecha_inicio, param_fecha_fin, '[]')
  ) INTO vb_hay_mantenimiento;

  RETURN NOT (vb_hay_reserva OR vb_hay_mantenimiento);
END;
$$;

COMMENT ON FUNCTION fn_vehiculo_disponible(BIGINT, DATE, DATE, BIGINT)
  IS 'Disponibilidad de un vehículo en un rango de fechas (RN-01 y RN-02)';

-- ---------------------------------------------------------------------
-- fn_calcular_costo
-- Costo base de una reserva: días x valor diario de la tarifa (RN-04).
-- Días = fecha_fin - fecha_inicio, con mínimo 1 (entrega y devolución el
-- mismo día se cobra como un día).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calcular_costo(
  param_id_tarifa    BIGINT,
  param_fecha_inicio DATE,
  param_fecha_fin    DATE
) RETURNS NUMERIC(12,2)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  vn_valor_diario tarifa.valor_diario%TYPE;
  vn_dias         INTEGER;
BEGIN
  IF param_fecha_inicio IS NULL OR param_fecha_fin IS NULL OR param_fecha_fin < param_fecha_inicio THEN
    RAISE EXCEPTION 'e_parametro_invalido: rango de fechas inválido (% a %)',
      param_fecha_inicio, param_fecha_fin
      USING ERRCODE = 'SR007';
  END IF;

  SELECT t.valor_diario
    INTO vn_valor_diario
    FROM tarifa t
   WHERE t.id_tarifa = param_id_tarifa;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: la tarifa % no existe', param_id_tarifa
      USING ERRCODE = 'SR008';
  END IF;

  vn_dias := GREATEST(param_fecha_fin - param_fecha_inicio, 1);

  RETURN ROUND(vn_dias * vn_valor_diario, 2);
END;
$$;

COMMENT ON FUNCTION fn_calcular_costo(BIGINT, DATE, DATE)
  IS 'Costo base = días (mínimo 1) x valor diario de la tarifa (RN-04)';

-- ---------------------------------------------------------------------
-- fn_calcular_cargo_retraso
-- Cargo por devolución tardía de un alquiler (RN-04): cada día después
-- de la fecha_fin de la reserva cuesta el 50 % de la tarifa diaria.
-- La fecha de devolución se toma en hora de Bogotá. Si no se pasa,
-- usa la fecha_devolucion registrada o, si no existe, el momento actual.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calcular_cargo_retraso(
  param_id_alquiler      BIGINT,
  param_fecha_devolucion TIMESTAMPTZ DEFAULT NULL
) RETURNS NUMERIC(12,2)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  r_alquiler           RECORD;
  vd_fecha_devolucion  DATE;
  vn_dias_retraso      INTEGER;
  vn_porcentaje_cargo  CONSTANT NUMERIC := 0.50;
BEGIN
  SELECT a.fecha_devolucion, r.fecha_fin, t.valor_diario
    INTO r_alquiler
    FROM alquiler a
    JOIN reserva  r ON r.id_reserva = a.id_reserva
    JOIN tarifa   t ON t.id_tarifa  = r.id_tarifa
   WHERE a.id_alquiler = param_id_alquiler;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'e_registro_no_encontrado: el alquiler % no existe', param_id_alquiler
      USING ERRCODE = 'SR008';
  END IF;

  vd_fecha_devolucion := (COALESCE(param_fecha_devolucion, r_alquiler.fecha_devolucion, now())
                          AT TIME ZONE 'America/Bogota')::date;

  vn_dias_retraso := GREATEST(vd_fecha_devolucion - r_alquiler.fecha_fin, 0);

  RETURN ROUND(vn_dias_retraso * r_alquiler.valor_diario * vn_porcentaje_cargo, 2);
END;
$$;

COMMENT ON FUNCTION fn_calcular_cargo_retraso(BIGINT, TIMESTAMPTZ)
  IS 'Cargo por retraso = días tarde x 50 % de la tarifa diaria (RN-04)';
