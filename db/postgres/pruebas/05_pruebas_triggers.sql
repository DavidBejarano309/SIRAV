-- =====================================================================
-- SIRAV - 05_pruebas_triggers.sql  (evidencia SIRAV-21)
-- Ejecutar después de 01 a 05. Muestra cada rechazo y cada registro de
-- auditoría. Todo se revierte al final. Cada NOTICE debe empezar por OK.
-- =====================================================================
SET client_min_messages = notice;
SET search_path TO sirav, public;
SET TIME ZONE 'America/Bogota';

BEGIN;

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

-- ---------------------------------------------------------------------
-- 0. Los estados cargados en 02_insercion.sql coinciden con la regla
-- ---------------------------------------------------------------------
SELECT pg_temp.fn_verificar('E0 Estado de los 25 vehículos coherente con reservas y mantenimientos', '0',
       (SELECT count(*)::text FROM vehiculo v WHERE v.estado_operativo <> fn_estado_vehiculo_calculado(v.id_vehiculo)));

DO $$
DECLARE
  vd_hoy         DATE := (now() AT TIME ZONE 'America/Bogota')::date;
  vn_id_reserva  BIGINT;
  vn_id_alquiler BIGINT;
  vn_id_mant     BIGINT;
  vn_km          INTEGER;
  vn_total       NUMERIC;
