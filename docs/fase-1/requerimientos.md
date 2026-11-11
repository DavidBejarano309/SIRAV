# Requerimientos priorizados — SIRAV

Lista oficial de la propuesta (Tabla 10). La prioridad es **Alta** (indispensable), **Media** (importante) o **Baja** (deseable). La trazabilidad indica dónde se implementa cada requerimiento en el repositorio:

- Base de datos: `database/postgres/` y `database/mongo/`.
- Backend: `backend/src/main/java/co/edu/sirav/`.
- Frontend: `frontend/src/views/`.
- Pruebas: `backend/src/test/java/co/edu/sirav/IntegrationTest.java`, salvo que se indique otra ruta.

## Requerimientos funcionales

| ID | Requerimiento | Prioridad | Base de datos | Aplicación | Prueba | Historias | Estado |
|---|---|---|---|---|---|---|---|
| RF-01 | Autenticación y perfiles (administrador, operador, cliente). | Alta | `usuario`, `rol`, `usuario_rol`; `usuario.token_version`; vista `v_cliente_contacto` | `POST /api/auth/register`, `/login`, `/logout`, `GET /me`; BCrypt(12) y JWT; `Auth.jsx` | `authEnforcesRolesAndRevokesSessions`, `AccessTest` | SIRAV-16, SIRAV-27 | Cumplido |
| RF-02 | Consultar el catálogo por categoría y fechas libres. | Alta | `fn_vehiculo_disponible`; exclusión GiST `ex_reserva_vehiculo_periodo`; reporte R6 (`availability.sql`) | `GET /api/vehicles`, `/vehicles/{id}/quote`; `Catalog.jsx` | `allSixSqlReportsExecuteAgainstRealDatabase` | SIRAV-19, SIRAV-22, SIRAV-28 | Cumplido |
| RF-03 | Crear y cancelar reservas sin solapamientos. | Alta | `sp_crear_reserva` (idempotente), `sp_cancelar_reserva`; `ex_reserva_vehiculo_periodo` (RN-01); `trg_validar_reserva` y `trg_validar_mantenimiento` (RN-02) | `POST /api/reservations`, `/reservations/{id}/cancel`; `Operations.jsx` | `concurrentReservationsHaveExactlyOneWinner` | SIRAV-18, SIRAV-20, SIRAV-29 | Cumplido |
| RF-04 | Confirmar reservas e iniciar alquileres. | Alta | `sp_confirmar_reserva`, `sp_iniciar_alquiler`; `trg_validar_reserva` (RN-03); `trg_actualizar_estado_vehiculo` | `POST /reservations/{id}/confirm`, `/reservations/{id}/start` | `lifecyclePersistsInspectionAndSimulatedPayment` | SIRAV-20, SIRAV-21, SIRAV-24, SIRAV-30 | Cumplido |
| RF-05 | Registrar devolución, cargos y pago de prueba. | Alta | `sp_cerrar_alquiler`; `fn_calcular_costo`, `fn_calcular_cargo_retraso` (RN-04); `cargo_adicional`, `pago` (tipo SIMULADO) | `POST /rentals/{id}/close`, `GET /rentals/{id}/payments` | `lifecyclePersistsInspectionAndSimulatedPayment` | SIRAV-19, SIRAV-24, SIRAV-30 | Cumplido |
| RF-06 | Registrar inspecciones de entrega y devolución. | Alta | `sp_iniciar_alquiler` y `sp_cerrar_alquiler` exigen la inspección (SR004) y la escriben en `evento_outbox`; colección `inspecciones_vehiculo` con validador e índice único `{alquilerId, tipo}` (RN-05) | `OutboxPublisher`; `GET /rentals/{id}/inspections`, `PUT` y `DELETE /inspections/{id}`; `InspectionFields.jsx`, `Inspections.jsx` | `mongodbCrudVersioningComplexSearchAndAggregations` | SIRAV-23, SIRAV-25, SIRAV-30 | Cumplido |
| RF-07 | Consultar historial y reportes. | Media | `auditoria_reserva` con `trg_auditar_reserva`; reportes R1 a R6 en `backend/src/main/resources/sql/reports/`; 3 agregaciones en MongoDB | `GET /reservations/{id}/history`, `/api/reports/{tipo}`, `/inspections/analytics`; `Reports.jsx` | `allSixSqlReportsExecuteAgainstRealDatabase`, `mongodbCrud…Aggregations` | SIRAV-21, SIRAV-22, SIRAV-26, SIRAV-31 | Cumplido |
| RF-08 | Registrar mantenimientos de vehículos. | Media | `mantenimiento`; exclusión `ex_mantenimiento`; `trg_validar_mantenimiento` (RN-02) | `GET`, `POST` y `PATCH /api/maintenance`; `Management.jsx` | Prueba de humo de la base (SR002) | SIRAV-21, SIRAV-31 | Cumplido |

