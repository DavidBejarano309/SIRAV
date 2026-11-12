-- Correcciones verificadas con transacciones concurrentes y llamadas SQL directas.
-- Reejecutable. Aplicar con ON_ERROR_STOP y --single-transaction.
CREATE OR REPLACE FUNCTION trg_validar_reserva() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE vn_categoria BIGINT;
BEGIN
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=NEW.id_vehiculo FOR UPDATE;
 IF TG_OP='UPDATE' AND (NEW.id_cliente,NEW.id_vehiculo,NEW.id_tarifa,NEW.fecha_inicio,NEW.fecha_fin,NEW.idempotencia) IS DISTINCT FROM (OLD.id_cliente,OLD.id_vehiculo,OLD.id_tarifa,OLD.fecha_inicio,OLD.fecha_fin,OLD.idempotencia) THEN
   RAISE EXCEPTION 'Los datos de una reserva son inmutables; cancele y cree otra' USING ERRCODE='SR003', HINT='e_transicion_invalida';
 END IF;
 IF TG_OP='UPDATE' AND NEW.estado<>OLD.estado AND NOT ((OLD.estado='SOLICITADA' AND NEW.estado IN ('CONFIRMADA','CANCELADA')) OR (OLD.estado='CONFIRMADA' AND NEW.estado IN ('ACTIVA','CANCELADA')) OR (OLD.estado='ACTIVA' AND NEW.estado='CERRADA')) THEN
   RAISE EXCEPTION 'Transición de reserva no permitida' USING ERRCODE='SR003', HINT='e_transicion_invalida';
 END IF;
 IF NEW.estado IN ('SOLICITADA','CONFIRMADA','ACTIVA') THEN
  SELECT id_categoria INTO vn_categoria FROM vehiculo WHERE id_vehiculo=NEW.id_vehiculo AND estado_operativo<>'INACTIVO';
  IF NOT FOUND THEN RAISE EXCEPTION 'Vehículo inactivo o inexistente' USING ERRCODE='SR005', HINT='e_vehiculo_no_disponible'; END IF;
  -- Mantener estable la tarifa hasta confirmar la reserva impide que otra sesión
  -- reduzca su vigencia o cambie su precio antes de que exista el historial visible.
  PERFORM 1 FROM tarifa WHERE id_tarifa=NEW.id_tarifa AND id_categoria=vn_categoria AND vigente_desde<=NEW.fecha_inicio AND (vigente_hasta IS NULL OR vigente_hasta>=NEW.fecha_fin) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe una tarifa que cubra el período' USING ERRCODE='SR006', HINT='e_tarifa_no_vigente'; END IF;
  IF EXISTS(SELECT 1 FROM mantenimiento WHERE id_vehiculo=NEW.id_vehiculo AND estado='PROGRAMADO' AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(NEW.fecha_inicio,NEW.fecha_fin,'[)')) THEN RAISE EXCEPTION 'El vehículo tiene mantenimiento en ese período' USING ERRCODE='SR002', HINT='e_mantenimiento_solapado'; END IF;
 END IF;
 RETURN NEW;
END $$;

CREATE OR REPLACE PROCEDURE sp_cancelar_reserva(param_actor BIGINT,param_reserva BIGINT,param_motivo TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF param_motivo IS NULL OR length(trim(param_motivo))<5 THEN RAISE EXCEPTION 'Indique un motivo de al menos cinco caracteres' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
 PERFORM set_config('sirav.actor',param_actor::text,true);
 PERFORM set_config('sirav.motivo',param_motivo,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=param_reserva) FOR UPDATE;
 UPDATE reserva SET estado='CANCELADA' WHERE id_reserva=param_reserva AND estado IN ('SOLICITADA','CONFIRMADA');
 IF NOT FOUND THEN RAISE EXCEPTION 'Esta reserva ya no se puede cancelar' USING ERRCODE='SR003', HINT='e_transicion_invalida'; END IF;
END $$;
