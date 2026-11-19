-- SIRAV: datos ficticios adicionales para la presentación y los reportes.
-- Carga 20 clientes, unos tres meses de historial por vehículo (reservas, alquileres,
-- pagos, cargos por retraso, cancelaciones e inspecciones), alquileres en curso,
-- reservas futuras y mantenimientos. Las inspecciones se escriben en evento_outbox y
-- la API las publica en MongoDB, igual que en la operación normal.
--
-- Requisitos: esquema 01 a 07 aplicado y al menos un usuario OPERADOR o ADMIN
-- (la API crea operador@sirav.local al arrancar con la carga demo).
-- Uso:  psql -d sirav_3fn -f 08-datos-presentacion.sql   y luego   CALL sp_cargar_datos_presentacion();
-- Es idempotente: si ya se cargó (existe el cliente PRES-001), no hace nada.
-- Los clientes registrados entran con la contraseña de demostración SiravDemo2026.

CREATE OR REPLACE PROCEDURE sp_cargar_datos_presentacion()
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 vn_actor BIGINT; vn_rol_cliente BIGINT; vn_usuario BIGINT; vn_cliente BIGINT;
 vn_reserva BIGINT; vn_alquiler BIGINT; vn_extra NUMERIC; vn_km INTEGER; vn_km_fin INTEGER;
 vn_k INTEGER; vn_v INTEGER; vn_dur INTEGER; vn_gap INTEGER; vn_combustible INTEGER;
 vd_hoy DATE := (now() AT TIME ZONE 'America/Bogota')::date;
 vd_inicio DATE; vd_fin DATE; vd_entrega TIMESTAMPTZ; vd_devolucion TIMESTAMPTZ;
 vb_tarde BOOLEAN; vb_dano BOOLEAN;
 vn_clientes BIGINT[] := '{}';
 vv_hash VARCHAR(100) := '$2b$12$usvJM339lPxJpxw85Etj9OoEHF/aFVc3vI9FTGA0y6Pc98jk7ueP.';
 vv_nombres TEXT[] := ARRAY['Laura','Andrés','Camila','Santiago','Valentina','Mateo','Daniela','Sebastián','Mariana','Nicolás','Paula','Juan Pablo'];
 vv_apellidos TEXT[] := ARRAY['Gómez','Rodríguez','Martínez','López','Hernández','Díaz','Moreno','Castro','Rojas','Vargas','Ramírez','Torres'];
 vv_walkin_n TEXT[] := ARRAY['Carlos','Ana María','Felipe','Lucía','Jorge','Natalia','Ricardo','Sofía'];
 vv_walkin_a TEXT[] := ARRAY['Pérez Ruiz','Suárez León','Ortiz Mejía','Cárdenas Gil','Ospina Vega','Salazar Pinto','Mendoza Ríos','Arango Cruz'];
 vv_zonas TEXT[] := ARRAY['Parachoques delantero','Puerta trasera izquierda','Espejo derecho','Rin delantero','Capó','Tapicería'];
 vv_sev TEXT[] := ARRAY['BAJA','MEDIA','ALTA'];
 r_vehiculo vehiculo; r_tarifa tarifa;
 cur_vehiculos CURSOR FOR SELECT * FROM vehiculo WHERE estado_operativo<>'INACTIVO' ORDER BY placa;
