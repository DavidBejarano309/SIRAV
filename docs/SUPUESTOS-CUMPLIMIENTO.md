# Cumplimiento de Supuestos SIRAV

Fuente: [Supuestos_SIRAV.docx](referencias/Supuestos_SIRAV.docx), versión 2.0, noviembre de 2026. Los 101 supuestos funcionales se incorporan a esta implementación; las condiciones externas se declaran por separado. Esta matriz indica soporte en código y pruebas concretas, no 101 pruebas automatizadas independientes.

## Políticas de esta implementación

Una sede; 25 vehículos iniciales en 5 categorías. Reservas y mantenimientos usan [inicio,fin), con fin exclusivo. Se rechazan conflictos; para reprogramar una reserva se cancela y crea otra. Inicio no anterior a hoy en Bogotá, salvo carga histórica deliberada. Mantenimiento programado admite cambios de fecha/motivo. Las tarifas utilizadas son históricas e inmutables en categoría/valor/inicio. COP se redondea a dos decimales; retraso por fecha calendario de Bogotá al 50% diario. Contraseñas se cambian localmente con la clave actual. Las inspecciones tienen versiones y anulación lógica. MongoDB se sincroniza mediante outbox; una ausencia sin evento pendiente se informa como inconsistencia.

Las decisiones operativas implementan la solicitud del usuario; la aprobación académica de supuestos inferidos, equipo, infraestructura y cronograma corresponde al equipo/docente. No se generan evidencias ficticias de VM, video, backups o commits.

## Ubicación del soporte

Backend: `security/` (JWT, usuarios, perfil, bitácora), `catalog/` (flota y mantenimiento), `rental/` (operaciones y cobros), `inspection/` (documentos, evidencias, outbox) y `report/` (reportes/historial). Frontend: vistas con el mismo propósito. SQL: `database/postgres/02-integrity.sql`, `03-procedures.sql`, `06-supuestos.sql` y `backend/src/main/resources/sql/reports/`. Pruebas: `backend/src/test/java/co/edu/sirav/IntegrationTest.java`, `security/AccessTest.java` y `frontend/e2e/`.

## Generales

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| SG-01 | El producto se realizará como prototipo académico funcional con información de prueba, no como servicio comercial listo para uso público. | Prototipo académico, datos ficticios y cobros simulados en README/manual. |
| SG-02 | Se trabajará con una sola sede, sin traslado o gestión multisede de vehículos. | Una sede; el catálogo no incluye traslados. |
| SG-03 | La ejecución se planificó para cuatro semanas y un equipo de dos integrantes, según la propuesta presentada. | Pendiente externo: confirmar integrantes y cronograma con el docente; el código no acredita participación del equipo. |
| SG-04 | Se conservará el ciclo completo desde la consulta hasta el cierre del alquiler como escenario principal de validación. | Flujo principal cubierto por pruebas de integración y lifecycle.spec.js. |
| SG-05 | Las operaciones financieras, contratos, aseguradoras y validaciones externas se representarán únicamente con datos locales o quedarán excluidas. | Sin bancos, aseguradoras, contratos o validadores externos. |

