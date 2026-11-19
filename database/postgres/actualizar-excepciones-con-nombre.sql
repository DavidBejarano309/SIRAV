-- SIRAV · Actualiza una base sirav_3fn ya instalada a las excepciones con nombre (SR001 a SR008),
-- a las convenciones param_/vn_/r_ y a los perfiles sirav_reportes y sirav_admin.
-- Conserva todos los datos. Reejecutable. Generado desde 02 a 07; no editar a mano.
-- Uso (como sirav_owner):
--   psql -v ON_ERROR_STOP=1 -d sirav_3fn -f database/postgres/actualizar-excepciones-con-nombre.sql
-- En las VM: copiar el archivo y ejecutarlo dentro del contenedor sirav-postgres (ver la guía de instalación).
\set ON_ERROR_STOP on
BEGIN;
-- Los parámetros cambiaron de nombre: PostgreSQL exige borrar y crear de nuevo estas rutinas.
DROP VIEW IF EXISTS v_reservas;
DROP FUNCTION IF EXISTS fn_vehiculo_disponible(BIGINT, DATE, DATE);
DROP FUNCTION IF EXISTS fn_calcular_costo(BIGINT);
DROP FUNCTION IF EXISTS fn_calcular_cargo_retraso(BIGINT, TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS sp_crear_reserva(BIGINT, BIGINT, BIGINT, DATE, DATE, UUID);
DROP PROCEDURE IF EXISTS sp_confirmar_reserva(BIGINT, BIGINT);
DROP PROCEDURE IF EXISTS sp_cancelar_reserva(BIGINT, BIGINT, TEXT);
DROP PROCEDURE IF EXISTS sp_iniciar_alquiler(BIGINT, BIGINT, INTEGER, NUMERIC, JSONB);
DROP PROCEDURE IF EXISTS sp_cerrar_alquiler(BIGINT, BIGINT, INTEGER, NUMERIC, JSONB);

-- ===== Funciones y triggers de 02-integrity.sql (los triggers siguen apuntando a estas funciones)
CREATE OR REPLACE FUNCTION fn_actor() RETURNS BIGINT LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('sirav.actor',true),'')::bigint
$$;
CREATE OR REPLACE FUNCTION fn_vehiculo_disponible(param_vehiculo BIGINT,param_inicio DATE,param_fin DATE) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
 SELECT param_fin>param_inicio AND EXISTS(SELECT 1 FROM vehiculo v WHERE v.id_vehiculo=param_vehiculo AND v.estado_operativo<>'INACTIVO')
 AND NOT EXISTS(SELECT 1 FROM reserva r WHERE r.id_vehiculo=param_vehiculo AND r.estado IN ('SOLICITADA','CONFIRMADA','ACTIVA') AND daterange(r.fecha_inicio,r.fecha_fin,'[)') && daterange(param_inicio,param_fin,'[)'))
 AND NOT EXISTS(SELECT 1 FROM mantenimiento m WHERE m.id_vehiculo=param_vehiculo AND m.estado='PROGRAMADO' AND daterange(m.fecha_inicio,m.fecha_fin,'[)') && daterange(param_inicio,param_fin,'[)'))
$$;
CREATE OR REPLACE FUNCTION fn_calcular_costo(param_reserva BIGINT) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
 SELECT (r.fecha_fin-r.fecha_inicio)*t.valor_diario FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_reserva=param_reserva
$$;
CREATE OR REPLACE FUNCTION fn_calcular_cargo_retraso(param_reserva BIGINT,param_devolucion TIMESTAMPTZ) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
 SELECT greatest(0,(param_devolucion AT TIME ZONE 'America/Bogota')::date-r.fecha_fin)*t.valor_diario*0.5
 FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_reserva=param_reserva
