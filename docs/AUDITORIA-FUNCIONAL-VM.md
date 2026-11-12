# Auditoría funcional, SQL, PL/pgSQL, MongoDB y concurrencia

Auditoría ejecutada el 10–11 de noviembre de 2026 sobre las VM del proyecto. Se identificaron y corrigieron siete casos defectuosos. El resultado final de las pruebas funcionales es **81 aprobadas: 72 Java, 5 frontend y 4 flujos completos de navegador**, además de **64 solicitudes HTTP concurrentes**.

## Entorno y aislamiento

| Componente | Entorno verificado |
| --- | --- |
| Relacional | PostgreSQL 17.6 en SIRAV-PostgreSQL, 2048 MB |
| Documental | MongoDB 8.0.5 en SIRAV-MongoDB, 2048 MB |
| Aplicación | Ubuntu Server 24.04 LTS, Nginx y Java 21 en SIRAV-Web, 2048 MB |
| Pruebas Java | JDK 23 compilando para Java 21, API de prueba en Windows y motores reales en las VM |
| Navegador y HTTP | Frontend y API de auditoría ejecutándose dentro de SIRAV-Web, puerto temporal 8089 |
| Base normal | `sirav_3fn` |
| Bases de auditoría | `sirav_audit_20261110231416` y `sirav_audit_20261110233432`, en ambos motores |

La primera pareja conserva la reproducción de los fallos. La segunda se inicializó desde cero con las correcciones SQL y se utilizó para la comprobación completa. Las pruebas de escritura, carga y navegador operaron sobre esas bases aisladas. Se utilizaron credenciales JWT de auditoría distintas de las de la aplicación normal.

## Resultados automatizados

| Suite | Casos | Fallos finales |
| --- | ---: | ---: |
| Integración existente: autenticación, perfiles, reservas, alquileres, archivos y reportes | 15 | 0 |
| Permisos unitarios | 3 | 0 |
| Contratos SQL, restricciones, funciones, procedimientos y reportes numéricos | 24 | 0 |
| Concurrencia de SQL, API, permisos y MongoDB | 11 | 0 |
| Entradas inválidas y seguridad de la API | 8 | 0 |
| Validación documental, índices, agregaciones y recuperación de eventos | 11 | 0 |
| Frontend Vitest | 5 | 0 |
| Flujos Playwright en la VM | 4 | 0 |
| **Total de pruebas** | **81** | **0** |

Se repitieron adicionalmente los 11 casos documentales para comprobar numéricamente las tres agregaciones MongoDB. Esa repetición no se suma al total de casos distintos.

La cobertura acumulada JaCoCo de las ejecuciones Java de esta auditoría fue **85,8% de líneas y 64,6% de ramas**. Las pruebas HTTP y del navegador contra la API Linux se verificaron aparte. La cobertura y la carga indicada delimitan el alcance de esta revisión.

## Fallos corregidos

| Caso reproducido | Comportamiento anterior | Resultado corregido |
| --- | --- | --- |
| Cancelación SQL con motivo NULL | Se cancelaba sin motivo | PL/pgSQL rechaza la operación y conserva la reserva |
| Reserva concurrente con cierre de tarifa | La vigencia podía quedar más corta que la reserva creada por la otra transacción | El trigger mantiene un bloqueo compartido sobre la tarifa; la modificación incompatible se rechaza |
| Crear usuario con un rol NULL | Se creaba una cuenta sin roles válidos | HTTP 400 antes de insertar |
| Cambiar permisos con un rol NULL | Podían borrarse los roles existentes | HTTP 400 y conservación de los permisos |
| Inspección con un elemento NULL en daños | Se aceptaba y podía romper la lectura del formulario | HTTP 400 antes de crear el alquiler o corregir el documento |
| Cerrar tarifa sin fecha | HTTP 500 | HTTP 400 mediante un cuerpo tipado y validado |
| Cambiar mantenimiento sin estado | HTTP 500 | HTTP 400 mediante un cuerpo tipado y validado |

La migración reejecutable está en [07-concurrency-validation.sql](../database/postgres/07-concurrency-validation.sql). Las validaciones están en `UserController`, `RentalService` y `CatalogController`.

Una expectativa inicial de prueba del reporte `late` se ajustó: el reporte incluye alquileres con cargos adicionales aunque sus días de retraso sean cero. Se comprobó el valor de esos cargos; no se cambió esa regla del reporte.

## SQL y PL/pgSQL

Se verificó el inventario de **15 rutinas propias: 9 funciones y 6 procedimientos**, sus 5 triggers habilitados, las 2 vistas y las 14 tablas públicas (13 entidades y outbox).