## Usuarios y perfiles

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| US-01 | Se dispondrá de tres perfiles funcionales de prueba: administrador, operador y cliente. | JWT y cuentas ADMIN/OPERADOR/CLIENTE; prueba authEnforcesRolesAndRevokesSessions. |
| US-02 | Las credenciales usadas en la sustentación pertenecerán a usuarios de prueba; no será necesaria una identidad digital externa. | Login local y cuentas ficticias en DemoSeed. |
| US-03 | Un cliente con acceso al sistema estará asociado a un solo usuario; podrá existir un cliente registrado sin cuenta web. | UNIQUE cliente.id_usuario y v_cliente_contacto; pruebas de clientes enlazados y sin cuenta. |
| US-04 | La autorización de acciones dependerá del perfil asignado y no solo de las opciones visibles en la interfaz. | @PreAuthorize y Access verifican cada petición; pruebas de accesos HTTP directos. |
| US-05 | El almacenamiento y la verificación de contraseñas se realizarán localmente mediante hash BCrypt y Spring Security. | SecurityConfig con BCrypt; contraseña nunca se devuelve ni se incluye en la bitácora. |
| US-06 | La administración de usuarios se hará dentro del prototipo, sin verificación externa de documentos o licencias. | UserController y vista Users: alta, roles y estado; sin validación externa. |
| US-07 | Las cuentas de administrador y operador serán habilitadas por el equipo del proyecto; no existirá autoasignación de roles privilegiados. | Registro público fuerza CLIENTE; prueba clientsCannotAssignPrivilegesOrReadOtherPeoplesData. |
| US-08 | El cliente autenticado únicamente podrá consultar y gestionar la información propia a la que le conceda acceso el sistema. | Access.reservation/rental y filtros de lectura; prueba de aislamiento HTTP. |
| US-09 | Un usuario podrá tener más de un rol, dado que la relación Usuario–Rol se modela como N:M mediante Usuario_Rol. | usuario_rol y selección múltiple en Users; prueba usersSupportMultipleRolesProfileChangesAndRevocation. |
| US-10 | El identificador empleado para iniciar sesión deberá ser inequívoco dentro de las cuentas de prueba. | Correo normalizado y UNIQUE; registro duplicado devuelve 409 en prueba. |
| US-11 | Los cambios en cuentas y permisos no eliminarán los historiales de reservas o alquileres vinculados a sus titulares. | Desactivación lógica y token_version; prueba conserva reserva del titular desactivado. |
| US-12 | La recuperación o modificación de credenciales no dependerá de servicios externos de SMS, correo o identidad federada. | Mi perfil permite cambiar contraseña con la actual, sin correo ni SMS. |
| US-13 | Las sesiones vencidas o cerradas impedirán continuar realizando operaciones que exijan autenticación. | JWT con vencimiento, verificación de activo/versión y logout; prueba revoca sesiones. |
| US-14 | Las acciones de administración y los intentos de acceso relevantes podrán quedar registrados en la bitácora de eventos. | AuditService + outbox hacia bitacora_operaciones; Historial de acceso visible al administrador. |

## Catálogo

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| CV-01 | El catálogo corresponderá a una sola sede y una flota simulada de entre 20 y 30 vehículos agrupados en cuatro o cinco categorías. | 04-views-seed.sql + 06-supuestos.sql: carga inicial de 25 vehículos y 5 categorías; prueba del volumen mínimo. |
| CV-02 | Cada vehículo pertenecerá a una categoría y se identificará de forma única por su placa. | FK a categoría y UNIQUE placa en el esquema 3FN. |
| CV-03 | La tarifa diaria se determinará por categoría y período de vigencia; la información usada para cotizar será de demostración. | Tarifas con vigencias y exclusión de solapamiento; cotización por categoría. |
| CV-04 | El estado de disponibilidad para una fecha se calculará a partir de reservas y mantenimientos, sin tratar “reservado” como un atributo independiente permanente. | fn_vehiculo_disponible consulta reservas y mantenimiento; sin estado reservado persistente. |
| CV-05 | Los usuarios podrán consultar las categorías, las características de vehículos y las fechas libres con datos disponibles en la base. | Catalog muestra categoría, características, fechas y cotización desde la API. |
| CV-06 | No se necesitará conocer la ubicación GPS de un vehículo ni actualizar su posición en tiempo real. | Alcance de una sede; sin dependencia de GPS. |
| CV-07 | Los datos iniciales de categorías, vehículos y tarifas se cargarán de forma controlada para la demostración, sin importar inventario desde sistemas de terceros. | Scripts SQL locales e idempotencia de la ampliación; sin inventario externo. |
| CV-08 | Cada vehículo tendrá datos de identificación y características suficientes para distinguirlo en el catálogo. | Ficha Catalog con placa, marca, modelo, año, color y kilometraje. |
| CV-09 | Los vehículos retirados del servicio o bloqueados por mantenimiento no se presentarán como opciones reservables para fechas afectadas. | Disponibilidad filtra INACTIVO y períodos de mantenimiento en PostgreSQL. |
| CV-10 | La disponibilidad que aparece en una consulta informativa podrá cambiar antes de registrar la reserva; la validación definitiva se repetirá al confirmar la operación en la base. | Bloqueo de vehículo y exclusión; concurrentReservationsHaveExactlyOneWinner. |
| CV-11 | El catálogo no tendrá traslado de vehículos entre sedes, porque la operación académica contempla una sola sede. | Modelo de una sede sin proceso de traslados. |
| CV-12 | No se permitirá calcular un valor de alquiler con una tarifa inexistente o fuera de vigencia sin presentar un aviso de validación. | Cotización y procedimiento rechazan falta de tarifa para el período. |
| CV-13 | Los cambios de categoría o características serán operaciones de personal autorizado y no del cliente. | Creación/edición de vehículos solo ADMIN, verificada en backend. |
| CV-14 | El catálogo priorizará consultas de disponibilidad, categoría y tarifa; no incluirá filtros por proximidad GPS ni ubicación en tiempo real. | Filtros por categoría, disponibilidad y fechas; sin proximidad geográfica. |

