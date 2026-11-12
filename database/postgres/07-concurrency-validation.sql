-- Correcciones verificadas con transacciones concurrentes y llamadas SQL directas.
-- Reejecutable. Aplicar con ON_ERROR_STOP y --single-transaction.
CREATE OR REPLACE FUNCTION trg_validar_reserva() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_categoria BIGINT;
BEGIN
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=NEW.id_vehiculo FOR UPDATE;
 IF TG_OP='UPDATE' AND (NEW.id_cliente,NEW.id_vehiculo,NEW.id_tarifa,NEW.fecha_inicio,NEW.fecha_fin,NEW.idempotencia) IS DISTINCT FROM (OLD.id_cliente,OLD.id_vehiculo,OLD.id_tarifa,OLD.fecha_inicio,OLD.fecha_fin,OLD.idempotencia) THEN
   RAISE EXCEPTION 'Los datos de una reserva son inmutables; cancele y cree otra' USING ERRCODE='P0001';
 END IF;
 IF TG_OP='UPDATE' AND NEW.estado<>OLD.estado AND NOT ((OLD.estado='SOLICITADA' AND NEW.estado IN ('CONFIRMADA','CANCELADA')) OR (OLD.estado='CONFIRMADA' AND NEW.estado IN ('ACTIVA','CANCELADA')) OR (OLD.estado='ACTIVA' AND NEW.estado='CERRADA')) THEN
   RAISE EXCEPTION 'Transición de reserva no permitida' USING ERRCODE='P0001';
 END IF;
 IF NEW.estado IN ('SOLICITADA','CONFIRMADA','ACTIVA') THEN
  SELECT id_categoria INTO v_categoria FROM vehiculo WHERE id_vehiculo=NEW.id_vehiculo AND estado_operativo<>'INACTIVO';
  IF NOT FOUND THEN RAISE EXCEPTION 'Vehículo inactivo o inexistente'; END IF;
  -- Mantener estable la tarifa hasta confirmar la reserva impide que otra sesión
  -- reduzca su vigencia o cambie su precio antes de que exista el historial visible.
  PERFORM 1 FROM tarifa WHERE id_tarifa=NEW.id_tarifa AND id_categoria=v_categoria AND vigente_desde<=NEW.fecha_inicio AND (vigente_hasta IS NULL OR vigente_hasta>=NEW.fecha_fin) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe una tarifa que cubra el período'; END IF;
  IF EXISTS(SELECT 1 FROM mantenimiento WHERE id_vehiculo=NEW.id_vehiculo AND estado='PROGRAMADO' AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(NEW.fecha_inicio,NEW.fecha_fin,'[)')) THEN RAISE EXCEPTION 'El vehículo tiene mantenimiento en ese período'; END IF;
 END IF;
 RETURN NEW;
END $$;

CREATE OR REPLACE PROCEDURE sp_cancelar_reserva(p_actor BIGINT,p_reserva BIGINT,p_motivo TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF p_motivo IS NULL OR length(trim(p_motivo))<5 THEN RAISE EXCEPTION 'Indique un motivo de al menos cinco caracteres'; END IF;
 PERFORM set_config('sirav.actor',p_actor::text,true);
 PERFORM set_config('sirav.motivo',p_motivo,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=p_reserva) FOR UPDATE;
 UPDATE reserva SET estado='CANCELADA' WHERE id_reserva=p_reserva AND estado IN ('SOLICITADA','CONFIRMADA');
 IF NOT FOUND THEN RAISE EXCEPTION 'Esta reserva ya no se puede cancelar'; END IF;
END $$;
