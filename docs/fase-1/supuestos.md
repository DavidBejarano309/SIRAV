# Documento de supuestos

Resumen de los supuestos que rigen el proyecto. El documento completo del equipo, versión 2.0 con 101 supuestos funcionales, está en [`docs/referencias/Supuestos_SIRAV.docx`](../referencias/Supuestos_SIRAV.docx). Su verificación uno por uno está en [`docs/SUPUESTOS-CUMPLIMIENTO.md`](../SUPUESTOS-CUMPLIMIENTO.md).

## Del negocio

- Una sola sede, con una flota inicial de 25 vehículos en 5 categorías (Compacto, SUV, Sedán, Camioneta y Van), dentro del rango de 20 a 30 vehículos de la propuesta (`06-supuestos.sql`).
- Cada reserva corresponde a un cliente y a un vehículo.
- Los precios, pagos y cargos son valores de demostración en pesos colombianos; no hay pasarela de pago.
- Las fotografías de inspección se adjuntan como imágenes PNG o JPEG de hasta 5 MB. Los archivos se guardan en el disco del servidor de la aplicación, fuera de las bases. MongoDB guarda solo su referencia (campo `evidencias`, hasta 10 por inspección), y solo el personal o el cliente de esa reserva pueden descargarlas.
- Existen tres perfiles de usuario: administrador, operador y cliente.

## Técnicos

- PostgreSQL es la fuente única de verdad para reservas, alquileres y pagos de prueba.
- MongoDB guarda inspecciones y bitácora de eventos, enlazadas por el identificador del alquiler.
- El sistema se despliega en tres máquinas virtuales Ubuntu Server 24.04 en VirtualBox: PostgreSQL, MongoDB y web (Nginx, React y la API Java). Cada una tiene 2 GB de RAM y los motores corren en contenedores. Como alternativa, todo puede ejecutarse con Docker Compose en una sola VM.
- Se dispone de un equipo anfitrión con recursos suficientes para la VM (recomendado: 6 GB de RAM, 2 núcleos y 40 GB de disco).
- Todo el software usado es gratuito o de código abierto.

## De gestión

- El equipo lo forman dos integrantes y el plazo es de cuatro semanas.
- El trabajo se organiza en cuatro sprints semanales en Jira.
- El alcance queda congelado con la propuesta; lo adicional pasa a ampliaciones futuras.

## Derivados de la implementación (Fase 2)

Supuestos que la propuesta no fijaba y que se decidieron al construir la aplicación SIRAV 3FN. Entre paréntesis, el archivo de `database/postgres/` o del backend donde se aplican.

### Fechas y cobro

- Todas las fechas y horas se interpretan en la zona horaria de Bogotá (America/Bogota).
- Una reserva ocupa el intervalo semiabierto `[fecha_inicio, fecha_fin)`: el día de fin el vehículo ya queda libre, así que una reserva puede empezar el mismo día en que termina otra (`01-schema.sql`, `ex_RESERVA_vehiculo_periodo`, RN-01).
- La fecha de fin debe ser posterior a la de inicio, y no se aceptan reservas que empiecen antes de hoy (`sp_crear_reserva`).
- El costo base es el número de días (fecha de fin menos fecha de inicio) por el valor diario de la tarifa (`fn_calcular_costo`, RN-04).
- La tarifa aplicada es la de la categoría del vehículo cuya vigencia cubre todo el período reservado. Una categoría no puede tener dos tarifas con vigencias que se crucen (`ex_tarifa`, `sp_crear_reserva`).
- Una reserva no se modifica: para cambiar fechas, vehículo o cliente se cancela y se crea otra (`trg_validar_reserva`).
- Cada día calendario de devolución posterior a la fecha de fin genera un cargo del 50 % de la tarifa diaria; devolver el día de fin no es retraso (`fn_calcular_cargo_retraso`, RN-04).
- Al cerrar un alquiler se registra un único pago **simulado** y aprobado por el costo base más los cargos adicionales; no hay pasarela de pago (`sp_cerrar_alquiler`).
- El kilometraje nunca disminuye y el combustible se registra como porcentaje del tanque, de 0 a 100 (`ck_alquiler`, `sp_iniciar_alquiler`).
- La entrega del vehículo solo puede hacerse dentro del período reservado (`sp_iniciar_alquiler`).
- Si la aplicación reintenta la creación de una reserva con la misma clave de idempotencia, se devuelve la reserva ya creada; si la clave llega con otros datos, se rechaza (`sp_crear_reserva`).