## Reservas

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| RE-01 | Cada reserva estará asociada exactamente a un cliente y a un vehículo; una reserva no agrupará múltiples vehículos. | FK obligatorias de cliente y vehículo; una unidad por solicitud. |
| RE-02 | Las fechas suministradas representarán un intervalo válido, con fecha final posterior a la inicial. | CHECK fecha_fin>fecha_inicio y validación del intervalo. |
| RE-03 | La comprobación definitiva de disponibilidad ocurrirá en PostgreSQL para impedir períodos superpuestos, incluso ante solicitudes concurrentes. | Bloqueo FOR UPDATE y EXCLUDE; prueba concurrente con un único ganador. |
| RE-04 | La creación de una reserva producirá el estado SOLICITADA; un operador podrá llevarla a CONFIRMADA. | sp_crear_reserva produce SOLICITADA y sp_confirmar_reserva confirma. |
| RE-05 | La cancelación se admitirá únicamente desde SOLICITADA o CONFIRMADA; los estados posteriores no podrán cancelarse por la misma operación. | sp_cancelar_reserva y trigger solo permiten SOLICITADA/CONFIRMADA. |
| RE-06 | Las reservas no podrán coincidir con períodos registrados de mantenimiento del vehículo. | Trigger cruza mantenimiento; prueba adjacentDatesMaintenanceConflictsAndHalfCentRounding. |
| RE-07 | No se exigirá un pago bancario real ni una firma jurídicamente válida para confirmar una reserva académica. | Confirmación local, sin pasarela ni firma. |
| RE-08 | Para solicitar una reserva, el cliente deberá estar registrado o identificado por un registro válido de Cliente. | FK a cliente, licencia requerida y Access.client para cliente autenticado. |
| RE-09 | No se admitirán solicitudes que comiencen antes de la fecha permitida para la demostración, salvo que sean datos históricos cargados deliberadamente. | Procedimiento rechaza inicio anterior a hoy en Bogotá; prueba de fecha pasada. Historial demo deliberado aparte. |
| RE-10 | Las confirmaciones de reservas dependerán de un operador; no se asumirá confirmación automática al crear la solicitud. | POST confirm restringido a ADMIN/OPERADOR; creación no confirma. |
| RE-11 | Cuando se rechace una reserva por solapamiento o mantenimiento, no deberán quedar registros parciales de esa operación. | Transacciones Spring/PostgreSQL; prueba de conflicto verifica ausencia de filas parciales. |
| RE-12 | Las cancelaciones conservarán el registro histórico de la reserva para fines de auditoría, sin eliminarlo físicamente. | Cancelación actualiza estado y genera auditoría, sin DELETE de reserva. |
| RE-13 | Las modificaciones de una reserva confirmada se manejarán mediante una política explícita; mientras no se defina, no se presumirá una función libre de reprogramación. | Política aplicada: cancelar y crear otra; trigger impide editar identidad/fechas. |
| RE-14 | No habrá listas de espera, reservas grupales ni reservas que combinen varios vehículos bajo una sola solicitud. | Formulario y entidad de una reserva por vehículo; sin listas de espera. |
| RE-15 | El límite exacto entre intervalos de fechas consecutivos se definirá de manera única en las consultas y restricciones de PostgreSQL. | Intervalos [inicio,fin); prueba admite reservas adyacentes y rechaza solapamiento. |

