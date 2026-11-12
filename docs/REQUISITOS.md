# Funciones de los siete módulos

| Función | Backend | Frontend |
| --- | --- | --- |
| Registro, login, JWT y logout | security | Auth / App |
| Roles y pertenencia de reservas | SecurityConfig / Access | Navegación por rol |
| Catálogo, disponibilidad y cotización | CatalogController / fn_vehiculo_disponible | Catalog |
| Clientes con y sin cuenta | AuthService / v_cliente_contacto | Auth / Management |
| Vehículos, categorías y tarifas | CatalogController | Catalog / Management |
| Reserva, confirmación y cancelación | RentalService / procedimientos | Operations |
| Entrega, devolución y pago simulado | Procedimientos PL/pgSQL | Operations |
| Inspecciones y CRUD documental | InspectionController | InspectionFields / Inspections |
| Mantenimiento | CatalogController / trigger | Management |
| Historial de reserva | Auditoria_Reserva | Detalle de reserva |
| Seis reportes SQL complejos | report y archivos SQL | Reports |
| Consulta compleja y tres agregaciones MongoDB | inspection | Inspections / Reports |

Se mantienen 13 entidades de dominio, relaciones 1:1, 1:N y N:M, la lógica transaccional en la base, manejo de excepciones, permisos y pruebas de concurrencia.

Se incorporan cuentas/roles múltiples, perfil, contraseña, bitácora de seguridad, carga de evidencias, edición de mantenimiento y vista de cobros. El alcance completo de los 101 supuestos está en [SUPUESTOS-CUMPLIMIENTO.md](SUPUESTOS-CUMPLIMIENTO.md). No se necesitan dashboard, edición genérica de clientes ni exportación CSV. Se preservan despliegue Compose, scripts Linux y pruebas. Crear la VM, grabar el video y documentar participación real siguen siendo actividades del equipo.
