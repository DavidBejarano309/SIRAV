-- =====================================================================
-- SIRAV - Sistema Integral de Reservas y Alquiler de Vehículos
-- Script 07_seguridad.sql  (SIRAV-32)
-- Motor: PostgreSQL 16 | Ejecutar como superusuario, después de 01 a 06
-- Autores: David Bejarano, Jose David Rodriguez
--
-- Roles (propuesta, "Privilegios en PostgreSQL"):
--   sirav_admin     dueño de todos los objetos del esquema; administración
--   sirav_app       aplicación Spring Boot: ejecuta sp_ y fn_, consulta
--                   tablas y vistas; SIN INSERT/UPDATE/DELETE directo sobre
--                   reservas, alquileres, pagos, cargos ni auditoría
--   sirav_reportes  solo lectura para reportes (sin ver password_hash)
--
-- Usuarios con login (heredan del rol de grupo):
--   sirav_admin_user, sirav_app_user, sirav_reportes_user
--
-- Los procedimientos sp_ son SECURITY DEFINER: corren con los permisos de
-- sirav_admin (que no es superusuario) y con search_path fijo, de modo que
-- la aplicación puede crear y cerrar reservas sin tener permiso directo
-- sobre las tablas. El "principio de mínimo privilegio" queda así:
-- la app solo puede cambiar reservas por los caminos que validan las reglas.
--
-- Contraseñas: se pasan con -v al ejecutar. Los valores por defecto son
-- solo para el entorno local y deben cambiarse en la VM:
--   psql -d sirav -v pwd_admin='...' -v pwd_app='...' -v pwd_reportes='...' -f 07_seguridad.sql
-- Script reejecutable: crea los roles solo si no existen.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET search_path TO sirav, public;

\if :{?pwd_admin}
\else
  \set pwd_admin 'Sirav_Admin_2026*'
\endif
\if :{?pwd_app}
\else
  \set pwd_app 'Sirav_App_2026*'
\endif
\if :{?pwd_reportes}
\else
  \set pwd_reportes 'Sirav_Reportes_2026*'
\endif

-- ---------------------------------------------------------------------
-- 1. Roles de grupo y usuarios con login (idempotente)
-- ---------------------------------------------------------------------
SELECT format('CREATE ROLE %I NOLOGIN', r)
  FROM unnest(ARRAY['sirav_admin', 'sirav_app', 'sirav_reportes']) AS r
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r)
\gexec

SELECT format('CREATE ROLE %I LOGIN', r)
  FROM unnest(ARRAY['sirav_admin_user', 'sirav_app_user', 'sirav_reportes_user']) AS r
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r)
\gexec

ALTER ROLE sirav_admin_user    PASSWORD :'pwd_admin'    NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE sirav_app_user      PASSWORD :'pwd_app'      NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 20;
ALTER ROLE sirav_reportes_user PASSWORD :'pwd_reportes' NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 5;

GRANT sirav_admin    TO sirav_admin_user;
GRANT sirav_app      TO sirav_app_user;
GRANT sirav_reportes TO sirav_reportes_user;

-- Cada usuario trabaja en el esquema sirav sin escribir el prefijo
ALTER ROLE sirav_admin_user    SET search_path = sirav, public;
ALTER ROLE sirav_app_user      SET search_path = sirav, public;
ALTER ROLE sirav_reportes_user SET search_path = sirav, public;

-- ---------------------------------------------------------------------
-- 2. sirav_admin pasa a ser dueño del esquema y de todos sus objetos
-- ---------------------------------------------------------------------
ALTER SCHEMA sirav OWNER TO sirav_admin;

SELECT format('ALTER TABLE sirav.%I OWNER TO sirav_admin', c.relname)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'sirav' AND c.relkind IN ('r', 'p')
\gexec

SELECT format('ALTER VIEW sirav.%I OWNER TO sirav_admin', c.relname)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'sirav' AND c.relkind IN ('v', 'm')
\gexec