## Alquileres e inspecciones

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| AL-01 | Un alquiler se originará a partir de una reserva confirmada y cada reserva dará lugar como máximo a un alquiler. | FK UNIQUE id_reserva y sp_iniciar_alquiler valida CONFIRMADA. |
| AL-02 | El personal operador registrará la entrega y la devolución; no se automatizarán mediante sensores o dispositivos del vehículo. | Entrega/devolución manual, endpoints restringidos a personal. |
| AL-03 | Las inspecciones de entrega y devolución podrán registrar kilometraje, combustible, observaciones y cero o más daños. | DTO Handover + InspectionFields: km, combustible, observaciones y lista de daños vacía o no. |
| AL-04 | Las inspecciones se conservarán como documentos en MongoDB y se relacionarán con el alquiler por id_alquiler; la aplicación validará la referencia. | Access valida alquiler SQL antes de leer/corregir MongoDB; publisher usa alquiler creado en la misma transacción. |
| AL-05 | Las fotografías se representarán mediante referencias o nombres de archivo; las imágenes binarias no se guardarán en las bases. | EvidenceService guarda imágenes en archivos; documentos contienen únicamente referencias. |
| AL-06 | El cierre del alquiler requerirá una devolución y su inspección final antes de liquidar los valores de prueba. | DTO exige inspección no nula; procedimiento guarda devolución, outbox y pago en una transacción. |
| AL-07 | La entrega y la devolución no incluirán firma electrónica con efectos jurídicos ni contrato comercial real. | Flujo académico sin firma ni contrato comercial. |
| AL-08 | No se iniciará un alquiler desde una reserva que permanezca SOLICITADA, CANCELADA o CERRADA. | Procedimiento exige CONFIRMADA; no inicia SOLICITADA/CANCELADA/CERRADA. |
| AL-09 | El operador introducirá manualmente los valores de combustible y kilometraje reportados en la inspección. | Formulario manual con validaciones de combustible y kilometraje. |
| AL-10 | El sistema conservará por separado la inspección de entrega y la de devolución para permitir comparar el estado del automóvil. | MongoDB índice único alquilerId+tipo; prueba verifica ENTREGA y DEVOLUCION. |
| AL-11 | Las referencias fotográficas almacenadas deberán apuntar a archivos accesibles dentro del entorno de demostración. | Upload PNG/JPEG y descarga autenticada; prueba de API y de navegador con imagen real. |
| AL-12 | Las inspecciones corregidas o anuladas deberán seguir una política de control para evitar confundirlas con el registro vigente. | Corrección con versión optimista e historial; anulación lógica con motivo y administrador. |
| AL-13 | La fecha real de devolución podrá diferir de la fecha planeada y alimentará el cálculo de retrasos. | Historial demo puntual/tardío y función de retraso según devolución real. |
| AL-14 | La integración entre PostgreSQL y MongoDB requerirá tratamiento de fallos parciales, dado que no existe llave foránea entre ambos motores. | Outbox transaccional y upsert idempotente; prueba simula fallo de transporte, retiene evento y reintenta. |
| AL-15 | Un alquiler cerrado no volverá a cerrarse ni generará una segunda liquidación al repetir la misma solicitud. | Segundo cierre devuelve 409; prueba conserva un solo pago. |

## Mantenimiento

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| MA-01 | Los mantenimientos serán ingresados por personal autorizado mediante datos de prueba, no desde talleres externos. | CatalogController restringe altas a personal; datos ingresados localmente. |
| MA-02 | Cada mantenimiento se asociará a un vehículo e incluirá un período durante el cual no podrá ofrecerse para una nueva reserva. | FK vehículo, período requerido y bloqueo en disponibilidad. |
| MA-03 | La detección de conflictos entre mantenimiento y reserva dependerá de verificaciones de integridad del sistema. | Trigger serializa sobre vehículo y verifica reservas vigentes. |
| MA-04 | El módulo gestionará bloqueos de disponibilidad, no inventarios de repuestos, proveedores ni costos reales de taller. | Módulo de fechas, motivo y estado; sin inventario de taller. |
| MA-05 | El tratamiento de un mantenimiento registrado sobre un período ya reservado se definirá antes de las pruebas finales. | Política aplicada: rechazar cruce con reserva vigente (409), no desplazarla. |
| MA-06 | Cuando termine un mantenimiento, la disponibilidad seguirá dependiendo de otras reservas vigentes para el mismo vehículo. | Disponibilidad vuelve a consultar reservas y otros bloqueos tras completar mantenimiento. |
| MA-07 | Los períodos de mantenimiento estarán definidos mediante fechas coherentes y suficientes para bloquear la disponibilidad. | NOT NULL y CHECK fecha_fin>fecha_inicio. |
| MA-08 | El sistema deberá definir qué hacer si un mantenimiento se programa cuando ya existe una reserva vigente para ese período. | Conflicto rechazado; prueba comprueba rollback del INSERT. |
| MA-09 | Los mantenimientos superpuestos del mismo vehículo se revisarán para evitar bloqueos duplicados o contradictorios. | Restricción EXCLUDE para mantenimientos PROGRAMADOS; prueba de duplicado. |
| MA-10 | Cada registro de mantenimiento tendrá información suficiente sobre motivo y período de indisponibilidad. | Descripción obligatoria en DTO y fechas obligatorias. |
| MA-11 | Si se modifica o termina un mantenimiento, una nueva consulta de disponibilidad reflejará el período actualizado. | PUT permite editar fecha/motivo de PROGRAMADO; prueba consulta disponibilidad antes/después. |
| MA-12 | Solo el personal administrativo u operador autorizado gestionará los bloqueos por mantenimiento. | @PreAuthorize ADMIN/OPERADOR; cliente recibe 403. |
| MA-13 | El historial de mantenimiento permanecerá consultable como antecedente del vehículo, incluso cuando deje de estar bloqueado. | PATCH completa/cancela y GET conserva el registro; prueba comprueba estado persistido. |
| MA-14 | Las fechas de mantenimiento se registrarán manualmente, sin integración con talleres, agendas externas o telemetría. | Formularios manuales sin agendas ni telemetría. |

