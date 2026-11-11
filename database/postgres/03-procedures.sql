-- SECURITY DEFINER + search_path cerrado. El usuario de la API no modifica reservas directamente.
CREATE OR REPLACE PROCEDURE sp_crear_reserva(param_actor BIGINT,param_cliente BIGINT,param_vehiculo BIGINT,param_inicio DATE,param_fin DATE,param_clave UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE vn_tarifa BIGINT; r_previa reserva;
BEGIN
 PERFORM set_config('sirav.actor',param_actor::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended(param_clave::text,0));
 SELECT * INTO r_previa FROM reserva WHERE idempotencia=param_clave;
 IF FOUND THEN
  IF (r_previa.id_cliente,r_previa.id_vehiculo,r_previa.fecha_inicio,r_previa.fecha_fin) IS DISTINCT FROM (param_cliente,param_vehiculo,param_inicio,param_fin) THEN RAISE EXCEPTION 'La clave de idempotencia ya se usó con otros datos' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
  RETURN;
 END IF;
 IF param_inicio<(now() AT TIME ZONE 'America/Bogota')::date OR param_fin<=param_inicio THEN RAISE EXCEPTION 'Fechas de reserva inválidas' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=param_vehiculo FOR UPDATE;
 IF NOT fn_vehiculo_disponible(param_vehiculo,param_inicio,param_fin) THEN RAISE EXCEPTION 'El vehículo no está disponible en esas fechas' USING ERRCODE='SR001', HINT='e_reserva_solapada'; END IF;
 SELECT t.id_tarifa INTO vn_tarifa FROM tarifa t JOIN vehiculo v USING(id_categoria) WHERE v.id_vehiculo=param_vehiculo AND t.vigente_desde<=param_inicio AND (t.vigente_hasta IS NULL OR t.vigente_hasta>=param_fin);
 IF vn_tarifa IS NULL THEN RAISE EXCEPTION 'No existe tarifa vigente para el período' USING ERRCODE='SR006', HINT='e_tarifa_no_vigente'; END IF;
 INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado,idempotencia) VALUES(param_cliente,param_vehiculo,vn_tarifa,param_inicio,param_fin,'SOLICITADA',param_clave);
EXCEPTION WHEN exclusion_violation THEN RAISE EXCEPTION 'Otra reserva ocupa el período seleccionado' USING ERRCODE='SR001', HINT='e_reserva_solapada';
END $$;

