# Requerimientos priorizados — SIRAV

Lista oficial de la propuesta (Tabla 10). La prioridad se expresa como **Alta** (indispensable), **Media** (importante) o **Baja** (deseable). La trazabilidad indica el objeto que implementa cada requerimiento; los scripts están en `db/postgres/`.

## Requerimientos funcionales

| ID | Requerimiento | Prioridad | Trazabilidad | Historias | Estado |
|---|---|---|---|---|---|
| RF-01 | Autenticación y perfiles (administrador, operador, cliente). | Alta | Tablas `usuario`, `rol` y `usuario_rol`; `password_hash` con BCrypt; Spring Security | SIRAV-16, SIRAV-27 | Base de datos lista; falta la aplicación |
| RF-02 | Consultar el catálogo por categoría y fechas libres. | Alta | `fn_vehiculo_disponible`; índice `ix_reserva_vehiculo_fechas`; reporte R6 | SIRAV-19, SIRAV-22, SIRAV-28 | Función lista; faltan R6 y la pantalla |
| RF-03 | Crear y cancelar reservas sin solapamientos. | Alta | `sp_crear_reserva`, `sp_cancelar_reserva`; restricción `ex_reserva_solapada` (RN-01); `trg_validar_mantenimiento` (RN-02) | SIRAV-18, SIRAV-20, SIRAV-29 | Base de datos lista; falta la aplicación |
| RF-04 | Confirmar reservas e iniciar alquileres. | Alta | `sp_confirmar_reserva`, `sp_iniciar_alquiler`; `trg_validar_transicion_reserva` (RN-03); `trg_actualizar_estado_vehiculo` | SIRAV-20, SIRAV-21, SIRAV-24, SIRAV-30 | Base de datos lista; falta la aplicación |
| RF-05 | Registrar devolución, cargos y pago de prueba. | Alta | `sp_cerrar_alquiler`; `fn_calcular_costo`, `fn_calcular_cargo_retraso` (RN-04); tablas `cargo_adicional` y `pago` | SIRAV-19, SIRAV-24, SIRAV-30 | Base de datos lista; falta la aplicación |
| RF-06 | Registrar inspecciones de entrega y devolución. | Alta | Colección `inspecciones_vehiculo` en MongoDB; `sp_cerrar_alquiler` exige el id de la inspección (RN-05) | SIRAV-23, SIRAV-25, SIRAV-30 | Pendiente |
| RF-07 | Consultar historial y reportes. | Media | Tabla `auditoria_reserva` con `trg_auditar_reserva`; reportes R1 a R6; agregaciones de MongoDB | SIRAV-21, SIRAV-22, SIRAV-26, SIRAV-31 | Auditoría lista; faltan reportes y agregaciones |
| RF-08 | Registrar mantenimientos de vehículos. | Media | Tabla `mantenimiento`; `trg_validar_mantenimiento` (RN-02); `trg_actualizar_estado_vehiculo` | SIRAV-21, SIRAV-31 | Base de datos lista; falta la aplicación |

## Requerimientos no funcionales

| ID | Requerimiento | Prioridad | Trazabilidad | Historias | Estado |
|---|---|---|---|---|---|
| RNF-01 | Sin dobles asignaciones, aun con accesos simultáneos. | Alta | Restricción `ex_reserva_solapada`; bloqueo `FOR UPDATE` en `sp_crear_reserva`; prueba `pruebas/04_concurrencia_dos_sesiones.sh` | SIRAV-18, SIRAV-20, SIRAV-33 | Implementado y probado localmente; falta repetir en la VM |
| RNF-02 | Seguridad: contraseñas con hash y privilegios mínimos. | Alta | Roles `sirav_app`, `sirav_reportes` y `sirav_admin`; procedimientos `SECURITY DEFINER` (`07_seguridad.sql`); BCrypt | SIRAV-32, SIRAV-27 | Base de datos lista; falta BCrypt en la aplicación |
| RNF-03 | Despliegue reproducible y documentado en VM Linux. | Alta | Scripts numerados `01` a `07` y `ejecutar_todo.sh`; guía de instalación en `infra/` | SIRAV-15, SIRAV-35 | Scripts listos; faltan la VM y la guía |
| RNF-04 | Consultas frecuentes en menos de 2 segundos con los datos de prueba. | Media | 13 índices `ix_` en `01_creacion.sql` | SIRAV-16, SIRAV-34 | Índices creados; falta medir con `EXPLAIN ANALYZE` |

## Reglas de negocio relacionadas

| Regla | Dónde se cumple |
|---|---|
| RN-01 Sin reservas solapadas | `ex_reserva_solapada`, `fn_vehiculo_disponible`, `sp_crear_reserva` |
| RN-02 Sin reservas durante mantenimientos | `trg_validar_mantenimiento` (en `reserva` y en `mantenimiento`) |
| RN-03 Orden de estados de la reserva | `trg_validar_transicion_reserva` |
| RN-04 Costo por tarifa y retraso al 50 % | `fn_calcular_costo`, `fn_calcular_cargo_retraso` |
| RN-05 Cierre solo con devolución e inspección | `sp_cerrar_alquiler`, restricción `ck_alquiler_cierre` |