## Requerimientos no funcionales

| ID | Requerimiento | Prioridad | Cómo se cumple | Evidencia | Historias | Estado |
|---|---|---|---|---|---|---|
| RNF-01 | Sin dobles asignaciones, aun con accesos simultáneos. | Alta | Exclusión GiST sobre `daterange(fecha_inicio, fecha_fin, '[)')`. `sp_crear_reserva` bloquea el vehículo con `FOR UPDATE` y usa un candado consultivo por clave de idempotencia. | `concurrentReservationsHaveExactlyOneWinner`: dos hilos reservan el mismo vehículo y solo uno gana. | SIRAV-18, SIRAV-20, SIRAV-33 | Cumplido |
| RNF-02 | Seguridad: contraseñas con hash y privilegios mínimos. | Alta | BCrypt(12) y JWT de 30 min, revocable con `token_version`. Usuario `sirav_app` sin escritura directa sobre reserva, alquiler, pago ni auditoría, y procedimientos `SECURITY DEFINER`. Perfiles `sirav_reportes` y `sirav_admin` (`05-permissions.sql`). | `applicationRoleCannotWriteReservationsDirectly`; prueba de permisos con `SET ROLE` | SIRAV-32, SIRAV-27 | Cumplido |
| RNF-03 | Despliegue reproducible y documentado en VM Linux. | Alta | `compose.yaml` con cuatro servicios y los scripts `scripts/configure.sh` y `scripts/backup.sh`. Guía en `docs/fase-2/guia-instalacion.md`. | CI de GitHub Actions levanta PostgreSQL y MongoDB con Compose y ejecuta las pruebas | SIRAV-15, SIRAV-35 | Guía lista; falta instalar la VM |
| RNF-04 | Consultas frecuentes en menos de 2 segundos con los datos de prueba. | Media | Índices `ix_reserva_cliente`, `ix_vehiculo_categoria`, `ix_pago_alquiler`, `ix_cargo_alquiler`, `ix_auditoria_reserva` e `ix_outbox_pendiente`. Índices GiST de las tres exclusiones e índices de MongoDB. | Los seis reportes se ejecutan sin error sobre los datos de prueba | SIRAV-16, SIRAV-34 | Cumplido con los datos de prueba; falta medir con más volumen |

## Reglas de negocio

| Regla | Dónde se cumple | Excepción |
|---|---|---|
| RN-01 Sin reservas solapadas | `ex_reserva_vehiculo_periodo`, `fn_vehiculo_disponible`, `sp_crear_reserva` | SR001 `e_reserva_solapada` |
| RN-02 Sin reservas durante mantenimientos | `trg_validar_reserva`, `trg_validar_mantenimiento`, `ex_mantenimiento` | SR002 `e_mantenimiento_solapado` |
| RN-03 Orden de estados de la reserva | `trg_validar_reserva` y validaciones en los `sp_` | SR003 `e_transicion_invalida` |
| RN-04 Costo por tarifa y retraso al 50 % | `fn_calcular_costo`, `fn_calcular_cargo_retraso`, `sp_cerrar_alquiler` | SR006 `e_tarifa_no_vigente` |
| RN-05 Entrega y cierre solo con inspección | `sp_iniciar_alquiler`, `sp_cerrar_alquiler`, `ck_devolucion`; índice único en MongoDB | SR004 `e_inspeccion_requerida` |

El catálogo completo de excepciones (SR001–SR007) está en `docs/fase-1/supuestos.md`.