### Disponibilidad de la flota

- Solo bloquean un vehículo las reservas SOLICITADA, CONFIRMADA o ACTIVA; las CERRADAS y CANCELADAS no (RN-01).
- Un mantenimiento PROGRAMADO bloquea las reservas en sus fechas; uno COMPLETADO o CANCELADO no. Tampoco se puede programar un mantenimiento encima de una reserva vigente (RN-02, `trg_validar_mantenimiento`, `fn_vehiculo_disponible`).
- Un vehículo INACTIVO no se puede reservar ni entregar. Ese estado lo fija el administrador.
- El estado del vehículo pasa a ALQUILADO al entregarlo y vuelve a DISPONIBLE al cerrar el alquiler (`trg_actualizar_estado_vehiculo`). La disponibilidad por fechas no depende de esa columna, sino de las reservas y los mantenimientos.

### Estados definidos por el equipo

La propuesta fija los estados de la reserva (SOLICITADA, CONFIRMADA, ACTIVA, CERRADA, CANCELADA). Los demás se definieron así (`02-integrity.sql`):

| Tabla | Valores |
|---|---|
| Alquiler (estado) | ACTIVA, CERRADA |
| Pago (estado) | APROBADO, ANULADO |
| Pago (tipo) | SIMULADO |
| Mantenimiento (estado) | PROGRAMADO, COMPLETADO, CANCELADO |
| Vehículo (estado operativo) | DISPONIBLE, ALQUILADO, INACTIVO |

### Errores de negocio

Cada regla que la base rechaza devuelve un código propio (SR001 a SR008) y el nombre de la excepción; la aplicación los muestra como error 409 (`02-integrity.sql`, `03-procedures.sql`, `ApiErrors.java`).

| Código | Excepción | Cuándo ocurre |
|---|---|---|
| SR001 | `e_reserva_solapada` | Otra reserva vigente ocupa el período |
| SR002 | `e_mantenimiento_solapado` | El período cruza un mantenimiento programado |
| SR003 | `e_transicion_invalida` | Cambio de estado no permitido o reserva modificada |
| SR004 | `e_inspeccion_requerida` | Falta la inspección de entrega o devolución |
| SR005 | `e_vehiculo_no_disponible` | Vehículo inactivo, inexistente o no apto para entrega |
| SR006 | `e_tarifa_no_vigente` | Ninguna tarifa cubre el período |
| SR007 | `e_parametro_invalido` | Fechas, motivo, kilometraje o clave de idempotencia inválidos |
| SR008 | `e_tarifa_historica` | Se intenta cambiar una tarifa que ya usan reservas, o acortar su vigencia (las tarifas usadas son históricas: se cierra su vigencia y se crea otra) |

### Personas y acceso

- Un cliente puede registrarse en mostrador sin cuenta en la aplicación. Si tiene cuenta, su nombre y correo salen del usuario y no se repiten en cliente (`ck_CLIENTE_origen_identidad`, vista `v_cliente_contacto`).
- Un usuario puede tener varios perfiles a la vez (tabla `usuario_rol`).
- La aplicación se conecta con el usuario de base de datos `sirav_app`, que no puede insertar, modificar ni borrar directamente reservas, alquileres, pagos ni auditoría: lo hace solo a través de los procedimientos `sp_` (`05-permissions.sql`).
- Para consultas y reportes existe el perfil `sirav_reportes`, de solo lectura, que no ve contraseñas; el perfil `sirav_admin` administra catálogo, tarifas y mantenimientos (`05-permissions.sql`).
- Al cerrar sesión, al cambiar la contraseña o al modificar los perfiles de un usuario se invalidan todos sus tokens (`usuario.token_version`).
- Solo el administrador crea cuentas de personal, asigna perfiles y desactiva cuentas; las cuentas no se borran, para conservar el historial.

### MongoDB

- Cada alquiler tiene como máximo una inspección de entrega y una de devolución (índice único `alquilerId` + `tipo`).
- Las inspecciones no se borran: se anulan de forma lógica y guardan su historial de versiones.
- Las inspecciones y la bitácora llegan a MongoDB a través de la tabla `evento_outbox`: si MongoDB no está disponible, la operación en PostgreSQL no se pierde y el evento se publica después (`OutboxPublisher`).
