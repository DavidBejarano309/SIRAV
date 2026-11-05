# Base de datos

## PostgreSQL

Los scripts se ejecutan en orden numérico. Todos se pueden volver a ejecutar: `01_creacion.sql` elimina y recrea el esquema `sirav`.

| Script | Contenido | Historia |
|---|---|---|
| `postgres/01_creacion.sql` | Esquema: 13 tablas, llaves, CHECK, índices `ix_` y restricción de exclusión (RN-01) | SIRAV-16 |
| `postgres/02_insercion.sql` | Datos de prueba: 25 vehículos, 12 clientes, 8 usuarios e historial | SIRAV-17 |
| `postgres/03_funciones.sql` | `fn_vehiculo_disponible`, `fn_calcular_costo`, `fn_calcular_cargo_retraso`, `fn_obtener_tarifa_vigente` y el catálogo de excepciones | SIRAV-19 |
| `postgres/04_procedimientos.sql` | `sp_crear_reserva`, `sp_confirmar_reserva`, `sp_cancelar_reserva`, `sp_iniciar_alquiler`, `sp_cerrar_alquiler` | SIRAV-20, SIRAV-24 |
| `postgres/05_triggers.sql` | Transición de estado, mantenimiento, auditoría y estado del vehículo | SIRAV-21 |
| `postgres/06_reportes.sql` | Reportes R1 a R6 | SIRAV-22 |
| `postgres/07_seguridad.sql` | Roles `sirav_admin`, `sirav_app`, `sirav_reportes` y sus privilegios | SIRAV-32 |

### Ejecutar todo

```bash
cd db/postgres
sudo -u postgres ./ejecutar_todo.sh                 # crea la base, ejecuta los scripts y las pruebas
sudo -u postgres ./ejecutar_todo.sh --sin-pruebas
# Contraseñas propias para los usuarios de la base (recomendado en la VM):
sudo -u postgres PWD_ADMIN='...' PWD_APP='...' PWD_REPORTES='...' ./ejecutar_todo.sh
```

Las pruebas de `postgres/pruebas/` revierten sus cambios. La evidencia de cada historia está en `docs/fase-2/evidencias/`.

### Excepciones para la aplicación

Los `sp_`, `fn_` y triggers lanzan errores con SQLSTATE de la clase `SR`, y cada mensaje empieza por el nombre de la excepción:

| SQLSTATE | Excepción | Regla |
|---|---|---|
| SR001 | `e_reserva_solapada` | RN-01 |
| SR002 | `e_mantenimiento_solapado` | RN-02 |
| SR003 | `e_transicion_invalida` | RN-03 |
| SR004 | `e_cierre_invalido` | RN-05 |
| SR005 | `e_vehiculo_no_disponible` | vehículo inactivo o ya ocupado |
| SR006 | `e_tarifa_no_vigente` | RN-04 |
| SR007 | `e_parametro_invalido` | datos de entrada |
| SR008 | `e_registro_no_encontrado` | id inexistente |

En Spring Boot el código llega en `SQLException.getSQLState()`.

### Conexión desde la aplicación

- Usuario: `sirav_app_user` (rol `sirav_app`). Puede ejecutar los `sp_` y `fn_` y consultar tablas, pero no modificar directamente reservas, alquileres, pagos, cargos ni la auditoría.
- Para que la auditoría registre quién hizo cada operación, cada `sp_` recibe el `id_usuario` de la sesión web.
- Usuarios de prueba de la aplicación: `admin@sirav.test`, `operador1@sirav.test`, `ana.perez@correo.test`, etc. Contraseña: `Sirav2026*`.

## MongoDB

Ver `mongo/README.md`.