| Rutina o grupo | Comprobación ejecutada |
| --- | --- |
| `fn_actor` | Actor de auditoría local a la transacción, sin filtrarse a la siguiente operación |
| `fn_vehiculo_disponible` | Reservas, mantenimiento, intervalos adyacentes, cancelación y vehículo inactivo |
| `fn_calcular_costo` | Tarifa histórica y costo por días; comprobación exacta del importe |
| `fn_calcular_cargo_retraso` | Cambio de día en Bogotá, límites horarios y redondeo de medio centavo |
| `trg_validar_reserva` | Inmutabilidad de datos, estados permitidos, disponibilidad y protección concurrente de la tarifa |
| `trg_validar_mantenimiento` | Cruces con reservas y competencia entre inserciones |
| `trg_auditar_reserva` | Secuencia SOLICITADA → CONFIRMADA → ACTIVA → CERRADA, actor y eventos |
| `trg_actualizar_estado_vehiculo` | ALQUILADO al entregar; DISPONIBLE y kilometraje actualizado al devolver |
| `trg_proteger_tarifa_historica` | Rechazo de cambios de precio/inicio y de vigencias incompatibles con reservas |
| `sp_crear_reserva` | Fechas, solapamiento, idempotencia, reintentos con otros datos y concurrencia |
| `sp_confirmar_reserva` | Transición válida y competencia contra cancelación |
| `sp_cancelar_reserva` | Motivo obligatorio, historia y estado final consistente |
| `sp_iniciar_alquiler` | Reserva confirmada, kilometraje, combustible, JSON y una única entrega |
| `sp_cerrar_alquiler` | Rollback de entradas inválidas, una devolución, un pago e inspección final |
| `sp_cargar_historial_demo` | Reejecución sin duplicar ni sobrescribir reservas, alquileres y pagos |

También se probaron claves foráneas, unicidad, correo normalizado, identidad 3FN de clientes, años y kilometrajes inválidos, importes, estados y restricciones de exclusión. Se comprobaron los códigos SQLSTATE de los rechazos, de modo que un error de conexión no cuente como un conflicto esperado.

El rol `sirav_app` no puede escribir directamente reservas, alquileres, pagos o auditoría, ni crear objetos en el esquema público. Las operaciones transaccionales usan los procedimientos con `SECURITY DEFINER`.

### Los seis reportes

`occupancy`, `revenue`, `ranking`, `clients`, `late` y `availability` se ejecutaron contra datos reales de prueba. Se comprobaron valores conocidos: un día ocupado, posición del vehículo, una reserva del cliente, disponibilidad tras devolver y **135.000 de pago con dos cargos que suman 15.000**, sin multiplicar importes por los JOIN. Las vistas conservaron la identidad del cliente y los totales de costos, cargos y pagos.

## MongoDB y sincronización

| Función | Resultado verificado |
| --- | --- |
| Validación del documento | Rechazo de campos obligatorios ausentes, tipo de inspección inválido, daños que no sean array y anulación que no sea booleana |
| Índice único `alquilerId` / `tipo` | Rechazo de documentos duplicados con código 11000 |
| Creación y lectura | Dos inspecciones sincronizadas tras entregar y devolver |
| Corrección | Control optimista de versión e historial original conservado |
| Anulación | Cambio lógico, conservación del documento y exclusión de consultas de vigentes |
| Consulta compleja | Combinación de vehículo, fecha y daños de severidad ALTA |
| Agregaciones | Valores de categoría, zona/mes e incidencias por vehículo contrastados con una muestra controlada |
| Outbox concurrente | Tres publicadores procesaron 64 eventos sin pérdida ni duplicados |
| Recuperación | Una conexión real a un puerto sin servidor falló; el evento quedó pendiente, aumentó su contador y se publicó al restablecer el destino correcto |

Los casos existentes también simularon fallos del transporte MongoDB. La prueba de conexión fallida adicional utilizó un cliente independiente; la VM MongoDB de la aplicación siguió funcionando.

## Concurrencia

La batería Java usó barreras para iniciar operaciones simultáneas. Incluyó ocho reservas sobre el mismo vehículo, ocho reintentos con una clave, ocho mantenimientos superpuestos, reservas frente a mantenimiento, doble entrega/devolución, edición documental, publicadores paralelos, cierre de tarifa y desactivación simultánea de los dos últimos administradores. Se verificaron además ocho reservas en vehículos independientes.

La prueba HTTP se ejecutó contra la API Linux y Nginx de la VM:

| Escenario HTTP | Solicitudes simultáneas | Respuestas verificadas |
| --- | ---: | --- |
| Reserva del mismo vehículo, tres rondas | 8 por ronda | 1 × 201 y 7 × 409 en cada ronda |
| Reintentos con la misma clave | 8 | 8 × 201, un único identificador y una sola creación en auditoría |
| Entrega | 8 | 1 × 200 y 7 × 409; un alquiler |
| Cierre y pago | 8 | 1 × 200 y 7 × 409; un pago |
| Corrección MongoDB con la misma versión | 8 | 1 × 200 y 7 × 409; una versión e historial únicos |
| Anulación del mismo documento | 8 | 1 × 204 y 7 × 404; documento conservado y anulado |

