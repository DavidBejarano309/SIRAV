-- SECURITY DEFINER + search_path cerrado. El usuario de la API no modifica reservas directamente.
CREATE OR REPLACE PROCEDURE sp_crear_reserva(p_actor BIGINT,p_cliente BIGINT,p_vehiculo BIGINT,p_inicio DATE,p_fin DATE,p_clave UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_tarifa BIGINT; v_previa reserva;
BEGIN
 PERFORM set_config('sirav.actor',p_actor::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended(p_clave::text,0));
 SELECT * INTO v_previa FROM reserva WHERE idempotencia=p_clave;
 IF FOUND THEN
  IF (v_previa.id_cliente,v_previa.id_vehiculo,v_previa.fecha_inicio,v_previa.fecha_fin) IS DISTINCT FROM (p_cliente,p_vehiculo,p_inicio,p_fin) THEN RAISE EXCEPTION 'La clave de idempotencia ya se usó con otros datos'; END IF;
  RETURN;
 END IF;
 IF p_inicio<(now() AT TIME ZONE 'America/Bogota')::date OR p_fin<=p_inicio THEN RAISE EXCEPTION 'Fechas de reserva inválidas'; END IF;
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=p_vehiculo FOR UPDATE;
 IF NOT fn_vehiculo_disponible(p_vehiculo,p_inicio,p_fin) THEN RAISE EXCEPTION 'El vehículo no está disponible en esas fechas'; END IF;
 SELECT t.id_tarifa INTO v_tarifa FROM tarifa t JOIN vehiculo v USING(id_categoria) WHERE v.id_vehiculo=p_vehiculo AND t.vigente_desde<=p_inicio AND (t.vigente_hasta IS NULL OR t.vigente_hasta>=p_fin);
 IF v_tarifa IS NULL THEN RAISE EXCEPTION 'No existe tarifa vigente para el período'; END IF;
 INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado,idempotencia) VALUES(p_cliente,p_vehiculo,v_tarifa,p_inicio,p_fin,'SOLICITADA',p_clave);
EXCEPTION WHEN exclusion_violation THEN RAISE EXCEPTION 'Otra reserva ocupa el período seleccionado' USING ERRCODE='P0001';
END $$;

