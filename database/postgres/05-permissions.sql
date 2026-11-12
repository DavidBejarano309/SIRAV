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
