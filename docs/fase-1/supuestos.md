# Documento de supuestos — SIRAV

## Del negocio

- Una sola sede y una flota de prueba de 20 a 30 vehículos en 4 o 5 categorías.
- Cada reserva corresponde a un cliente y a un vehículo.
- Los precios, pagos y cargos son valores de demostración en pesos colombianos; no hay pasarela de pago.
- Las fotografías de inspección se referencian por nombre de archivo; no se almacenan en la base.
- Existen tres perfiles de usuario: administrador, operador y cliente.

## Técnicos

- PostgreSQL es la fuente única de verdad para reservas, alquileres y pagos de prueba.
- MongoDB guarda inspecciones y bitácora de eventos, enlazadas por el identificador del alquiler.
- La aplicación y las dos bases de datos se ejecutan en una máquina virtual Ubuntu Server.
- Se dispone de un equipo anfitrión con recursos suficientes para la VM (recomendado: 6 GB de RAM, 2 núcleos y 40 GB de disco).
- Todo el software usado es gratuito o de código abierto.

## De gestión

- El equipo lo forman dos integrantes y el plazo es de cuatro semanas.
- El trabajo se organiza en cuatro sprints semanales en Jira.
- El alcance queda congelado con la propuesta; lo adicional pasa a ampliaciones futuras.

## Derivados de la implementación (Fase 2)

Supuestos que la propuesta no fijaba y que se decidieron al construir la base de datos. Entre paréntesis, el script donde se aplican.

### Fechas y cobro

- Todas las fechas y horas se interpretan en la zona horaria de Bogotá (America/Bogota).
- Una reserva ocupa días completos: el vehículo queda bloqueado desde la fecha de inicio hasta la fecha de fin, ambas incluidas (`01_creacion.sql`, RN-01).
- No se aceptan reservas que empiecen en una fecha pasada (`sp_crear_reserva`).
- El costo base es el número de días (fecha de fin menos fecha de inicio) por el valor diario de la tarifa, con un mínimo de un día (`fn_calcular_costo`, RN-04).
- Se aplica la tarifa vigente de la categoría en la fecha de inicio de la reserva. Una categoría no puede tener dos tarifas con vigencias que se crucen (`01_creacion.sql`, `fn_obtener_tarifa_vigente`).
- Cada día calendario de devolución posterior a la fecha de fin genera un cargo del 50 % de la tarifa diaria; devolver el mismo día de la fecha de fin, a cualquier hora, no es retraso (`fn_calcular_cargo_retraso`, RN-04).
- Al cerrar un alquiler se registra un único pago de prueba, aprobado, por el costo base más todos los cargos adicionales (`sp_cerrar_alquiler`).
- El valor de los daños lo estima el operador durante la inspección de devolución y se registra como cargo adicional (`sp_cerrar_alquiler`).
- El combustible se registra como porcentaje del tanque, de 0 a 100.

### Disponibilidad de la flota

- Solo bloquean un vehículo las reservas en estado SOLICITADA, CONFIRMADA o ACTIVA; las CERRADAS y CANCELADAS no (RN-01).
- Un mantenimiento PROGRAMADO o EN_CURSO bloquea las reservas en esas fechas; uno CANCELADO no (RN-02, `trg_validar_mantenimiento`).
- Un vehículo INACTIVO no se puede reservar. Ese estado lo fija el administrador y los triggers no lo cambian.
- El estado del vehículo se calcula a partir de sus reservas y mantenimientos, con esta prioridad: INACTIVO, ENTREGADO, MANTENIMIENTO, RESERVADO y DISPONIBLE (`trg_actualizar_estado_vehiculo`).

### Estados definidos por el equipo

La propuesta fija los estados de la reserva. Los demás se definieron así (`01_creacion.sql`):

| Tabla | Valores |
|---|---|
| Alquiler (estado) | ACTIVO, CERRADO |
| Pago (estado) | PENDIENTE, APROBADO, RECHAZADO, ANULADO |
| Pago (tipo) | EFECTIVO, TARJETA, TRANSFERENCIA, PRUEBA |
| Cargo adicional (concepto) | RETRASO, COMBUSTIBLE, DANO, LIMPIEZA, KILOMETRAJE, OTRO |
| Mantenimiento (estado) | PROGRAMADO, EN_CURSO, FINALIZADO, CANCELADO |
| Vehículo (estado operativo) | DISPONIBLE, RESERVADO, ENTREGADO, MANTENIMIENTO, INACTIVO |

### Personas y acceso

- Un cliente puede registrarse en mostrador sin tener cuenta en la aplicación; la relación con usuario es opcional (1:1).
- Un usuario puede tener varios perfiles a la vez; por ejemplo, el administrador también es operador.
- La aplicación se conecta con un usuario de base de datos de mínimo privilegio y solo modifica reservas, alquileres y pagos a través de los procedimientos `sp_` (`07_seguridad.sql`).
