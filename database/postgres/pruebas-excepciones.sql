-- SIRAV · Prueba de las excepciones con nombre (SR001 a SR008).
-- Ejecutar como sirav_owner sobre una base recién creada con 01 a 07:
--   psql -v ON_ERROR_STOP=1 -d sirav_3fn -f database/postgres/pruebas-excepciones.sql
-- Todo ocurre en una transacción que se revierte al final: no deja datos.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.espera(param_sql TEXT, param_codigo TEXT, param_nombre TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE vv_estado TEXT; vv_pista TEXT; vv_mensaje TEXT;
BEGIN
 EXECUTE param_sql;
 RAISE EXCEPTION 'FALLA: se esperaba % (%) y la operación fue aceptada: %', param_codigo, param_nombre, param_sql;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS vv_estado = RETURNED_SQLSTATE, vv_pista = PG_EXCEPTION_HINT, vv_mensaje = MESSAGE_TEXT;
 IF vv_mensaje LIKE 'FALLA:%' THEN RAISE; END IF;
 IF vv_estado <> param_codigo OR vv_pista <> param_nombre THEN
  RAISE EXCEPTION 'FALLA: se esperaba % % y llegó % % (%)', param_codigo, param_nombre, vv_estado, vv_pista, vv_mensaje;
 END IF;
 RETURN format('[OK] %s %s: %s', vv_estado, vv_pista, vv_mensaje);
END $$;

-- Datos de prueba: un operador, un cliente de mostrador y un vehículo con tarifa vigente.
INSERT INTO usuario(nombre,apellido,email,password_hash) VALUES ('Prueba','SR','prueba.sr@sirav.local','x');
INSERT INTO cliente(nombres,apellidos,documento,telefono,licencia_conduccion) VALUES ('Cliente','SR','SR-TEST','3000000000','LIC-SR');
CREATE TEMP TABLE ctx AS SELECT
 (SELECT id_usuario FROM usuario WHERE email='prueba.sr@sirav.local') AS actor,
 (SELECT id_cliente FROM cliente WHERE documento='SR-TEST') AS cliente,
 (SELECT min(id_vehiculo) FROM vehiculo WHERE estado_operativo='DISPONIBLE') AS vehiculo,
 (now() AT TIME ZONE 'America/Bogota')::date AS hoy;
SELECT set_config('t.actor',actor::text,false), set_config('t.cli',cliente::text,false),
       set_config('t.veh',vehiculo::text,false), set_config('t.hoy',hoy::text,false) FROM ctx;

CALL sp_crear_reserva(current_setting('t.actor')::bigint, current_setting('t.cli')::bigint, current_setting('t.veh')::bigint,
  current_setting('t.hoy')::date+40, current_setting('t.hoy')::date+43, gen_random_uuid());
SELECT set_config('t.res',(SELECT max(id_reserva) FROM reserva)::text,false);

\pset tuples_only on
\echo '== Excepciones con nombre de SIRAV'
SELECT pg_temp.espera(format('CALL sp_crear_reserva(%s,%s,%s,%L,%L,gen_random_uuid())', current_setting('t.actor'), current_setting('t.cli'), current_setting('t.veh'),
  current_setting('t.hoy')::date+41, current_setting('t.hoy')::date+42), 'SR001', 'e_reserva_solapada');
SELECT pg_temp.espera(format($q$INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado) VALUES (%s,%L,%L,'Prueba SR002','PROGRAMADO')$q$,
  current_setting('t.veh'), current_setting('t.hoy')::date+41, current_setting('t.hoy')::date+42), 'SR002', 'e_mantenimiento_solapado');
SELECT pg_temp.espera(format('CALL sp_iniciar_alquiler(%s,%s,100,50,%L::jsonb)', current_setting('t.actor'), current_setting('t.res'), '{"danos":[],"evidencias":[]}'),
  'SR003', 'e_transicion_invalida');
CALL sp_confirmar_reserva(current_setting('t.actor')::bigint, current_setting('t.res')::bigint);
-- Reserva de hoy en otro vehículo, para llegar a la validación de la inspección.
SELECT set_config('t.veh2',(SELECT min(id_vehiculo) FROM vehiculo WHERE estado_operativo='DISPONIBLE' AND id_vehiculo>current_setting('t.veh')::bigint)::text,false);
CALL sp_crear_reserva(current_setting('t.actor')::bigint, current_setting('t.cli')::bigint, current_setting('t.veh2')::bigint,
  current_setting('t.hoy')::date, current_setting('t.hoy')::date+2, gen_random_uuid());
SELECT set_config('t.hoyres',(SELECT max(id_reserva) FROM reserva)::text,false);
CALL sp_confirmar_reserva(current_setting('t.actor')::bigint, current_setting('t.hoyres')::bigint);
SELECT pg_temp.espera(format('CALL sp_iniciar_alquiler(%s,%s,999999,50,NULL)', current_setting('t.actor'), current_setting('t.hoyres')), 'SR004', 'e_inspeccion_requerida');
UPDATE vehiculo SET estado_operativo='INACTIVO' WHERE id_vehiculo=(SELECT max(id_vehiculo) FROM vehiculo);
-- sp_crear_reserva ya lo rechaza como no disponible (SR001); el trigger es la segunda defensa.
SELECT pg_temp.espera(format($q$INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado) SELECT %s, v.id_vehiculo, t.id_tarifa, %L, %L, 'SOLICITADA'
  FROM vehiculo v JOIN tarifa t USING(id_categoria) WHERE v.id_vehiculo=(SELECT max(id_vehiculo) FROM vehiculo) LIMIT 1$q$,
  current_setting('t.cli'), current_setting('t.hoy')::date+50, current_setting('t.hoy')::date+51), 'SR005', 'e_vehiculo_no_disponible');
UPDATE tarifa SET vigente_hasta=current_setting('t.hoy')::date+60 WHERE id_categoria=(SELECT id_categoria FROM vehiculo WHERE id_vehiculo=current_setting('t.veh')::bigint);
SELECT pg_temp.espera(format('CALL sp_crear_reserva(%s,%s,%s,%L,%L,gen_random_uuid())', current_setting('t.actor'), current_setting('t.cli'), current_setting('t.veh'),
  current_setting('t.hoy')::date+58, current_setting('t.hoy')::date+62), 'SR006', 'e_tarifa_no_vigente');
SELECT pg_temp.espera(format('CALL sp_cancelar_reserva(%s,%s,%L)', current_setting('t.actor'), current_setting('t.res'), 'no'), 'SR007', 'e_parametro_invalido');
SELECT pg_temp.espera(format('UPDATE tarifa SET valor_diario=valor_diario+1 WHERE id_tarifa=(SELECT id_tarifa FROM reserva WHERE id_reserva=%s)', current_setting('t.res')),
  'SR008', 'e_tarifa_historica');
\echo '== Todas las excepciones devolvieron su código y su nombre'
ROLLBACK;