BEGIN
 IF EXISTS(SELECT 1 FROM cliente WHERE documento='PRES-001') THEN
  RAISE NOTICE 'Los datos de presentación ya estaban cargados'; RETURN;
 END IF;
 SELECT u.id_usuario INTO vn_actor FROM usuario u JOIN usuario_rol ur ON ur.id_usuario=u.id_usuario
  JOIN rol r ON r.id_rol=ur.id_rol WHERE r.nombre IN ('OPERADOR','ADMIN') ORDER BY (r.nombre='OPERADOR') DESC, u.id_usuario LIMIT 1;
 IF vn_actor IS NULL THEN
  RAISE EXCEPTION 'No hay usuario OPERADOR o ADMIN; arranque la API una vez antes de cargar estos datos';
 END IF;
 PERFORM set_config('sirav.actor',vn_actor::text,true);
 SELECT id_rol INTO vn_rol_cliente FROM rol WHERE nombre='CLIENTE';

 -- 12 clientes registrados (contacto en usuario, 3FN) y 8 clientes de mostrador.
 FOR i IN 1..12 LOOP
  INSERT INTO usuario(nombre,apellido,email,password_hash,activo)
  VALUES(vv_nombres[i],vv_apellidos[i],
         lower(translate(replace(vv_nombres[i],' ',''),'áéíóúñ','aeioun'))||'.'||lower(translate(vv_apellidos[i],'áéíóúñ','aeioun'))||'@correo.demo',
         vv_hash,true)
  RETURNING id_usuario INTO vn_usuario;
  INSERT INTO usuario_rol(id_usuario,id_rol) VALUES(vn_usuario,vn_rol_cliente);
  INSERT INTO cliente(id_usuario,documento,telefono,licencia_conduccion)
  VALUES(vn_usuario,'PRES-'||lpad(i::text,3,'0'),'300'||lpad((1234567+i*7919)::text,7,'0'),'LIC-'||(52000000+i*313))
  RETURNING id_cliente INTO vn_cliente;
  vn_clientes := vn_clientes || vn_cliente;
 END LOOP;
 FOR i IN 1..8 LOOP
  INSERT INTO cliente(nombres,apellidos,documento,telefono,email,licencia_conduccion)
  VALUES(vv_walkin_n[i],vv_walkin_a[i],'PRES-'||lpad((12+i)::text,3,'0'),'310'||lpad((7654321-i*4241)::text,7,'0'),
         'mostrador'||i||'@correo.demo','LIC-'||(79000000+i*517))
  RETURNING id_cliente INTO vn_cliente;
  vn_clientes := vn_clientes || vn_cliente;
 END LOOP;

 -- Historial: alquileres cerrados de hace unos 100 días hasta hace 12 días.
 vn_v := 0;
 FOR r_vehiculo IN cur_vehiculos LOOP
  vn_v := vn_v + 1; vn_k := 0; vn_km := r_vehiculo.kilometraje_actual;
  vd_inicio := vd_hoy - 100 + (vn_v % 5);
  SELECT * INTO r_tarifa FROM tarifa WHERE id_categoria=r_vehiculo.id_categoria AND vigente_desde<=vd_inicio
   AND (vigente_hasta IS NULL OR vigente_hasta>=vd_hoy) ORDER BY vigente_desde DESC LIMIT 1;
  CONTINUE WHEN NOT FOUND;
  LOOP
   vn_k := vn_k + 1;
   vn_dur := 2 + (vn_k*7 + vn_v*3) % 4;
   vd_fin := vd_inicio + vn_dur;
   EXIT WHEN vd_fin > vd_hoy - 12;
   vn_cliente := vn_clientes[1 + (vn_k*7 + vn_v*11) % array_length(vn_clientes,1)];
   vd_entrega := (vd_inicio + time '09:00') AT TIME ZONE 'America/Bogota';
   IF (vn_k + vn_v) % 9 = 0 THEN
    INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,fecha_solicitud,estado)
    VALUES(vn_cliente,r_vehiculo.id_vehiculo,r_tarifa.id_tarifa,vd_inicio,vd_fin,vd_entrega - interval '3 days','CANCELADA');
    vd_inicio := vd_fin + 1;
    CONTINUE;
   END IF;
   vb_tarde := (vn_k + vn_v) % 5 = 0;
   vb_dano := (vn_k + vn_v) % 6 = 0;
   vd_devolucion := ((vd_fin + CASE WHEN vb_tarde THEN 1 ELSE 0 END) + time '10:30') AT TIME ZONE 'America/Bogota';
   vn_km_fin := vn_km + 120 + (vn_k*97 + vn_v*53) % 480;
   vn_combustible := 50 + (vn_k*13 + vn_v) % 51;
   INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,fecha_solicitud,estado)
   VALUES(vn_cliente,r_vehiculo.id_vehiculo,r_tarifa.id_tarifa,vd_inicio,vd_fin,
          vd_entrega - make_interval(days => 1 + (vn_k+vn_v) % 6),'CERRADA')
   RETURNING id_reserva INTO vn_reserva;
   INSERT INTO alquiler(id_reserva,fecha_entrega,fecha_devolucion,km_salida,km_entrada,combustible_salida,combustible_entrada,estado)
   VALUES(vn_reserva,vd_entrega,vd_devolucion,vn_km,vn_km_fin,100,vn_combustible,'CERRADA')
   RETURNING id_alquiler INTO vn_alquiler;
   vn_extra := fn_calcular_cargo_retraso(vn_reserva,vd_devolucion);
   IF vn_extra > 0 THEN
    INSERT INTO cargo_adicional(id_alquiler,concepto,descripcion,monto,fecha_registro)
    VALUES(vn_alquiler,'RETRASO','Devolución después de la fecha pactada',vn_extra,vd_devolucion);
   END IF;
   INSERT INTO pago(id_alquiler,monto,tipo,estado,fecha_pago)
   VALUES(vn_alquiler,fn_calcular_costo(vn_reserva)+vn_extra,'SIMULADO','APROBADO',vd_devolucion);
   INSERT INTO evento_outbox(coleccion,documento)
   SELECT 'inspecciones_vehiculo',jsonb_build_object(
     'alquilerId',vn_alquiler,'vehiculoId',r_vehiculo.id_vehiculo,'categoriaId',r_vehiculo.id_categoria,'tipo',t.tipo,
     'fecha',CASE WHEN t.tipo='ENTREGA' THEN vd_entrega ELSE vd_devolucion END,'actor',vn_actor,
     'kilometraje',CASE WHEN t.tipo='ENTREGA' THEN vn_km ELSE vn_km_fin END,
     'combustible',CASE WHEN t.tipo='ENTREGA' THEN 100 ELSE vn_combustible END,
     'danos',CASE WHEN t.tipo='DEVOLUCION' AND vb_dano THEN jsonb_build_array(jsonb_build_object(
        'zona',vv_zonas[1 + (vn_k+vn_v) % 6],'severidad',vv_sev[1 + (vn_k*vn_v) % 3],'descripcion','Daño registrado en la devolución'))
       ELSE '[]'::jsonb END,
     'evidencias','[]'::jsonb,'observaciones','Datos ficticios de presentación','anulada',false,'version',0)
   FROM (VALUES('ENTREGA'),('DEVOLUCION')) t(tipo);
   vn_km := vn_km_fin;
   vn_gap := 1 + (vn_k*5 + vn_v) % 4 + CASE WHEN vb_tarde THEN 1 ELSE 0 END;
   vd_inicio := vd_fin + vn_gap;
  END LOOP;
 END LOOP;

 -- Alquileres en curso: entregados ayer, devolución pasado mañana.
 FOR r_vehiculo IN SELECT * FROM vehiculo WHERE placa IN ('SIR104','SIR204','SIR304','SIR404') AND estado_operativo='DISPONIBLE' LOOP
  SELECT * INTO r_tarifa FROM tarifa WHERE id_categoria=r_vehiculo.id_categoria AND vigente_desde<=vd_hoy-1
   AND (vigente_hasta IS NULL OR vigente_hasta>=vd_hoy+2) ORDER BY vigente_desde DESC LIMIT 1;
  vd_entrega := ((vd_hoy-1) + time '09:00') AT TIME ZONE 'America/Bogota';
  INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,fecha_solicitud,estado)
  VALUES(vn_clientes[1 + r_vehiculo.id_vehiculo % 20],r_vehiculo.id_vehiculo,r_tarifa.id_tarifa,vd_hoy-1,vd_hoy+2,vd_entrega - interval '2 days','ACTIVA')
  RETURNING id_reserva INTO vn_reserva;
  INSERT INTO alquiler(id_reserva,fecha_entrega,km_salida,combustible_salida,estado)
  VALUES(vn_reserva,vd_entrega,r_vehiculo.kilometraje_actual,100,'ACTIVA') RETURNING id_alquiler INTO vn_alquiler;
  INSERT INTO evento_outbox(coleccion,documento) VALUES('inspecciones_vehiculo',jsonb_build_object(
   'alquilerId',vn_alquiler,'vehiculoId',r_vehiculo.id_vehiculo,'categoriaId',r_vehiculo.id_categoria,'tipo','ENTREGA',
   'fecha',vd_entrega,'actor',vn_actor,'kilometraje',r_vehiculo.kilometraje_actual,'combustible',100,
   'danos','[]'::jsonb,'evidencias','[]'::jsonb,'observaciones','Datos ficticios de presentación','anulada',false,'version',0));
 END LOOP;

 -- Reservas futuras: confirmadas y por confirmar.
 FOR r_vehiculo IN SELECT * FROM vehiculo WHERE placa IN ('SIR105','SIR205','SIR305','SIR405','SIR502','SIR505') AND estado_operativo<>'INACTIVO' LOOP
  SELECT * INTO r_tarifa FROM tarifa WHERE id_categoria=r_vehiculo.id_categoria AND vigente_desde<=vd_hoy+3
   AND (vigente_hasta IS NULL OR vigente_hasta>=vd_hoy+9) ORDER BY vigente_desde DESC LIMIT 1;
  vn_k := r_vehiculo.id_vehiculo % 3;
  INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado)
  VALUES(vn_clientes[1 + (r_vehiculo.id_vehiculo*3) % 20],r_vehiculo.id_vehiculo,r_tarifa.id_tarifa,vd_hoy+3+vn_k,vd_hoy+6+vn_k,
         CASE WHEN r_vehiculo.placa IN ('SIR405','SIR502') THEN 'SOLICITADA' ELSE 'CONFIRMADA' END);
 END LOOP;

 -- Mantenimientos: uno completado y uno programado sin reservas en ese periodo.
 INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado)
 SELECT id_vehiculo,vd_hoy-11,vd_hoy-9,'Cambio de aceite y revisión de frenos','COMPLETADO' FROM vehiculo WHERE placa='SIR503';
 INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado)
 SELECT id_vehiculo,vd_hoy+10,vd_hoy+12,'Revisión de los 30 000 km','PROGRAMADO' FROM vehiculo WHERE placa='SIR504';
END $$;
