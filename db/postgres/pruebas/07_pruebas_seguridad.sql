-- =====================================================================
-- SIRAV - 07_pruebas_seguridad.sql  (evidencia SIRAV-32)
-- Ejecutar como superusuario después de 01 a 07. Cambia de rol con
-- SET ROLE para comprobar qué puede y qué no puede hacer cada perfil.
-- Todo se revierte al final. Cada NOTICE debe empezar por OK.
-- 42501 = insufficient_privilege
-- =====================================================================
SET client_min_messages = notice;
SET search_path TO sirav, public;

BEGIN;

CREATE FUNCTION pg_temp.fn_verificar(param_caso TEXT, param_esperado TEXT, param_obtenido TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  RAISE NOTICE '% | %  (esperado: %, obtenido: %)',
    CASE WHEN param_esperado IS NOT DISTINCT FROM param_obtenido THEN 'OK   ' ELSE 'FALLO' END,
    param_caso, param_esperado, param_obtenido;
END; $$;

-- Ejecuta una sentencia con el rol indicado y devuelve el SQLSTATE
CREATE FUNCTION pg_temp.fn_como(param_rol TEXT, param_sql TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  vv_resultado TEXT := 'SIN_ERROR';
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', param_rol);
    EXECUTE param_sql;
  EXCEPTION WHEN OTHERS THEN
    vv_resultado := SQLSTATE;
  END;
  RESET ROLE;
  RETURN vv_resultado;
END; $$;

GRANT EXECUTE ON FUNCTION pg_temp.fn_verificar(TEXT, TEXT, TEXT) TO PUBLIC;

DO $$
DECLARE
  vd_hoy DATE := (now() AT TIME ZONE 'America/Bogota')::date;
BEGIN
  -- -------------------------------------------------------------------
  -- Aplicación: sirav_app_user
  -- -------------------------------------------------------------------
  PERFORM pg_temp.fn_verificar('S1 App consulta el catálogo de vehículos', 'SIN_ERROR',
    pg_temp.fn_como('sirav_app_user', 'SELECT count(*) FROM sirav.vehiculo'));
  PERFORM pg_temp.fn_verificar('S2 App lee usuario y password_hash (login BCrypt)', 'SIN_ERROR',
    pg_temp.fn_como('sirav_app_user', 'SELECT password_hash FROM sirav.usuario WHERE email = ''admin@sirav.test'''));
  PERFORM pg_temp.fn_verificar('S3 App usa fn_vehiculo_disponible', 'SIN_ERROR',
    pg_temp.fn_como('sirav_app_user', format('SELECT sirav.fn_vehiculo_disponible(4, %L, %L)', vd_hoy + 100, vd_hoy + 101)));
  PERFORM pg_temp.fn_verificar('S4 App crea reserva con sp_crear_reserva (SECURITY DEFINER)', 'SIN_ERROR',
    pg_temp.fn_como('sirav_app_user', format('CALL sirav.sp_crear_reserva(1, 4, %L, %L, 2)', vd_hoy + 100, vd_hoy + 101)));
  PERFORM pg_temp.fn_verificar('S5 App NO puede borrar reservas', '42501',
    pg_temp.fn_como('sirav_app_user', 'DELETE FROM sirav.reserva WHERE id_reserva = 12'));
  PERFORM pg_temp.fn_verificar('S6 App NO puede cambiar el estado de una reserva directamente', '42501',
    pg_temp.fn_como('sirav_app_user', 'UPDATE sirav.reserva SET estado = ''CONFIRMADA'' WHERE id_reserva = 12'));
  PERFORM pg_temp.fn_verificar('S7 App NO puede insertar reservas directamente', '42501',
    pg_temp.fn_como('sirav_app_user', format(
      'INSERT INTO sirav.reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin) VALUES (1, 9, 7, %L, %L)', vd_hoy + 110, vd_hoy + 111)));
  PERFORM pg_temp.fn_verificar('S8 App NO puede registrar pagos directamente', '42501',
    pg_temp.fn_como('sirav_app_user', 'INSERT INTO sirav.pago (id_alquiler, monto, tipo) VALUES (1, 1000, ''EFECTIVO'')'));
  PERFORM pg_temp.fn_verificar('S9 App NO puede alterar la auditoría', '42501',
    pg_temp.fn_como('sirav_app_user', 'DELETE FROM sirav.auditoria_reserva'));
  PERFORM pg_temp.fn_verificar('S10 App registra un cliente nuevo', 'SIN_ERROR',
    pg_temp.fn_como('sirav_app_user', 'INSERT INTO sirav.cliente (nombres, apellidos, documento) VALUES (''Prueba'', ''Seguridad'', ''999000111'')'));
  PERFORM pg_temp.fn_verificar('S11 App registra un mantenimiento', 'SIN_ERROR',
    pg_temp.fn_como('sirav_app_user', format(
      'INSERT INTO sirav.mantenimiento (id_vehiculo, fecha_inicio, fecha_fin, descripcion) VALUES (25, %L, %L, ''Revisión'')', vd_hoy + 120, vd_hoy + 121)));
  PERFORM pg_temp.fn_verificar('S12 App NO puede cambiar la tarifa', '42501',
    pg_temp.fn_como('sirav_app_user', 'UPDATE sirav.tarifa SET valor_diario = 1 WHERE id_tarifa = 6'));
  PERFORM pg_temp.fn_verificar('S13 App NO puede llamar el procedimiento interno de contexto', '42501',
    pg_temp.fn_como('sirav_app_user', 'CALL sirav.sp_registrar_contexto(1, ''x'')'));
  PERFORM pg_temp.fn_verificar('S14 App NO puede crear tablas en el esquema', '42501',
    pg_temp.fn_como('sirav_app_user', 'CREATE TABLE sirav.intrusa (x int)'));

  -- -------------------------------------------------------------------
  -- Reportes: sirav_reportes_user
  -- -------------------------------------------------------------------
  PERFORM pg_temp.fn_verificar('R1 Reportes consulta alquileres y pagos', 'SIN_ERROR',
    pg_temp.fn_como('sirav_reportes_user', 'SELECT sum(monto) FROM sirav.pago JOIN sirav.alquiler USING (id_alquiler)'));
  PERFORM pg_temp.fn_verificar('R2 Reportes ve nombre y email de usuarios', 'SIN_ERROR',
    pg_temp.fn_como('sirav_reportes_user', 'SELECT nombre, email FROM sirav.usuario'));
  PERFORM pg_temp.fn_verificar('R3 Reportes NO ve password_hash', '42501',
    pg_temp.fn_como('sirav_reportes_user', 'SELECT password_hash FROM sirav.usuario'));
  PERFORM pg_temp.fn_verificar('R4 Reportes NO puede crear reservas', '42501',
    pg_temp.fn_como('sirav_reportes_user', format('CALL sirav.sp_crear_reserva(1, 9, %L, %L, 2)', vd_hoy + 130, vd_hoy + 131)));
  PERFORM pg_temp.fn_verificar('R5 Reportes NO puede modificar vehículos', '42501',
    pg_temp.fn_como('sirav_reportes_user', 'UPDATE sirav.vehiculo SET color = ''Verde'' WHERE id_vehiculo = 1'));

  -- -------------------------------------------------------------------
  -- Administrador: sirav_admin_user
  -- -------------------------------------------------------------------
  PERFORM pg_temp.fn_verificar('D1 Admin puede actualizar tarifas', 'SIN_ERROR',
    pg_temp.fn_como('sirav_admin_user', 'UPDATE sirav.tarifa SET valor_diario = 115000 WHERE id_tarifa = 6'));
  PERFORM pg_temp.fn_verificar('D2 Admin sigue sujeto a las reglas (RN-03 en trigger)', 'SR003',
    pg_temp.fn_como('sirav_admin_user', 'UPDATE sirav.reserva SET estado = ''CANCELADA'' WHERE id_reserva = 1'));
  PERFORM pg_temp.fn_verificar('D3 Admin no es superusuario', 'false',
    (SELECT rolsuper::text FROM pg_roles WHERE rolname = 'sirav_admin_user'));

  -- -------------------------------------------------------------------
  -- Configuración
  -- -------------------------------------------------------------------
  PERFORM pg_temp.fn_verificar('C1 Los 6 sp_ (5 públicos + contexto) son SECURITY DEFINER con search_path fijo', '6',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'sirav' AND p.proname LIKE 'sp\_%' AND p.prosecdef
        AND p.proconfig::text LIKE '%search_path=sirav, public, pg_temp%'));
  PERFORM pg_temp.fn_verificar('C2 Todos los objetos del esquema pertenecen a sirav_admin', '0',
    (SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'sirav' AND c.relkind IN ('r','v','m','S') AND pg_get_userbyid(c.relowner) <> 'sirav_admin'));
END $$;

ROLLBACK;
