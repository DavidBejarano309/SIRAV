# Plan y resultados de pruebas — SIRAV

Historias de Jira: **SIRAV-18** (exclusión y concurrencia), **SIRAV-33** (reservas simultáneas) y **SIRAV-34** (punta a punta). Las pruebas usan **PostgreSQL y MongoDB reales**, nunca bases simuladas en memoria: las restricciones GiST, los triggers y las excepciones SR solo existen en el motor real.

## 1. Niveles de prueba

| Nivel | Herramienta | Dónde | Cuándo se ejecuta |
|---|---|---|---|
| Integración del backend | JUnit 5 + Spring Boot Test, contra las bases de `compose.test.yaml` | `backend/src/test/java/co/edu/sirav/` | Cada push, workflow **SIRAV CI** |
| Interfaz (componentes) | Vitest + Testing Library | `frontend/src/views/Auth.test.jsx` | Cada push, workflow **SIRAV CI** |
| Navegador (punta a punta) | Playwright | `frontend/e2e/` | Manual, con la aplicación en marcha (`npm run test:e2e`) |
| Despliegue | Docker Compose + `scripts/verificar-despliegue.sh` | `.github/workflows/despliegue.yml` | Cada push que toque código, bases, scripts o Compose |
| Base de datos | Prueba de humo SQL sobre los scripts cargados | Sección 4 | Al modificar `database/postgres/` |

## 2. Casos y requerimientos

| Prueba | Qué verifica | Requerimiento |
|---|---|---|
| `authEnforcesRolesAndRevokesSessions` | Cada perfil solo accede a lo suyo; tras el logout, el token anterior se rechaza (`token_version`) | RF-01, RNF-02 |
| `lifecyclePersistsInspectionAndSimulatedPayment` | Reserva idempotente, confirmación, entrega y devolución con inspecciones; pago SIMULADO; la devolución inválida no deja pago parcial | RF-03, RF-04, RF-05, RF-06 |
| `concurrentReservationsHaveExactlyOneWinner` | Dos hilos reservan el mismo vehículo y fechas a la vez: exactamente uno obtiene 201 y el otro 409 | **RNF-01**, RN-01 |
| `allSixSqlReportsExecuteAgainstRealDatabase` | Los seis reportes R1 a R6 se ejecutan y devuelven columnas | RF-07 |
| `applicationRoleCannotWriteReservationsDirectly` | El usuario `sirav_app` no puede hacer `INSERT` directo en `reserva` | RNF-02 |
| `registeredClientUsesUserIdentityWithoutDuplicatingIt` | El registro no copia nombre ni correo en `cliente`; la vista los toma de `usuario`; la restricción rechaza copiarlos | 3FN |
| `clientWithoutAccountKeepsItsOwnIdentity` | Un cliente de mostrador conserva su identidad en `cliente` | 3FN |
| `mongodbCrudVersioningComplexSearchAndAggregations` | Lectura, corrección con versión e historial, conflicto de versión (409), anulación lógica, consulta `$elemMatch` y tres agregaciones | RF-06, RF-07 |
| `AccessTest` (3 casos) | Un cliente no puede leer reservas ajenas; el operador sí; una reserva inexistente no concede acceso | RNF-02 |
| `Auth.test.jsx` (3 casos) | Rechazo de credenciales, sesión iniciada y campos obligatorios del registro | RF-01 |
| `e2e/lifecycle.spec.js` | Reserva, confirmación, entrega y devolución desde los formularios de la interfaz | RF-03 a RF-06 |
| `e2e/operation.spec.js` (2 casos) | El administrador navega por todos los módulos; el cliente ve solo sus reservas y la vista móvil no se desborda | RF-01, RF-07 |
| `verificar-despliegue.sh` | Flujo completo a través de nginx en el despliegue Docker, incluido el rechazo de una reserva solapada | RNF-03 |

## 3. Concurrencia (RNF-01)

La regla "un vehículo no puede tener dos reservas vigentes solapadas" tiene dos defensas:

1. `sp_crear_reserva` bloquea la fila del vehículo con `SELECT … FOR UPDATE`, así que las reservas del mismo vehículo se atienden en fila; luego valida con `fn_vehiculo_disponible`.
2. Si algo llegara a pasar ese control, la restricción `ex_reserva_vehiculo_periodo` (GiST sobre `daterange(fecha_inicio, fecha_fin, '[)')`) rechaza la inserción. El procedimiento la convierte en `SR001 e_reserva_solapada`.