BEGIN
  -- -------------------------------------------------------------------
  -- 1. trg_validar_transicion_reserva (RN-03), escribiendo directo
  -- -------------------------------------------------------------------
  PERFORM pg_temp.fn_verificar('T1 Insertar reserva ya CONFIRMADA -> e_transicion_invalida', 'SR003',
    pg_temp.fn_sqlstate_de(format(
      'INSERT INTO sirav.reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin, estado) VALUES (1, 9, 7, %L, %L, %L)',
      vd_hoy + 70, vd_hoy + 71, 'CONFIRMADA')));
  PERFORM pg_temp.fn_verificar('T2 SOLICITADA -> ACTIVA (salta la confirmación) -> e_transicion_invalida', 'SR003',
    pg_temp.fn_sqlstate_de('UPDATE sirav.reserva SET estado = ''ACTIVA'' WHERE id_reserva = 12'));
  PERFORM pg_temp.fn_verificar('T3 CERRADA -> CANCELADA -> e_transicion_invalida', 'SR003',
    pg_temp.fn_sqlstate_de('UPDATE sirav.reserva SET estado = ''CANCELADA'' WHERE id_reserva = 1'));
  PERFORM pg_temp.fn_verificar('T4 ACTIVA -> CANCELADA -> e_transicion_invalida', 'SR003',
    pg_temp.fn_sqlstate_de('UPDATE sirav.reserva SET estado = ''CANCELADA'' WHERE id_reserva = 10'));
  PERFORM pg_temp.fn_verificar('T5 CANCELADA -> SOLICITADA (reabrir) -> e_transicion_invalida', 'SR003',
    pg_temp.fn_sqlstate_de('UPDATE sirav.reserva SET estado = ''SOLICITADA'' WHERE id_reserva = 9'));

  -- -------------------------------------------------------------------
  -- 2. trg_validar_mantenimiento (RN-02), desde los dos lados
  -- -------------------------------------------------------------------
  PERFORM pg_temp.fn_verificar('M1 Mantenimiento encima de reserva CONFIRMADA (vehículo 8) -> e_mantenimiento_solapado', 'SR002',
    pg_temp.fn_sqlstate_de(format(
      'INSERT INTO sirav.mantenimiento (id_vehiculo, fecha_inicio, fecha_fin, descripcion) VALUES (8, %L, %L, ''x'')',
      vd_hoy + 3, vd_hoy + 5)));
  INSERT INTO mantenimiento (id_vehiculo, fecha_inicio, fecha_fin, descripcion)
  VALUES (9, vd_hoy + 50, vd_hoy + 52, 'Prueba de trigger') RETURNING id_mantenimiento INTO vn_id_mant;
  PERFORM pg_temp.fn_verificar('M2 Reserva directa en fechas de mantenimiento -> e_mantenimiento_solapado', 'SR002',
    pg_temp.fn_sqlstate_de(format(
      'INSERT INTO sirav.reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin) VALUES (1, 9, 7, %L, %L)',
      vd_hoy + 51, vd_hoy + 53)));
  PERFORM pg_temp.fn_verificar('M3 Mantenimiento CANCELADO ya no bloquea', 'SIN_ERROR',
    pg_temp.fn_sqlstate_de(format(
      'UPDATE sirav.mantenimiento SET estado = ''CANCELADO'' WHERE id_mantenimiento = %s;
       INSERT INTO sirav.reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin) VALUES (1, 9, 7, %L, %L)',
      vn_id_mant, vd_hoy + 51, vd_hoy + 53)));

  -- -------------------------------------------------------------------
  -- 3 y 4. Flujo completo con los sp_: auditoría y estado del vehículo
  -- -------------------------------------------------------------------
  CALL sp_crear_reserva(4, 20, vd_hoy, vd_hoy + 2, 2, vn_id_reserva);
  PERFORM pg_temp.fn_verificar('V1 Reserva SOLICITADA: vehículo sigue DISPONIBLE', 'DISPONIBLE',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 20));

  CALL sp_confirmar_reserva(vn_id_reserva, 3);
  PERFORM pg_temp.fn_verificar('V2 Reserva CONFIRMADA: vehículo RESERVADO', 'RESERVADO',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 20));

  SELECT kilometraje_actual INTO vn_km FROM vehiculo WHERE id_vehiculo = 20;
  CALL sp_iniciar_alquiler(vn_id_reserva, vn_km, 100, 3, vn_id_alquiler);
  PERFORM pg_temp.fn_verificar('V3 Alquiler iniciado: vehículo ENTREGADO', 'ENTREGADO',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 20));

  CALL sp_cerrar_alquiler(vn_id_alquiler, vn_km + 120, 100, '665f1c2ab3e4d5f6a7b8c9d1', 3,
                          param_monto_total => vn_total);
  PERFORM pg_temp.fn_verificar('V4 Alquiler cerrado: vehículo DISPONIBLE', 'DISPONIBLE',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 20));

  PERFORM pg_temp.fn_verificar('A1 Auditoría: 4 registros (creación + 3 cambios)', '4',
    (SELECT count(*)::text FROM auditoria_reserva WHERE id_reserva = vn_id_reserva));
  PERFORM pg_temp.fn_verificar('A2 Secuencia de estados auditada', '->SOLICITADA, SOLICITADA->CONFIRMADA, CONFIRMADA->ACTIVA, ACTIVA->CERRADA',
    (SELECT string_agg(COALESCE(estado_anterior, '') || '->' || estado_nuevo, ', ' ORDER BY id_auditoria)
       FROM auditoria_reserva WHERE id_reserva = vn_id_reserva));
  PERFORM pg_temp.fn_verificar('A3 Usuarios registrados (creó 2, gestionó 3)', '2,3,3,3',
    (SELECT string_agg(id_usuario::text, ',' ORDER BY id_auditoria) FROM auditoria_reserva WHERE id_reserva = vn_id_reserva));
  PERFORM pg_temp.fn_verificar('A4 Observación de la confirmación', 'Reserva confirmada por operador',
    (SELECT observacion FROM auditoria_reserva WHERE id_reserva = vn_id_reserva AND estado_nuevo = 'CONFIRMADA'));

  -- Cancelar una CONFIRMADA libera el vehículo
  CALL sp_crear_reserva(4, 23, vd_hoy + 1, vd_hoy + 3, 2, vn_id_reserva);
  CALL sp_confirmar_reserva(vn_id_reserva, 2);
  CALL sp_cancelar_reserva(vn_id_reserva, 2, 'Prueba');
  PERFORM pg_temp.fn_verificar('V5 Confirmada y luego cancelada: vehículo DISPONIBLE', 'DISPONIBLE',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 23));
  PERFORM pg_temp.fn_verificar('A5 Observación del motivo de cancelación', 'Cancelada: Prueba',
    (SELECT observacion FROM auditoria_reserva WHERE id_reserva = vn_id_reserva AND estado_nuevo = 'CANCELADA'));

  -- Mantenimiento EN_CURSO y FINALIZADO
  INSERT INTO mantenimiento (id_vehiculo, fecha_inicio, fecha_fin, descripcion, estado)
  VALUES (24, vd_hoy, vd_hoy + 1, 'Cambio de batería', 'EN_CURSO') RETURNING id_mantenimiento INTO vn_id_mant;
  PERFORM pg_temp.fn_verificar('V6 Mantenimiento EN_CURSO: vehículo MANTENIMIENTO', 'MANTENIMIENTO',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 24));
  UPDATE mantenimiento SET estado = 'FINALIZADO' WHERE id_mantenimiento = vn_id_mant;
  PERFORM pg_temp.fn_verificar('V7 Mantenimiento FINALIZADO: vehículo DISPONIBLE', 'DISPONIBLE',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 24));

  -- Cambio directo sin sp_ también se audita
  UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = 12;
  PERFORM pg_temp.fn_verificar('A6 Cambio directo en la tabla queda auditado', 'SOLICITADA->CONFIRMADA',
    (SELECT estado_anterior || '->' || estado_nuevo FROM auditoria_reserva
      WHERE id_reserva = 12 ORDER BY id_auditoria DESC LIMIT 1));
  PERFORM pg_temp.fn_verificar('V8 y el vehículo 13 pasa a RESERVADO', 'RESERVADO',
    (SELECT estado_operativo FROM vehiculo WHERE id_vehiculo = 13));
END $$;

ROLLBACK;
