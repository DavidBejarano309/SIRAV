-- Reglas de operación adicionales al esquema revisado 3FN del usuario.
ALTER TABLE usuario ADD CONSTRAINT ck_email_lower CHECK(email=lower(email));
ALTER TABLE vehiculo ADD CONSTRAINT ck_vehiculo CHECK (anio BETWEEN 1950 AND 2100 AND kilometraje_actual>=0 AND estado_operativo IN ('DISPONIBLE','ALQUILADO','INACTIVO'));
ALTER TABLE tarifa ADD CONSTRAINT ck_tarifa CHECK(valor_diario>0 AND (vigente_hasta IS NULL OR vigente_hasta>vigente_desde));
ALTER TABLE tarifa ADD CONSTRAINT ex_tarifa EXCLUDE USING gist(id_categoria WITH =, daterange(vigente_desde,vigente_hasta,'[)') WITH &&);
ALTER TABLE reserva ADD COLUMN idempotencia UUID NOT NULL UNIQUE DEFAULT gen_random_uuid();
ALTER TABLE reserva ADD CONSTRAINT ck_reserva CHECK(fecha_fin>fecha_inicio AND estado IN ('SOLICITADA','CONFIRMADA','ACTIVA','CERRADA','CANCELADA'));
-- La exclusión de reservas ya viene definida en 01-schema.sql.
ALTER TABLE mantenimiento ADD CONSTRAINT ck_mantenimiento CHECK(fecha_fin>fecha_inicio AND estado IN ('PROGRAMADO','COMPLETADO','CANCELADO'));
ALTER TABLE mantenimiento ADD CONSTRAINT ex_mantenimiento EXCLUDE USING gist(id_vehiculo WITH =,daterange(fecha_inicio,fecha_fin,'[)') WITH &&) WHERE (estado='PROGRAMADO');
ALTER TABLE alquiler ADD CONSTRAINT ck_alquiler CHECK(estado IN ('ACTIVA','CERRADA') AND km_salida>=0 AND (km_entrada IS NULL OR km_entrada>=km_salida) AND combustible_salida BETWEEN 0 AND 100 AND (combustible_entrada IS NULL OR combustible_entrada BETWEEN 0 AND 100));
ALTER TABLE alquiler ADD CONSTRAINT ck_devolucion CHECK((estado='ACTIVA' AND fecha_devolucion IS NULL) OR (estado='CERRADA' AND fecha_devolucion>=fecha_entrega AND km_entrada IS NOT NULL AND combustible_entrada IS NOT NULL));
ALTER TABLE pago ADD CONSTRAINT ck_pago CHECK(monto>=0 AND tipo='SIMULADO' AND estado IN ('APROBADO','ANULADO'));
CREATE INDEX ix_reserva_cliente ON reserva(id_cliente,fecha_solicitud DESC);
CREATE INDEX ix_pago_alquiler ON pago(id_alquiler);
CREATE INDEX ix_cargo_alquiler ON cargo_adicional(id_alquiler);
CREATE INDEX ix_auditoria_reserva ON auditoria_reserva(id_reserva,fecha_evento);
CREATE INDEX ix_vehiculo_categoria ON vehiculo(id_categoria);

-- Infraestructura de integración, adicional a las 13 entidades del modelo.
-- La transacción SQL conserva el documento hasta que MongoDB confirma su escritura.
CREATE TABLE evento_outbox (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), coleccion VARCHAR(50) NOT NULL,
 documento JSONB NOT NULL, creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
 publicado_en TIMESTAMPTZ, intentos INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX ix_outbox_pendiente ON evento_outbox(creado_en) WHERE publicado_en IS NULL;

CREATE FUNCTION fn_actor() RETURNS BIGINT LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('sirav.actor',true),'')::bigint
$$;
CREATE FUNCTION fn_vehiculo_disponible(param_vehiculo BIGINT,param_inicio DATE,param_fin DATE) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
 SELECT param_fin>param_inicio AND EXISTS(SELECT 1 FROM vehiculo v WHERE v.id_vehiculo=param_vehiculo AND v.estado_operativo<>'INACTIVO')
 AND NOT EXISTS(SELECT 1 FROM reserva r WHERE r.id_vehiculo=param_vehiculo AND r.estado IN ('SOLICITADA','CONFIRMADA','ACTIVA') AND daterange(r.fecha_inicio,r.fecha_fin,'[)') && daterange(param_inicio,param_fin,'[)'))
 AND NOT EXISTS(SELECT 1 FROM mantenimiento m WHERE m.id_vehiculo=param_vehiculo AND m.estado='PROGRAMADO' AND daterange(m.fecha_inicio,m.fecha_fin,'[)') && daterange(param_inicio,param_fin,'[)'))