## Cobros simulados

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| CO-01 | Todos los importes mostrados serán valores académicos en pesos colombianos (COP) y no representarán cobros bancarios efectivos. | Vista Cobros simulados y formato es-CO/COP con dos decimales. |
| CO-02 | El costo base de un alquiler se calculará a partir de los días aplicables y la tarifa diaria vigente de la categoría. | fn_calcular_costo usa días del intervalo y tarifa asociada a la reserva. |
| CO-03 | Por cada día de retraso en una devolución se aplicará un cargo adicional equivalente al 50 % de la tarifa diaria, como regla de demostración. | fn_calcular_cargo_retraso aplica 50% diario; pruebas de fecha límite y medio centavo. |
| CO-04 | Los cargos adicionales y los pagos de prueba quedarán asociados al alquiler para permitir su trazabilidad. | FK id_alquiler en pago/cargo_adicional; detalle de cobro consulta ambos. |
| CO-05 | El cierre del alquiler ejecutará la liquidación de demostración según las reglas del sistema. | sp_cerrar_alquiler liquida y deja pago SIMULADO en una transacción. |
| CO-06 | No se realizará conciliación con bancos ni emisión de documentos tributarios o facturas electrónicas reales. | Sin conciliación ni facturación tributaria en endpoints o dependencias. |
| CO-07 | No se aplicarán promociones, cupones o descuentos comerciales a menos que se incorporen formalmente al alcance y sus reglas. | Fórmulas sin descuentos, cupones ni promociones. |
| CO-08 | Los resultados monetarios seguirán una convención uniforme de redondeo y visualización en pesos colombianos. | NUMERIC, round(...,2) y money con dos decimales; prueba de 0.005 a 0.01. |
| CO-09 | El instante de referencia para determinar un día de retraso se establecerá de forma consistente entre fechas planeadas y reales. | Días calendario America/Bogota; pruebas 23:59:59 y 00:00 del siguiente día. |
| CO-10 | Los pagos de prueba se almacenarán como registros de simulación y no producirán cargos a tarjetas o cuentas bancarias. | CHECK tipo=SIMULADO y vista explícita de pagos simulados. |
| CO-11 | Una corrección de tarifa vigente no modificará arbitrariamente la liquidación de alquileres ya cerrados. | Trigger protege tarifa ya utilizada; prueba rechaza cambio y conserva cálculo histórico. |
| CO-12 | La liquidación de cierre asociará a un único alquiler sus cargos adicionales, evitando duplicaciones por reintentos. | Bloqueo de alquiler y estado ACTIVA; segundo cierre no duplica pago/cargos. |
| CO-13 | Los reportes de ingresos distinguirán explícitamente los valores simulados del dinero efectivamente recaudado. | R2 ingresos_simulados y títulos explícitos de R2/R5 en Reports. |
| CO-14 | No se implementarán devoluciones bancarias, financiación ni conciliación con medios de pago externos. | Sin medios de pago bancarios, financiación ni reembolsos. |