$$;
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
  PERFORM 1 FROM tarifa WHERE id_tarifa=NEW.id_tarifa AND id_categoria=vn_categoria AND vigente_desde<=NEW.fecha_inicio AND (vigente_hasta IS NULL OR vigente_hasta>=NEW.fecha_fin) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe una tarifa que cubra el período' USING ERRCODE='SR006', HINT='e_tarifa_no_vigente'; END IF;
  IF EXISTS(SELECT 1 FROM mantenimiento WHERE id_vehiculo=NEW.id_vehiculo AND estado='PROGRAMADO' AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(NEW.fecha_inicio,NEW.fecha_fin,'[)')) THEN RAISE EXCEPTION 'El vehículo tiene mantenimiento en ese período' USING ERRCODE='SR002', HINT='e_mantenimiento_solapado'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION trg_validar_mantenimiento() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 PERFORM 1 FROM vehiculo WHERE id_vehiculo=NEW.id_vehiculo FOR UPDATE;
 IF NEW.estado='PROGRAMADO' AND EXISTS(SELECT 1 FROM reserva WHERE id_vehiculo=NEW.id_vehiculo AND estado IN ('SOLICITADA','CONFIRMADA','ACTIVA') AND daterange(fecha_inicio,fecha_fin,'[)') && daterange(NEW.fecha_inicio,NEW.fecha_fin,'[)')) THEN RAISE EXCEPTION 'El mantenimiento coincide con una reserva vigente' USING ERRCODE='SR002', HINT='e_mantenimiento_solapado'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION trg_auditar_reserva() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' OR NEW.estado<>OLD.estado THEN
  INSERT INTO auditoria_reserva(id_reserva,id_usuario,estado_anterior,estado_nuevo,observacion)
  VALUES(NEW.id_reserva,fn_actor(),CASE WHEN TG_OP='UPDATE' THEN OLD.estado END,NEW.estado,nullif(current_setting('sirav.motivo',true),''));
  INSERT INTO evento_outbox(coleccion,documento) VALUES('bitacora_operaciones',jsonb_build_object('accion','RESERVA_'||NEW.estado,'actor',fn_actor(),'reservaId',NEW.id_reserva,'fecha',now()));
 END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION trg_actualizar_estado_vehiculo() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 UPDATE vehiculo SET estado_operativo=CASE WHEN NEW.estado='ACTIVA' THEN 'ALQUILADO' ELSE 'DISPONIBLE' END,
 kilometraje_actual=coalesce(NEW.km_entrada,NEW.km_salida) WHERE id_vehiculo=(SELECT id_vehiculo FROM reserva WHERE id_reserva=NEW.id_reserva);
 RETURN NEW;
END $$;

-- ===== 03-procedures.sql
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
 IF param_motivo IS NULL OR length(trim(param_motivo))<5 THEN RAISE EXCEPTION 'Indique un motivo de al menos cinco caracteres' USING ERRCODE='SR007', HINT='e_parametro_invalido'; END IF;
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

-- ===== Vista v_reservas de 04-views-seed.sql
CREATE VIEW v_reservas AS
SELECT r.*, c.nombres||' '||c.apellidos cliente, c.id_usuario,
 v.placa,v.marca,v.modelo,v.id_categoria,cv.nombre categoria,t.valor_diario,
 fn_calcular_costo(r.id_reserva) costo_base,a.id_alquiler,a.estado estado_alquiler,
 a.fecha_entrega,a.fecha_devolucion,a.km_salida,a.km_entrada,
 coalesce(cargos.total,0) cargos,coalesce(pagos.total,0) pagado,v.kilometraje_actual
FROM reserva r JOIN v_cliente_contacto c USING(id_cliente) JOIN vehiculo v USING(id_vehiculo)
JOIN categoria_vehiculo cv USING(id_categoria) JOIN tarifa t ON t.id_tarifa=r.id_tarifa
LEFT JOIN alquiler a USING(id_reserva)
LEFT JOIN LATERAL(SELECT sum(monto) total FROM cargo_adicional WHERE id_alquiler=a.id_alquiler) cargos ON true
LEFT JOIN LATERAL(SELECT sum(monto) total FROM pago WHERE id_alquiler=a.id_alquiler AND estado='APROBADO') pagos ON true;

-- ===== 06-supuestos.sql (reejecutable; no duplica la flota)
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

-- ===== 07-concurrency-validation.sql
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

-- ===== 05-permissions.sql (vuelve a otorgar EXECUTE sobre las rutinas recreadas)
-- El rol sirav_app se crea antes de ejecutar este archivo.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO sirav_app;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO sirav_app;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO sirav_app;
GRANT INSERT,UPDATE ON usuario,usuario_rol,cliente,categoria_vehiculo,vehiculo,tarifa,mantenimiento,evento_outbox TO sirav_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO sirav_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO sirav_app;
-- Sin INSERT/UPDATE/DELETE directo sobre reserva, alquiler, pago y auditoría.

-- Perfiles de base de datos adicionales (NOLOGIN: se asignan con GRANT rol TO persona).
-- sirav_reportes: solo lectura para analistas; no ve credenciales ni la versión del token.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sirav_reportes') THEN CREATE ROLE sirav_reportes NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sirav_admin') THEN CREATE ROLE sirav_admin NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO sirav_reportes;
GRANT SELECT ON rol, usuario_rol, cliente, categoria_vehiculo, vehiculo, tarifa, reserva, alquiler, pago,
  cargo_adicional, mantenimiento, auditoria_reserva, v_reservas, v_cliente_contacto TO sirav_reportes;
GRANT SELECT (id_usuario, nombre, apellido, email, activo, creado_en) ON usuario TO sirav_reportes;
GRANT EXECUTE ON FUNCTION fn_calcular_costo(BIGINT), fn_vehiculo_disponible(BIGINT, DATE, DATE) TO sirav_reportes;
-- sirav_admin: administración funcional (catálogo, tarifas, mantenimiento, usuarios) y los mismos
-- procedimientos de la aplicación; tampoco modifica reserva, alquiler, pago ni auditoría directamente.
GRANT sirav_app TO sirav_admin;
GRANT DELETE ON tarifa, mantenimiento, usuario_rol TO sirav_admin;
COMMIT;
