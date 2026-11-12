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