## Historial y reportes

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| HR-01 | PostgreSQL será la fuente oficial de reservas, alquileres, cargos, pagos simulados y auditoría transaccional. | PostgreSQL conserva dominio y auditoria_reserva; MongoDB es proyección documental. |
| HR-02 | MongoDB conservará inspecciones y bitácoras de eventos con estructura documental flexible. | inspecciones_vehiculo y bitacora_operaciones, índices y consultas reales. |
| HR-03 | Los reportes SQL cubrirán ocupación, ingresos simulados, ranking de vehículos, comportamiento de clientes, devoluciones tardías y disponibilidad. | Seis archivos sql/reports y prueba allSixSqlReportsExecuteAgainstRealDatabase. |
| HR-04 | Las agregaciones de MongoDB permitirán analizar promedios de kilometraje/combustible, zonas de daño e incidencias por vehículo. | InspectionController.analytics ejecuta tres pipelines MongoDB. |
| HR-05 | La calidad de los resultados dependerá de la consistencia y variedad del conjunto de datos simulado; no se usarán estadísticas de una compañía real. | Flota ficticia y historial de diez alquileres objetivo con puntualidad/retrasos/daños y una cancelación; carga omite conflictos existentes. |
| HR-06 | Las consultas frecuentes buscarán responder en menos de dos segundos en el ambiente y con el volumen de datos de prueba especificado. | Medición reproducible de HTTP local en docs/evidencias/supuestos-medicion.txt; validar nuevamente en la VM. |
| HR-07 | El acceso a consultas de historial y auditoría respetará los permisos de usuario definidos para el sistema. | Autorización HTTP para historial, auditoría y reportes; prueba de acceso de cliente. |
| HR-08 | Los reportes se construirán únicamente con datos del prototipo, sin conectarse a proveedores externos de analítica. | JdbcTemplate y MongoTemplate consultan únicamente bases del prototipo. |
| HR-09 | Las fechas inicial y final de los reportes, cuando se soliciten, respetarán el orden y período seleccionado por el usuario. | Rangos SQL hasta exclusivo de 1 a 366 días; entradas invertidas se rechazan. |
| HR-10 | El acceso a reportes agregados de la empresa se limitará a perfiles que tengan autorización para datos operativos globales. | ReportController e HistoryController restringen datos globales a personal; seguridad de usuarios solo ADMIN. |
| HR-11 | El historial visible para un cliente no expondrá alquileres, inspecciones ni pagos de otros clientes. | Filtros por titular en reservas/alquileres/cobros y Access en inspecciones/pagos. |
| HR-12 | Si una inspección documental no puede recuperarse, el sistema deberá informar la inconsistencia sin inventar datos faltantes. | inspection-status distingue PENDIENTE/INCONSISTENTE/DISPONIBLE y anulaciones; prueba borra y restaura un documento en test. |
| HR-13 | El ranking de los cinco vehículos más alquilados por categoría contemplará empates según la función RANK() prevista. | ranking.sql usa RANK() y filtra <=5; historial demo con cantidades iguales. |
| HR-14 | La auditoría permitirá revisar cambios de estado de reservas y principales eventos de negocio con los datos disponibles. | Trigger auditoria_reserva y eventos outbox; vista Historial para consultar cambios. |
| HR-15 | Los informes no requerirán tableros de inteligencia de negocios, procesamiento masivo ni actualización en tiempo real. | Reportes tabulares y agregaciones, sin plataforma externa de BI. |

## Técnicos

| ID | Supuesto del documento | Soporte y verificación |
| --- | --- | --- |
| ST-01 | La base relacional seleccionada será PostgreSQL; su modelo contempla trece entidades y normalización hasta tercera forma normal (3FN). | Esquema 3FN de 13 entidades preservado byte por byte; outbox es infraestructura adicional. |
| ST-02 | MongoDB se utilizará para inspecciones y bitácora; no existirá integridad referencial declarativa entre MongoDB y PostgreSQL. | Referencias de alquiler verificadas por Access; no se declara FK entre motores. |
| ST-03 | La solución se ejecutará en Linux virtualizado, con Ubuntu Server como opción prevista y servicios de aplicación y bases de datos configurados. | Pendiente externo: despliegue real en Ubuntu/VM. Compose y guía incluidos; no se afirma ejecución en Linux. |
| ST-04 | La máquina virtual tendrá recursos suficientes para operar ambos motores y el servidor de aplicación; se estiman 6 GB RAM, 2 vCPU y 40 GB si el anfitrión lo permite (mínimo 4 GB RAM). | Pendiente externo: asignación y comprobación de RAM/vCPU/disco del anfitrión. |
| ST-05 | La operación principal dependerá de procedimientos, funciones, triggers, restricciones y transacciones para conservar la consistencia. | Funciones, procedimientos PL/pgSQL, triggers, restricciones y transacciones; pruebas contra PostgreSQL real. |
| ST-06 | Se dispondrá de controles de acceso y respaldos demostrables, así como un repositorio Git con historial del trabajo. | Parcial: controles y script backup.sh incluidos. Pendientes ejecución/restauración de respaldo e historial Git real del equipo. |