CREATE OR REPLACE PROCEDURE sp_confirmar_reserva(param_actor BIGINT,param_reserva BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM set_config('sirav.actor',param_actor::text,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=param_reserva) FOR UPDATE;
 UPDATE reserva SET estado='CONFIRMADA' WHERE id_reserva=param_reserva AND estado='SOLICITADA';
 IF NOT FOUND THEN RAISE EXCEPTION 'Solo se pueden confirmar reservas solicitadas' USING ERRCODE='SR003', HINT='e_transicion_invalida'; END IF;
END $$;
CREATE OR REPLACE PROCEDURE sp_cancelar_reserva(param_actor BIGINT,param_reserva BIGINT,param_motivo TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF length(trim(param_motivo))<5 THEN RAISE EXCEPTION 'Indique un motivo de al menos cinco caracteres' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
 PERFORM set_config('sirav.actor',param_actor::text,true);
 PERFORM set_config('sirav.motivo',param_motivo,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=param_reserva) FOR UPDATE;
 UPDATE reserva SET estado='CANCELADA' WHERE id_reserva=param_reserva AND estado IN ('SOLICITADA','CONFIRMADA');
 IF NOT FOUND THEN RAISE EXCEPTION 'Esta reserva ya no se puede cancelar' USING ERRCODE='SR003', HINT='e_transicion_invalida'; END IF;
END $$;

CREATE OR REPLACE PROCEDURE sp_iniciar_alquiler(param_actor BIGINT,param_reserva BIGINT,param_km INTEGER,param_combustible NUMERIC,param_inspeccion JSONB)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r_reserva reserva; r_vehiculo vehiculo; vn_id BIGINT;
BEGIN
 PERFORM set_config('sirav.actor',param_actor::text,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=param_reserva) FOR UPDATE;
 SELECT * INTO r_reserva FROM reserva WHERE id_reserva=param_reserva FOR UPDATE;
 IF NOT FOUND OR r_reserva.estado<>'CONFIRMADA' THEN RAISE EXCEPTION 'La reserva debe estar confirmada' USING ERRCODE='SR003', HINT='e_transicion_invalida'; END IF;
 SELECT * INTO r_vehiculo FROM vehiculo WHERE id_vehiculo=r_reserva.id_vehiculo FOR UPDATE;
 IF r_vehiculo.estado_operativo<>'DISPONIBLE' THEN RAISE EXCEPTION 'El vehículo no está disponible para entrega' USING ERRCODE='SR005', HINT='e_vehiculo_no_disponible'; END IF;
 IF (now() AT TIME ZONE 'America/Bogota')::date < r_reserva.fecha_inicio OR (now() AT TIME ZONE 'America/Bogota')::date>=r_reserva.fecha_fin THEN RAISE EXCEPTION 'La entrega debe realizarse dentro del período reservado' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
 IF param_km<r_vehiculo.kilometraje_actual THEN RAISE EXCEPTION 'El kilometraje no puede disminuir' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
 IF param_inspeccion IS NULL OR jsonb_typeof(param_inspeccion->'danos') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Debe registrar la inspección de entrega' USING ERRCODE='SR004', HINT='e_inspeccion_requerida'; END IF;
 INSERT INTO alquiler(id_reserva,fecha_entrega,km_salida,combustible_salida,estado) VALUES(param_reserva,now(),param_km,param_combustible,'ACTIVA') RETURNING id_alquiler INTO vn_id;
 UPDATE reserva SET estado='ACTIVA' WHERE id_reserva=param_reserva;
 INSERT INTO evento_outbox(coleccion,documento) VALUES('inspecciones_vehiculo',param_inspeccion||jsonb_build_object('alquilerId',vn_id,'vehiculoId',r_vehiculo.id_vehiculo,'categoriaId',r_vehiculo.id_categoria,'tipo','ENTREGA','kilometraje',param_km,'combustible',param_combustible,'actor',param_actor,'fecha',now(),'anulada',false,'version',0));
END $$;

CREATE OR REPLACE PROCEDURE sp_cerrar_alquiler(param_actor BIGINT,param_alquiler BIGINT,param_km INTEGER,param_combustible NUMERIC,param_inspeccion JSONB)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r_alquiler alquiler; r_reserva reserva; r_vehiculo vehiculo; vn_cargo NUMERIC; vn_total NUMERIC;
BEGIN
 PERFORM set_config('sirav.actor',param_actor::text,true);
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=(SELECT r.id_vehiculo FROM reserva r JOIN alquiler a USING(id_reserva) WHERE a.id_alquiler=param_alquiler) FOR UPDATE;
 SELECT * INTO r_alquiler FROM alquiler WHERE id_alquiler=param_alquiler FOR UPDATE;
 IF NOT FOUND OR r_alquiler.estado<>'ACTIVA' THEN RAISE EXCEPTION 'El alquiler no está activo' USING ERRCODE='SR003', HINT='e_transicion_invalida'; END IF;
 SELECT * INTO r_reserva FROM reserva WHERE id_reserva=r_alquiler.id_reserva FOR UPDATE;
 SELECT * INTO r_vehiculo FROM vehiculo WHERE id_vehiculo=r_reserva.id_vehiculo FOR UPDATE;
 IF param_km<r_alquiler.km_salida THEN RAISE EXCEPTION 'El kilometraje de entrada debe ser mayor o igual al de salida' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
 IF param_inspeccion IS NULL OR jsonb_typeof(param_inspeccion->'danos') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Debe registrar la inspección de devolución' USING ERRCODE='SR004', HINT='e_inspeccion_requerida'; END IF;
 vn_cargo:=fn_calcular_cargo_retraso(r_reserva.id_reserva,now());
 IF vn_cargo>0 THEN INSERT INTO cargo_adicional(id_alquiler,concepto,descripcion,monto) VALUES(param_alquiler,'RETRASO','50% de tarifa diaria por día calendario de retraso',vn_cargo); END IF;
 vn_total:=fn_calcular_costo(r_reserva.id_reserva)+(SELECT coalesce(sum(monto),0) FROM cargo_adicional WHERE id_alquiler=param_alquiler);
 UPDATE alquiler SET fecha_devolucion=now(),km_entrada=param_km,combustible_entrada=param_combustible,estado='CERRADA' WHERE id_alquiler=param_alquiler;
 UPDATE reserva SET estado='CERRADA' WHERE id_reserva=r_reserva.id_reserva;
 INSERT INTO pago(id_alquiler,monto,tipo,estado) VALUES(param_alquiler,vn_total,'SIMULADO','APROBADO');
 INSERT INTO evento_outbox(coleccion,documento) VALUES('inspecciones_vehiculo',param_inspeccion||jsonb_build_object('alquilerId',param_alquiler,'vehiculoId',r_vehiculo.id_vehiculo,'categoriaId',r_vehiculo.id_categoria,'tipo','DEVOLUCION','kilometraje',param_km,'combustible',param_combustible,'actor',param_actor,'fecha',now(),'anulada',false,'version',0));
END $$;