**Total: 64 solicitudes concurrentes en ocho grupos.** Los p95 observados por grupo fueron de aproximadamente **1,06 a 2,89 segundos**, con ocho clientes y las VM de 2 GB en este equipo. La prueba valida esta carga concreta y el aislamiento de las operaciones.

La misma ejecución comprobó por HTTP creación/edición de vehículos, bloqueo de cambios con reservas, kilometraje no decreciente, categorías, tarifas consecutivas, cotizaciones, mantenimiento y carga/descarga de evidencia a través del alquiler. Al terminar respondieron correctamente 20 consultas de salud consecutivas.

## Navegador

Pasaron los cuatro escenarios existentes sobre la instancia de auditoría en la VM:

1. Reserva, confirmación, entrega, evidencia descargable, devolución y pago simulado.
2. Navegación por los siete módulos, perfil e historial.
3. Creación de cuenta con varios roles y desactivación.
4. Acceso limitado del cliente y vista móvil de 390 píxeles sin desbordamiento.

## Aplicación de correcciones y datos conservados

Se respaldó el esquema normal antes de aplicar la migración SQL. Los conteos de entidades antes y después fueron iguales:

| Entidad | Antes | Después |
| --- | ---: | ---: |
| Usuarios | 3 | 3 |
| Clientes | 1 | 1 |
| Vehículos | 25 | 25 |
| Reservas | 11 | 11 |
| Alquileres | 10 | 10 |
| Pagos | 10 | 10 |

Las bases y evidencias de auditoría se conservaron. El servicio temporal y su puerto web se retiraron al terminar las pruebas. La migración también quedó copiada en el directorio de inicialización de la VM PostgreSQL.

La API normal se actualizó con el JAR corregido y pasó **48 comprobaciones HTTP finales**, que incluyeron lecturas de todos los módulos, los seis reportes, detalles e historial de reservas, pagos, inspecciones y **20 respuestas de salud consecutivas `UP`**. La aplicación quedó disponible en **http://192.168.1.18**.

El arranque de esa actualización tardó aproximadamente 11 minutos bajo el modo NEM de VirtualBox. El comprobador inicial tenía un límite de seis minutos y agotó su plazo mientras el proceso seguía cargando. Se esperó sin reiniciar de nuevo, se confirmó la recuperación y se amplió el plazo del despliegue a 15 minutos para este entorno.

Al comienzo se observó un HTTP 503 con `NoRouteToHostException` entre la API y PostgreSQL. La comprobación posterior de rutas, ARP, ping y TCP respondió correctamente. La interrupción transitoria no se reprodujo en los escenarios finales; su causa exacta no quedó determinada. Esta incidencia se conserva separada de los siete defectos funcionales corregidos.

## Evidencias y repetición

Resultados locales sin credenciales en `.runtime/audit/sirav_audit_20261110233432/`:

- `summary.json`: resumen de resultados y conteos.
- `runs/20261110-233713/`: ejecución completa de 72 casos, con log Maven y reportes XML.
- `runs/20261110-235851/`: comprobación documental adicional de 11 casos.
- `playwright.json`, `playwright.log`, `browser-evidence/`: resultados y capturas del navegador.
- `http-concurrency.json`: respuestas y tiempos de las 64 solicitudes.
- `deployment/`: respaldo de esquema y conteos previos/posteriores.
- `production-smoke.json`: comprobación final de lectura y salud de la aplicación normal.

La primera base conserva las reproducciones anteriores en `.runtime/audit/sirav_audit_20261110231416/before-fixes/`. `settings.json` contiene secretos de prueba y está restringido al usuario Windows; no debe incluirse en entregas públicas.

Para repetir con bases nuevas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-vm-audit.ps1
# Usa la ruta settings.json que devuelve la preparacion:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-vm-audit.ps1 -Settings RUTA-SETTINGS -Clean
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/vm-audit-web.ps1 -Settings RUTA-SETTINGS -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-vm-browser.ps1 -Settings RUTA-SETTINGS
node scripts/audit-http.cjs RUTA-SETTINGS http://192.168.1.18:8089
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/vm-audit-web.ps1 -Settings RUTA-SETTINGS -Action Stop
```

Los scripts validan el prefijo de base y el puerto aislado de auditoría. Las credenciales y los documentos se generan para ese entorno. Si cambia la IP LAN de SIRAV-Web, utiliza la dirección vigente al ejecutar las pruebas HTTP y el parámetro `-Url` de la prueba de navegador.