$$;
CREATE FUNCTION fn_calcular_costo(param_reserva BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
 SELECT (r.fecha_fin-r.fecha_inicio)*t.valor_diario FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_reserva=param_reserva
$$;
CREATE FUNCTION fn_calcular_cargo_retraso(param_reserva BIGINT,param_devolucion TIMESTAMPTZ) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
 SELECT greatest(0,(param_devolucion AT TIME ZONE 'America/Bogota')::date-r.fecha_fin)*t.valor_diario*0.5
 FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_reserva=param_reserva
$$;
CREATE FUNCTION trg_validar_reserva() RETURNS TRIGGER LANGUAGE plpgsql AS $$
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
  PERFORM 1 FROM tarifa WHERE id_tarifa=NEW.id_tarifa AND id_categoria=vn_categoria AND vigente_desde<=NEW.fecha_inicio AND (vigente_hasta IS NULL OR vigente_hasta>=NEW.fecha_fin) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe una tarifa que cubra el período' USING ERRCODE='SR006', HINT='e_tarifa_no_vigente'; END IF;
  IF EXISTS(SELECT 1 FROM mantenimiento WHERE id_vehiculo=NEW.id_vehiculo AND estado='PROGRAMADO' AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(NEW.fecha_inicio,NEW.fecha_fin,'[)')) THEN RAISE EXCEPTION 'El vehículo tiene mantenimiento en ese período' USING ERRCODE='SR002', HINT='e_mantenimiento_solapado'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_validar_transicion_reserva BEFORE INSERT OR UPDATE ON reserva FOR EACH ROW EXECUTE FUNCTION trg_validar_reserva();
CREATE FUNCTION trg_validar_mantenimiento() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=NEW.id_vehiculo FOR UPDATE;
 IF NEW.estado='PROGRAMADO' AND EXISTS(SELECT 1 FROM reserva WHERE id_vehiculo=NEW.id_vehiculo AND estado IN ('SOLICITADA','CONFIRMADA','ACTIVA') AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(NEW.fecha_inicio,NEW.fecha_fin,'[)')) THEN RAISE EXCEPTION 'El mantenimiento coincide con una reserva vigente' USING ERRCODE='SR002', HINT='e_mantenimiento_solapado'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_validar_mantenimiento BEFORE INSERT OR UPDATE ON mantenimiento FOR EACH ROW EXECUTE FUNCTION trg_validar_mantenimiento();
CREATE FUNCTION trg_auditar_reserva() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' OR NEW.estado<>OLD.estado THEN
  INSERT INTO auditoria_reserva(id_reserva,id_usuario,estado_anterior,estado_nuevo,observacion)
  VALUES(NEW.id_reserva,fn_actor(),CASE WHEN TG_OP='UPDATE' THEN OLD.estado END,NEW.estado,nullif(current_setting('sirav.motivo',true),''));
  INSERT INTO evento_outbox(coleccion,documento) VALUES('bitacora_operaciones',jsonb_build_object('accion','RESERVA_'||NEW.estado,'actor',fn_actor(),'reservaId',NEW.id_reserva,'fecha',now()));
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_auditar_reserva AFTER INSERT OR UPDATE ON reserva FOR EACH ROW EXECUTE FUNCTION trg_auditar_reserva();
CREATE FUNCTION trg_actualizar_estado_vehiculo() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 UPDATE vehiculo SET estado_operativo=CASE WHEN NEW.estado='ACTIVA' THEN 'ALQUILADO' ELSE 'DISPONIBLE' END,
 kilometraje_actual=coalesce(NEW.km_entrada,NEW.km_salida) WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=NEW.id_reserva);
 RETURN NEW;
END $$;
CREATE TRIGGER trg_actualizar_estado_vehiculo AFTER INSERT OR UPDATE ON alquiler FOR EACH ROW EXECUTE FUNCTION trg_actualizar_estado_vehiculo();
