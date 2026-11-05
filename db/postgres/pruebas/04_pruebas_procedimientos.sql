-- =====================================================================
-- SIRAV - 04_pruebas_procedimientos.sql  (evidencia SIRAV-20 y SIRAV-24)
-- Ejecutar después de 01 a 04. Todo corre en una transacción que se
-- revierte al final, así que los datos de prueba no cambian.
-- Las fechas se calculan a partir de hoy para que las pruebas sirvan
-- cualquier día. Cada línea NOTICE debe empezar por OK.
-- =====================================================================
SET client_min_messages = notice;
SET search_path TO sirav, public;

BEGIN;

-- Auxiliares de prueba (pg_temp: solo existen en esta sesión)
CREATE FUNCTION pg_temp.fn_verificar(param_caso TEXT, param_esperado TEXT, param_obtenido TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  RAISE NOTICE '% | %  (esperado: %, obtenido: %)',
    CASE WHEN param_esperado IS NOT DISTINCT FROM param_obtenido THEN 'OK   ' ELSE 'FALLO' END,
    param_caso, param_esperado, param_obtenido;
END; $$;

CREATE FUNCTION pg_temp.fn_sqlstate_de(param_sql TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE param_sql;
  RETURN 'SIN_ERROR';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END; $$;

-- Fechas de prueba relativas a hoy (hora de Bogotá)
CREATE TEMP TABLE t_fechas AS
SELECT (now() AT TIME ZONE 'America/Bogota')::date AS hoy;

-- ---------------------------------------------------------------------
-- SIRAV-20: crear, confirmar y cancelar reservas
-- ---------------------------------------------------------------------
DO $$
DECLARE
  vd_hoy        DATE := (SELECT hoy FROM t_fechas);
  vn_id_reserva BIGINT;
  vn_id_otra    BIGINT;
BEGIN
  -- P1: reserva válida (vehículo 4, ECONOMICO, 3 días)
  CALL sp_crear_reserva(1, 4, vd_hoy + 30, vd_hoy + 33, 2, vn_id_reserva);
  PERFORM pg_temp.fn_verificar('P1 sp_crear_reserva deja la reserva SOLICITADA', 'SOLICITADA',
          (SELECT estado FROM reserva WHERE id_reserva = vn_id_reserva));
  PERFORM pg_temp.fn_verificar('P1 usa la tarifa vigente de la categoría', '6',
          (SELECT id_tarifa::text FROM reserva WHERE id_reserva = vn_id_reserva));
  CREATE TEMP TABLE t_ids AS SELECT vn_id_reserva AS id_reserva;

  -- P2: misma franja, mismo vehículo -> RN-01
  PERFORM pg_temp.fn_verificar('P2 Reserva solapada -> e_reserva_solapada', 'SR001',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(2, 4, %L, %L, 2)', vd_hoy + 32, vd_hoy + 35)));

  -- P3: mantenimiento en las fechas -> RN-02
  INSERT INTO mantenimiento (id_vehiculo, fecha_inicio, fecha_fin, descripcion)
  VALUES (4, vd_hoy + 40, vd_hoy + 42, 'Mantenimiento de prueba');
  PERFORM pg_temp.fn_verificar('P3 Fechas con mantenimiento -> e_mantenimiento_solapado', 'SR002',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(2, 4, %L, %L, 2)', vd_hoy + 41, vd_hoy + 44)));

  -- P4 a P7: validaciones de entrada
  PERFORM pg_temp.fn_verificar('P4 Fecha pasada -> e_parametro_invalido', 'SR007',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(2, 9, %L, %L, 2)', vd_hoy - 3, vd_hoy - 1)));
  PERFORM pg_temp.fn_verificar('P5 Fechas invertidas -> e_parametro_invalido', 'SR007',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(2, 9, %L, %L, 2)', vd_hoy + 9, vd_hoy + 5)));
  PERFORM pg_temp.fn_verificar('P6 Vehículo INACTIVO -> e_vehiculo_no_disponible', 'SR005',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(2, 15, %L, %L, 2)', vd_hoy + 5, vd_hoy + 6)));
  PERFORM pg_temp.fn_verificar('P7 Cliente inexistente -> e_registro_no_encontrado', 'SR008',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(999, 9, %L, %L, 2)', vd_hoy + 5, vd_hoy + 6)));

  -- P8: confirmar (RN-03)
  CALL sp_confirmar_reserva(vn_id_reserva, 2);
  PERFORM pg_temp.fn_verificar('P8 sp_confirmar_reserva -> CONFIRMADA', 'CONFIRMADA',
          (SELECT estado FROM reserva WHERE id_reserva = vn_id_reserva));
  PERFORM pg_temp.fn_verificar('P9 Confirmar dos veces -> e_transicion_invalida', 'SR003',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_confirmar_reserva(%s, 2)', vn_id_reserva)));

  -- P10: cancelar y liberar el vehículo
  CALL sp_crear_reserva(2, 9, vd_hoy + 10, vd_hoy + 12, 2, vn_id_otra);
  CALL sp_cancelar_reserva(vn_id_otra, 2, 'El cliente cambió de planes');
  PERFORM pg_temp.fn_verificar('P10 sp_cancelar_reserva -> CANCELADA', 'CANCELADA',
          (SELECT estado FROM reserva WHERE id_reserva = vn_id_otra));
  PERFORM pg_temp.fn_verificar('P11 La cancelada libera las fechas (nueva reserva igual)', 'SIN_ERROR',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_crear_reserva(3, 9, %L, %L, 2)', vd_hoy + 10, vd_hoy + 12)));
  PERFORM pg_temp.fn_verificar('P12 Cancelar una CERRADA -> e_transicion_invalida', 'SR003',
          pg_temp.fn_sqlstate_de('CALL sirav.sp_cancelar_reserva(1, 2)'));
END $$;

-- ---------------------------------------------------------------------
-- Transacciones: ROLLBACK explícito y atomicidad del procedimiento
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_conteo AS SELECT count(*) AS n FROM reserva;
SELECT hoy + 60 AS vd_ini_rb, hoy + 61 AS vd_fin_rb FROM t_fechas \gset
SAVEPOINT antes_rollback;
CALL sp_crear_reserva(4, 10, :'vd_ini_rb', :'vd_fin_rb', 2);
SELECT pg_temp.fn_verificar('P13 Dentro de la transacción la reserva existe',
       ((SELECT n FROM t_conteo) + 1)::text, (SELECT count(*)::text FROM reserva));
ROLLBACK TO antes_rollback;
SELECT pg_temp.fn_verificar('P13 ROLLBACK deshace la reserva creada',
       (SELECT n::text FROM t_conteo), (SELECT count(*)::text FROM reserva));

-- ---------------------------------------------------------------------
-- SIRAV-24: iniciar y cerrar alquiler
-- ---------------------------------------------------------------------
DO $$
DECLARE
  vn_id_reserva  BIGINT := (SELECT id_reserva FROM t_ids);
  vn_id_alquiler BIGINT;
  vn_total       NUMERIC;
  vd_fin         DATE;
  vn_km_veh      INTEGER := (SELECT kilometraje_actual FROM vehiculo WHERE id_vehiculo = 4);
BEGIN
  PERFORM pg_temp.fn_verificar('A1 Entregar una SOLICITADA -> e_transicion_invalida', 'SR003',
          pg_temp.fn_sqlstate_de('CALL sirav.sp_iniciar_alquiler(12, 14300, 100, 2)'));
  PERFORM pg_temp.fn_verificar('A2 km de salida menor al del vehículo -> e_parametro_invalido', 'SR007',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_iniciar_alquiler(%s, %s, 100, 2)', vn_id_reserva, vn_km_veh - 1)));

  CALL sp_iniciar_alquiler(vn_id_reserva, vn_km_veh + 5, 100, 2, vn_id_alquiler);
  PERFORM pg_temp.fn_verificar('A3 sp_iniciar_alquiler crea alquiler ACTIVO', 'ACTIVO',
          (SELECT estado FROM alquiler WHERE id_alquiler = vn_id_alquiler));
  PERFORM pg_temp.fn_verificar('A3 y deja la reserva ACTIVA', 'ACTIVA',
          (SELECT estado FROM reserva WHERE id_reserva = vn_id_reserva));
  PERFORM pg_temp.fn_verificar('A4 Segundo alquiler de la misma reserva -> e_transicion_invalida', 'SR003',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_iniciar_alquiler(%s, %s, 100, 2)', vn_id_reserva, vn_km_veh + 5)));

  PERFORM pg_temp.fn_verificar('A5 Cerrar sin inspección -> e_cierre_invalido (RN-05)', 'SR004',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_cerrar_alquiler(%s, %s, 80, NULL, 2)', vn_id_alquiler, vn_km_veh + 400)));
  PERFORM pg_temp.fn_verificar('A6 km de entrada menor que salida -> e_parametro_invalido', 'SR007',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_cerrar_alquiler(%s, %s, 80, %L, 2)', vn_id_alquiler, vn_km_veh, 'insp-x')));

  -- A7: atomicidad. Tipo de pago inválido: falla al insertar el pago,
  -- después de haber actualizado el alquiler y creado cargos.
  -- Todo debe revertirse.
  SELECT fecha_fin INTO vd_fin FROM reserva WHERE id_reserva = vn_id_reserva;
  PERFORM pg_temp.fn_verificar('A7 Falla a mitad del cierre (tipo de pago inválido)', '23514',
          pg_temp.fn_sqlstate_de(format(
            'CALL sirav.sp_cerrar_alquiler(%s, %s, 80, %L, 2, 0, %L, %L)',
            vn_id_alquiler, vn_km_veh + 400, 'insp-x', 'BITCOIN', (vd_fin + 2)::text || ' 10:00-05')));
  PERFORM pg_temp.fn_verificar('A7 y el alquiler sigue ACTIVO sin devolución', 'ACTIVO|',
          (SELECT estado || '|' || COALESCE(km_entrada::text, '') FROM alquiler WHERE id_alquiler = vn_id_alquiler));
  PERFORM pg_temp.fn_verificar('A7 y no quedó ningún cargo a medias', '0',
          (SELECT count(*)::text FROM cargo_adicional WHERE id_alquiler = vn_id_alquiler));

  -- A8: cierre correcto con 2 días de retraso y 100.000 de daños
  --     3 días x 110.000 + 2 x 55.000 + 100.000 = 540.000
  CALL sp_cerrar_alquiler(vn_id_alquiler, vn_km_veh + 400, 80, '665f1c2ab3e4d5f6a7b8c9d0', 2,
                          100000, 'TARJETA', ((vd_fin + 2)::text || ' 10:00-05')::timestamptz, vn_total);
  PERFORM pg_temp.fn_verificar('A8 Total = 330.000 + 110.000 retraso + 100.000 daños', '540000.00', vn_total::text);
  PERFORM pg_temp.fn_verificar('A8 Cargo de retraso calculado por la función', '110000.00',
          (SELECT monto::text FROM cargo_adicional WHERE id_alquiler = vn_id_alquiler AND concepto = 'RETRASO'));
  PERFORM pg_temp.fn_verificar('A8 Pago de prueba registrado', '540000.00|APROBADO',
          (SELECT monto::text || '|' || estado FROM pago WHERE id_alquiler = vn_id_alquiler));
  PERFORM pg_temp.fn_verificar('A8 Alquiler CERRADO y reserva CERRADA', 'CERRADO|CERRADA',
          (SELECT a.estado || '|' || r.estado FROM alquiler a JOIN reserva r USING (id_reserva) WHERE a.id_alquiler = vn_id_alquiler));
  PERFORM pg_temp.fn_verificar('A8 Kilometraje del vehículo actualizado', (vn_km_veh + 400)::text,
          (SELECT kilometraje_actual::text FROM vehiculo WHERE id_vehiculo = 4));
  PERFORM pg_temp.fn_verificar('A9 Cerrar dos veces -> e_cierre_invalido', 'SR004',
          pg_temp.fn_sqlstate_de(format('CALL sirav.sp_cerrar_alquiler(%s, %s, 80, %L, 2)', vn_id_alquiler, vn_km_veh + 500, 'insp-y')));
END $$;

ROLLBACK;
