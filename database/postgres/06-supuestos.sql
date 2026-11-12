-- Ampliaciones exigidas por Supuestos_SIRAV.docx. Reejecutable y sin borrar datos.
CREATE OR REPLACE FUNCTION fn_calcular_costo(param_reserva BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
 SELECT round((r.fecha_fin-r.fecha_inicio)*t.valor_diario,2)
 FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_reserva=param_reserva
$$;
CREATE OR REPLACE FUNCTION fn_calcular_cargo_retraso(param_reserva BIGINT,param_devolucion TIMESTAMPTZ) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
 SELECT round(greatest(0,(param_devolucion AT TIME ZONE 'America/Bogota')::date-r.fecha_fin)*t.valor_diario*0.5,2)
 FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_reserva=param_reserva
$$;

CREATE OR REPLACE FUNCTION trg_proteger_tarifa_historica() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM reserva WHERE id_tarifa=OLD.id_tarifa)
 AND (NEW.id_categoria,NEW.valor_diario,NEW.vigente_desde) IS DISTINCT FROM (OLD.id_categoria,OLD.valor_diario,OLD.vigente_desde)
 THEN RAISE EXCEPTION 'Una tarifa utilizada es histórica: cierre su vigencia y cree una nueva' USING ERRCODE='SR008', HINT='e_tarifa_historica'; END IF;
 IF NEW.vigente_hasta IS NOT NULL AND EXISTS(SELECT 1 FROM reserva WHERE id_tarifa=OLD.id_tarifa AND fecha_fin>NEW.vigente_hasta)
 THEN RAISE EXCEPTION 'La vigencia debe cubrir las reservas ya asociadas' USING ERRCODE='SR008', HINT='e_tarifa_historica'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER trg_proteger_tarifa_historica BEFORE UPDATE ON tarifa FOR EACH ROW EXECUTE FUNCTION trg_proteger_tarifa_historica();

-- Flota inicial: cinco categorías y veinticinco vehículos ficticios en una sede.
INSERT INTO categoria_vehiculo(nombre,descripcion) VALUES
 ('Camioneta','Vehículos de carga y recorridos de trabajo'),('Van','Transporte de grupos') ON CONFLICT(nombre) DO NOTHING;
INSERT INTO tarifa(id_categoria,valor_diario,vigente_desde)
 SELECT c.id_categoria,CASE c.nombre WHEN 'Camioneta' THEN 300000 ELSE 350000 END,'2020-01-01'::date
 FROM categoria_vehiculo c WHERE c.nombre IN ('Camioneta','Van') AND NOT EXISTS(SELECT 1 FROM tarifa t WHERE t.id_categoria=c.id_categoria);
INSERT INTO vehiculo(id_categoria,placa,marca,modelo,anio,color,kilometraje_actual,estado_operativo)
 SELECT c.id_categoria,d.placa,d.marca,d.modelo,2025,d.color,d.km,'DISPONIBLE'
 FROM (VALUES
 ('Compacto','SIR103','Chevrolet','Onix','Gris',11000),('Compacto','SIR104','Suzuki','Swift','Rojo',14000),('Compacto','SIR105','Hyundai','Grand i10','Blanco',9000),
 ('SUV','SIR203','Toyota','RAV4','Plata',18000),('SUV','SIR204','Kia','Seltos','Negro',13000),('SUV','SIR205','Hyundai','Creta','Azul',16000),
 ('Sedán','SIR303','Chevrolet','Onix Turbo','Plata',12000),('Sedán','SIR304','Volkswagen','Virtus','Blanco',17000),('Sedán','SIR305','Mazda','Mazda 3','Rojo',19000),
 ('Camioneta','SIR401','Toyota','Hilux','Blanco',22000),('Camioneta','SIR402','Ford','Ranger','Negro',24000),('Camioneta','SIR403','Nissan','Frontier','Gris',26000),('Camioneta','SIR404','Chevrolet','Colorado','Rojo',20000),('Camioneta','SIR405','Mitsubishi','L200','Plata',23000),
 ('Van','SIR501','Renault','Trafic','Blanco',28000),('Van','SIR502','Hyundai','Staria','Gris',21000),('Van','SIR503','Kia','Carnival','Negro',18000),('Van','SIR504','Peugeot','Traveller','Plata',27000),('Van','SIR505','Citroen','SpaceTourer','Azul',25000)
 ) AS d(categoria,placa,marca,modelo,color,km) JOIN categoria_vehiculo c ON c.nombre=d.categoria
 ON CONFLICT(placa) DO NOTHING;

-- Solo lo invoca el arranque de demostración con SEED_DEMO=true.
-- Historial deliberado: permite demostrar puntuales, tardíos, empates y cancelaciones.
CREATE OR REPLACE PROCEDURE sp_cargar_historial_demo()
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE vn_actor BIGINT;vn_cliente BIGINT;r_vehiculo vehiculo;r_tarifa tarifa;vn_reserva BIGINT;vn_alquiler BIGINT;
 vd_inicio DATE;vd_fin DATE;vd_entrega TIMESTAMPTZ;vd_devolucion TIMESTAMPTZ;vn_extra NUMERIC;vv_clave UUID;
 vv_placas TEXT[]:=ARRAY['SIR101','SIR102','SIR201','SIR202','SIR301','SIR302','SIR103','SIR203','SIR303','SIR401'];