SELECT format('ALTER %s sirav.%I(%s) OWNER TO sirav_admin',
              CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
              p.proname, pg_get_function_identity_arguments(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sirav'
\gexec

-- ---------------------------------------------------------------------
-- 3. Procedimientos sp_ como SECURITY DEFINER con search_path fijo
--    (evita que un usuario cambie el search_path para suplantar tablas)
-- ---------------------------------------------------------------------
SELECT format('ALTER PROCEDURE sirav.%I(%s) SECURITY DEFINER SET search_path = sirav, public, pg_temp',
              p.proname, pg_get_function_identity_arguments(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sirav' AND p.prokind = 'p' AND p.proname LIKE 'sp\_%'
\gexec

-- ---------------------------------------------------------------------
-- 4. Quitar permisos por defecto a PUBLIC
-- ---------------------------------------------------------------------
REVOKE ALL ON SCHEMA sirav FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA sirav FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA sirav FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA sirav FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA sirav FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO sirav_admin, sirav_app, sirav_reportes', current_database()) \gexec

-- ---------------------------------------------------------------------
-- 5. sirav_app (aplicación)
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA sirav TO sirav_app;

-- Lectura de todo (catálogo, historial, login con password_hash, vistas)
GRANT SELECT ON ALL TABLES IN SCHEMA sirav TO sirav_app;

-- Escritura solo en datos maestros que la aplicación administra
GRANT INSERT, UPDATE ON usuario, usuario_rol, cliente, mantenimiento TO sirav_app;
GRANT UPDATE (estado_operativo, kilometraje_actual, color) ON vehiculo TO sirav_app;
GRANT USAGE ON SEQUENCE usuario_id_usuario_seq, cliente_id_cliente_seq,
                        mantenimiento_id_mantenimiento_seq TO sirav_app;

-- Reservas, alquileres, pagos, cargos y auditoría: solo a través de sp_
GRANT EXECUTE ON PROCEDURE
  sp_crear_reserva(BIGINT, BIGINT, DATE, DATE, BIGINT, BIGINT),
  sp_confirmar_reserva(BIGINT, BIGINT),
  sp_cancelar_reserva(BIGINT, BIGINT, TEXT),
  sp_iniciar_alquiler(BIGINT, INTEGER, NUMERIC, BIGINT, BIGINT),
  sp_cerrar_alquiler(BIGINT, INTEGER, NUMERIC, VARCHAR, BIGINT, NUMERIC, VARCHAR, TIMESTAMPTZ, NUMERIC)
TO sirav_app;

GRANT EXECUTE ON FUNCTION
  fn_vehiculo_disponible(BIGINT, DATE, DATE, BIGINT),
  fn_calcular_costo(BIGINT, DATE, DATE),
  fn_calcular_cargo_retraso(BIGINT, TIMESTAMPTZ),
  fn_obtener_tarifa_vigente(BIGINT, DATE),
  fn_estado_vehiculo_calculado(BIGINT)
TO sirav_app;

-- ---------------------------------------------------------------------
-- 6. sirav_reportes (solo lectura, sin credenciales)
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA sirav TO sirav_reportes;
GRANT SELECT ON ALL TABLES IN SCHEMA sirav TO sirav_reportes;
REVOKE SELECT ON usuario FROM sirav_reportes;
GRANT SELECT (id_usuario, nombre, apellido, email, activo, creado_en) ON usuario TO sirav_reportes;

GRANT EXECUTE ON FUNCTION
  fn_vehiculo_disponible(BIGINT, DATE, DATE, BIGINT),
  fn_calcular_costo(BIGINT, DATE, DATE),
  fn_calcular_cargo_retraso(BIGINT, TIMESTAMPTZ),
  fn_obtener_tarifa_vigente(BIGINT, DATE),
  fn_estado_vehiculo_calculado(BIGINT)
TO sirav_reportes;

-- ---------------------------------------------------------------------
-- 7. Objetos futuros (por ejemplo, vistas nuevas de reportes)
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE sirav_admin IN SCHEMA sirav
  GRANT SELECT ON TABLES TO sirav_app, sirav_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE sirav_admin IN SCHEMA sirav
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Resumen de privilegios por tabla
-- ---------------------------------------------------------------------
SELECT table_name AS tabla,
       string_agg(DISTINCT CASE WHEN grantee = 'sirav_app'      THEN privilege_type END, ',') AS sirav_app,
       string_agg(DISTINCT CASE WHEN grantee = 'sirav_reportes' THEN privilege_type END, ',') AS sirav_reportes
  FROM information_schema.role_table_grants
 WHERE table_schema = 'sirav' AND grantee IN ('sirav_app', 'sirav_reportes')
 GROUP BY table_name
 ORDER BY table_name;