`concurrentReservationsHaveExactlyOneWinner` lanza las dos solicitudes con un `ExecutorService` de dos hilos sobre la API real y comprueba un ganador y un 409. La idempotencia se protege aparte, con `pg_advisory_xact_lock` sobre la clave: dos reintentos con la misma clave devuelven la misma reserva.

## 4. Prueba de humo de la base de datos

Se ejecutó sobre PostgreSQL 16 con los scripts `01` a `05` recién cargados (11 de noviembre de 2026):

| Caso | Resultado esperado | Resultado obtenido |
|---|---|---|
| Reserva de 3 días | Creada, costo = 3 × tarifa | Creada, costo 720 000 |
| Reserva solapada | `SR001 e_reserva_solapada` | `SR001: El vehículo no está disponible en esas fechas` |
| Reserva contigua (empieza el día en que termina otra) | Aceptada (intervalo `[)`) | Aceptada |
| Fecha fin anterior a inicio | `SR007 e_parametro_invalido` | `SR007: Fechas de reserva inválidas` |
| Cancelar con motivo de 2 letras | `SR007` | `SR007: Indique un motivo de al menos cinco caracteres` |
| Entregar sin confirmar | `SR003 e_transicion_invalida` | `SR003: La reserva debe estar confirmada` |
| Mantenimiento sobre una reserva | `SR002 e_mantenimiento_solapado` | `SR002: El mantenimiento coincide con una reserva vigente` |
| Confirmar dos veces | `SR003` | `SR003: Solo se pueden confirmar reservas solicitadas` |
| Auditoría | Creación y cada cambio | `→ SOLICITADA`, `SOLICITADA → CONFIRMADA` |
| `sirav_reportes` lee `usuario.password_hash` | Permiso denegado | `permission denied for table usuario` |
| `sirav_app` o `sirav_admin` borran una reserva | Permiso denegado | `permission denied for table reserva` |

## 5. Resultados

| Ejecución | Fecha | Resultado |
|---|---|---|
| **SIRAV CI** ([run 43124722372](https://github.com/DavidBejarano309/SIRAV/actions/runs/43124722372)) | 11 nov 2026, 19:05 (Bogotá) | Backend: 11 pruebas, 0 fallos (8 de `IntegrationTest` y 3 de `AccessTest`). Frontend: Vitest aprobado y build de Vite correcto |
| **SIRAV despliegue Docker** ([run 43124722316](https://github.com/DavidBejarano309/SIRAV/actions/runs/43124722316)) | 11 nov 2026, 19:05 (Bogotá) | 14 de 14 comprobaciones de `verificar-despliegue.sh`; respaldo restaurado con conteos iguales; datos conservados tras el reinicio (`docs/evidencias/despliegue-docker.txt`) |
| Playwright en Edge (equipo local) | 8 nov 2026 | 3 de 3 aprobadas (`docs/evidencias/3fn-resultados.txt`) |
| Prueba de humo de la base | 11 nov 2026 | 11 de 11 casos con el resultado esperado (sección 4) |

## 6. Errores encontrados por las pruebas y corregidos

| Error | Cómo se detectó | Corrección |
|---|---|---|
| El usuario `sirav_app` de MongoDB tenía permisos sobre la base `sirav` y no sobre `sirav_3fn`: el backend no arrancaba | Primera ejecución de **SIRAV CI** (`Unauthorized` al crear índices) | `database/mongo/init.js` |
| Entre las 19:00 y la medianoche de Bogotá las pruebas reservaban "mañana" y la entrega se rechazaba | **SIRAV CI** ejecutado a las 19:00 (el runner está en UTC) | Las pruebas usan la fecha de America/Bogota |
| Los errores de negocio no tenían nombre ni código propio | Revisión contra la propuesta (sección 6.4) | Excepciones SR001–SR007 con su nombre `e_` |

## 7. Limitaciones

- Las pruebas de Playwright no corren en la integración continua: necesitan la aplicación levantada y un navegador. Se ejecutaron en Edge el 8 de noviembre de 2026 (3 de 3 aprobadas, `docs/evidencias/3fn-resultados.txt`).
- RNF-04 (menos de 2 segundos) se cumple con los datos de prueba, que son pocos; no se hizo una prueba de carga con volumen.
- Falta repetir `scripts/verificar-despliegue.sh` dentro de la VM del equipo (guía de instalación, sección 11).
