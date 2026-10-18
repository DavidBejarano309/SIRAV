# Base de datos

Los scripts de PostgreSQL se ejecutan en orden numérico:

| Script | Contenido |
|---|---|
| `postgres/01_creacion.sql` | Esquema: tablas, llaves, restricciones, índices y restricción de exclusión (RN-01) |
| `postgres/02_insercion.sql` | Datos de prueba |
| `postgres/03_funciones.sql` | `fn_vehiculo_disponible`, `fn_calcular_costo`, `fn_calcular_cargo_retraso` |
| `postgres/04_procedimientos.sql` | `sp_crear_reserva`, `sp_confirmar_reserva`, `sp_cancelar_reserva`, `sp_iniciar_alquiler`, `sp_cerrar_alquiler` |
| `postgres/05_triggers.sql` | Transición de estado, mantenimiento, auditoría y estado del vehículo |
| `postgres/06_reportes.sql` | Reportes R1 a R6 |
| `postgres/07_seguridad.sql` | Roles y privilegios |

MongoDB: ver `mongo/README.md`.