CREATE OR REPLACE PROCEDURE sp_confirmar_reserva(p_actor BIGINT,p_reserva BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM set_config('sirav.actor',p_actor::text,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=p_reserva) FOR UPDATE;
 UPDATE reserva SET estado='CONFIRMADA' WHERE id_reserva=p_reserva AND estado='SOLICITADA';
 IF NOT FOUND THEN RAISE EXCEPTION 'Solo se pueden confirmar reservas solicitadas'; END IF;
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

CREATE OR REPLACE PROCEDURE sp_iniciar_alquiler(p_actor BIGINT,p_reserva BIGINT,p_km INTEGER,p_combustible NUMERIC,p_inspeccion JSONB)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_reserva reserva; v_vehiculo vehiculo; v_id BIGINT;
BEGIN
 PERFORM set_config('sirav.actor',p_actor::text,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=p_reserva) FOR UPDATE;
 SELECT * INTO v_reserva FROM reserva WHERE id_reserva=p_reserva FOR UPDATE;
 IF NOT FOUND OR v_reserva.estado<>'CONFIRMADA' THEN RAISE EXCEPTION 'La reserva debe estar confirmada'; END IF;
 SELECT * INTO v_vehiculo FROM vehiculo WHERE id_vehiculo=v_reserva.id_vehiculo FOR UPDATE;
 IF v_vehiculo.estado_operativo<>'DISPONIBLE' THEN RAISE EXCEPTION 'El vehículo no está disponible para entrega'; END IF;
 IF (now() AT TIME ZONE 'America/Bogota')::date < v_reserva.fecha_inicio OR (now() AT TIME ZONE 'America/Bogota')::date>=v_reserva.fecha_fin THEN RAISE EXCEPTION 'La entrega debe realizarse dentro del período reservado'; END IF;
 IF p_km<v_vehiculo.kilometraje_actual THEN RAISE EXCEPTION 'El kilometraje no puede disminuir'; END IF;
 IF p_inspeccion IS NULL OR jsonb_typeof(p_inspeccion->'danos') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Debe registrar la inspección de entrega'; END IF;
 INSERT INTO alquiler(id_reserva,fecha_entrega,km_salida,combustible_salida,estado) VALUES(p_reserva,now(),p_km,p_combustible,'ACTIVA') RETURNING id_alquiler INTO v_id;
 UPDATE reserva SET estado='ACTIVA' WHERE id_reserva=p_reserva;
 INSERT INTO evento_outbox(coleccion,documento) VALUES('inspecciones_vehiculo',p_inspeccion||jsonb_build_object('alquilerId',v_id,'vehiculoId',v_vehiculo.id_vehiculo,'categoriaId',v_vehiculo.id_categoria,'tipo','ENTREGA','kilometraje',p_km,'combustible',p_combustible,'actor',p_actor,'fecha',now(),'anulada',false,'version',0));
END $$;

CREATE OR REPLACE PROCEDURE sp_cerrar_alquiler(p_actor BIGINT,p_alquiler BIGINT,p_km INTEGER,p_combustible NUMERIC,p_inspeccion JSONB)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_alquiler alquiler; v_reserva reserva; v_vehiculo vehiculo; v_cargo NUMERIC; v_total NUMERIC;
BEGIN
 PERFORM set_config('sirav.actor',p_actor::text,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT r.id_vehiculo FROM reserva r JOIN alquiler a USING(id_reserva) WHERE a.id_alquiler=p_alquiler) FOR UPDATE;
 SELECT * INTO v_alquiler FROM alquiler WHERE id_alquiler=p_alquiler FOR UPDATE;
 IF NOT FOUND OR v_alquiler.estado<>'ACTIVA' THEN RAISE EXCEPTION 'El alquiler no está activo'; END IF;
 SELECT * INTO v_reserva FROM reserva WHERE id_reserva=v_alquiler.id_reserva FOR UPDATE;
 SELECT * INTO v_vehiculo FROM vehiculo WHERE id_vehiculo=v_reserva.id_vehiculo FOR UPDATE;
 IF p_km<v_alquiler.km_salida THEN RAISE EXCEPTION 'El kilometraje de entrada debe ser mayor o igual al de salida'; END IF;
 IF p_inspeccion IS NULL OR jsonb_typeof(p_inspeccion->'danos') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Debe registrar la inspección de devolución'; END IF;
 v_cargo:=fn_calcular_cargo_retraso(v_reserva.id_reserva,now());
 IF v_cargo>0 THEN INSERT INTO cargo_adicional(id_alquiler,concepto,descripcion,monto) VALUES(p_alquiler,'RETRASO','50% de tarifa diaria por día calendario de retraso',v_cargo); END IF;
 v_total:=fn_calcular_costo(v_reserva.id_reserva)+(SELECT coalesce(sum(monto),0) FROM cargo_adicional WHERE id_alquiler=p_alquiler);
 UPDATE alquiler SET fecha_devolucion=now(),km_entrada=p_km,combustible_entrada=p_combustible,estado='CERRADA' WHERE id_alquiler=p_alquiler;
 UPDATE reserva SET estado='CERRADA' WHERE id_reserva=v_reserva.id_reserva;
 INSERT INTO pago(id_alquiler,monto,tipo,estado) VALUES(p_alquiler,v_total,'SIMULADO','APROBADO');
 INSERT INTO evento_outbox(coleccion,documento) VALUES('inspecciones_vehiculo',p_inspeccion||jsonb_build_object('alquilerId',p_alquiler,'vehiculoId',v_vehiculo.id_vehiculo,'categoriaId',v_vehiculo.id_categoria,'tipo','DEVOLUCION','kilometraje',p_km,'combustible',p_combustible,'actor',p_actor,'fecha',now(),'anulada',false,'version',0));
END $$;
