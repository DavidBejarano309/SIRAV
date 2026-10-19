\# Documento de supuestos — SIRAV



\## Del negocio

\- Una sola sede y una flota de prueba de 20 a 30 vehículos en 4 o 5 categorías.

\- Cada reserva corresponde a un cliente y a un vehículo.

\- Los precios, pagos y cargos son valores de demostración en pesos colombianos; no hay pasarela de pago.

\- Las fotografías de inspección se referencian por nombre de archivo; no se almacenan en la base.

\- Existen tres perfiles de usuario: administrador, operador y cliente.



\## Técnicos

\- PostgreSQL es la fuente única de verdad para reservas, alquileres y pagos de prueba.

\- MongoDB guarda inspecciones y bitácora de eventos, enlazadas por el identificador del alquiler.

\- La aplicación y las dos bases de datos se ejecutan en una máquina virtual Ubuntu Server.

\- Se dispone de un equipo anfitrión con recursos suficientes para la VM (recomendado: 6 GB de RAM, 2 núcleos y 40 GB de disco).

\- Todo el software usado es gratuito o de código abierto.



\## De gestión

\- El equipo lo forman dos integrantes y el plazo es de cuatro semanas.

\- El trabajo se organiza en cuatro sprints semanales en Jira.

\- El alcance queda congelado con la propuesta; lo adicional pasa a ampliaciones futuras.