BEGIN
 SELECT id_usuario INTO vn_actor FROM usuario WHERE email='operador@sirav.local';
 SELECT id_cliente INTO vn_cliente FROM cliente WHERE documento='DEMO-001';
 IF vn_actor IS NULL OR vn_cliente IS NULL THEN RETURN; END IF;
 PERFORM set_config('sirav.actor',vn_actor::text,true);
 FOR i IN 1..10 LOOP
  vv_clave:=('70f00000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid;
  IF EXISTS(SELECT 1 FROM reserva WHERE idempotencia=vv_clave) THEN CONTINUE; END IF;
  SELECT * INTO r_vehiculo FROM vehiculo WHERE placa=vv_placas[i] AND estado_operativo='DISPONIBLE' FOR UPDATE;
  IF NOT FOUND THEN CONTINUE; END IF;
  vd_inicio:=(now() AT TIME ZONE 'America/Bogota')::date-8+(i%3);vd_fin:=vd_inicio+2;
  vd_entrega:=(vd_inicio+time '09:00') AT TIME ZONE 'America/Bogota';
  vd_devolucion:=((vd_fin+CASE WHEN i%2=0 THEN 1 ELSE 0 END)+time '10:00') AT TIME ZONE 'America/Bogota';
  IF EXISTS(SELECT 1 FROM reserva WHERE id_vehiculo=r_vehiculo.id_vehiculo AND estado<>'CANCELADA' AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(vd_inicio,(vd_devolucion AT TIME ZONE 'America/Bogota')::date+1,'[)')) THEN CONTINUE; END IF;
  SELECT * INTO r_tarifa FROM tarifa WHERE id_categoria=r_vehiculo.id_categoria AND vigente_desde<=vd_inicio AND (vigente_hasta IS NULL OR vigente_hasta>=vd_fin) ORDER BY vigente_desde DESC LIMIT 1;
  IF NOT FOUND THEN CONTINUE; END IF;
  INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,fecha_solicitud,estado,idempotencia)
  VALUES(vn_cliente,r_vehiculo.id_vehiculo,r_tarifa.id_tarifa,vd_inicio,vd_fin,vd_entrega-interval '1 day','CERRADA',vv_clave) RETURNING id_reserva INTO vn_reserva;
  INSERT INTO alquiler(id_reserva,fecha_entrega,fecha_devolucion,km_salida,km_entrada,combustible_salida,combustible_entrada,estado)
  VALUES(vn_reserva,vd_entrega,vd_devolucion,greatest(0,r_vehiculo.kilometraje_actual-100),r_vehiculo.kilometraje_actual,100,75,'CERRADA') RETURNING id_alquiler INTO vn_alquiler;
  vn_extra:=fn_calcular_cargo_retraso(vn_reserva,vd_devolucion);
  IF vn_extra>0 THEN INSERT INTO cargo_adicional(id_alquiler,concepto,descripcion,monto,fecha_registro) VALUES(vn_alquiler,'RETRASO','Cargo de demostración',vn_extra,vd_devolucion); END IF;
  INSERT INTO pago(id_alquiler,monto,tipo,estado,fecha_pago) VALUES(vn_alquiler,fn_calcular_costo(vn_reserva)+vn_extra,'SIMULADO','APROBADO',vd_devolucion);
  INSERT INTO evento_outbox(coleccion,documento)
   SELECT 'inspecciones_vehiculo',jsonb_build_object('alquilerId',vn_alquiler,'vehiculoId',r_vehiculo.id_vehiculo,'categoriaId',r_vehiculo.id_categoria,'tipo',tipo,'fecha',CASE WHEN tipo='ENTREGA' THEN vd_entrega ELSE vd_devolucion END,'actor',vn_actor,'kilometraje',CASE WHEN tipo='ENTREGA' THEN greatest(0,r_vehiculo.kilometraje_actual-100) ELSE r_vehiculo.kilometraje_actual END,'combustible',CASE WHEN tipo='ENTREGA' THEN 100 ELSE 75 END,'danos',CASE WHEN tipo='DEVOLUCION' AND i%2=0 THEN jsonb_build_array(jsonb_build_object('zona','Parachoques','severidad','ALTA','descripcion','Incidencia ficticia para reportes')) ELSE '[]'::jsonb END,'evidencias','[]'::jsonb,'observaciones','Historial académico ficticio','anulada',false,'version',0)
   FROM (VALUES('ENTREGA'),('DEVOLUCION')) tipos(tipo);
 END LOOP;
 vv_clave:='70f00000-0000-4000-8000-000000000020'::uuid;
 IF NOT EXISTS(SELECT 1 FROM reserva WHERE idempotencia=vv_clave) THEN
  SELECT * INTO r_vehiculo FROM vehiculo WHERE placa='SIR501';
  SELECT * INTO r_tarifa FROM tarifa WHERE id_categoria=r_vehiculo.id_categoria ORDER BY vigente_desde LIMIT 1;
  INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado,idempotencia)
  VALUES(vn_cliente,r_vehiculo.id_vehiculo,r_tarifa.id_tarifa,(now() AT TIME ZONE 'America/Bogota')::date-4,(now() AT TIME ZONE 'America/Bogota')::date-2,'CANCELADA',vv_clave);
 END IF;
END $$;
GRANT DELETE ON usuario_rol TO sirav_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO sirav_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO sirav_app;
