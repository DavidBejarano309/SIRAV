# MongoDB

Colecciones `inspecciones_vehiculo` y `bitacora_operaciones` de la base `sirav`. El diseño, los patrones y los ejemplos JSON están en [MODELO_DOCUMENTAL.md](MODELO_DOCUMENTAL.md).

| Archivo | Contenido | Historia |
|---|---|---|
| `MODELO_DOCUMENTAL.md` | Modelo documental, justificación de NoSQL y patrones del capítulo 13 | SIRAV-23 |
| `00_comun.js` | Constantes, fechas en hora de Bogotá y cálculo del resumen (patrón Computed) | SIRAV-25 |
| `01_colecciones.js` | Colecciones con validación `$jsonSchema`, índices y usuarios | SIRAV-25 |
| `02_crud.js` | Registrar, consultar, corregir y anular inspecciones; registrar eventos (patrón Bucket) | SIRAV-25 |
| `03_datos.js` | Datos de ejemplo enlazados con los alquileres de `db/postgres/02_insercion.sql` | SIRAV-25 |
| `pruebas/01_pruebas_crud.js` | Validación, índices, CRUD, Computed, Bucket y consultas de SIRAV-26 (en una base aparte) | SIRAV-25 |
| `pruebas/02_pruebas_permisos.js` | Mínimo privilegio de los usuarios (requiere autorización activada) | SIRAV-25 |
| `ejecutar_todo.sh` | Crea todo y ejecuta las pruebas | — |

## Ejecutar

```bash
cd db/mongo
SIRAV_MONGO_ADMIN_URI='mongodb://admin:<clave>@localhost:27017/admin' ./ejecutar_todo.sh
# Contraseñas propias para los usuarios de la base (recomendado en la VM):
SIRAV_MONGO_APP_PWD='...' SIRAV_MONGO_REPORTES_PWD='...' SIRAV_MONGO_ADMIN_URI='...' ./ejecutar_todo.sh
```

Requiere `mongosh` y un usuario administrador. La prueba de permisos supone `security.authorization: enabled` en `/etc/mongod.conf`.

## Conexión desde la aplicación

- Usuario `sirav_app_mongo` (base de autenticación `sirav`): consulta, inserta y actualiza; no puede borrar. Las inspecciones se anulan, no se borran.
- Al devolver un vehículo: guardar la inspección de DEVOLUCION, tomar su `_id` y `resumen.monto_danos_estimado`, y pasarlos a `sp_cerrar_alquiler` en PostgreSQL (RN-05).
- Los errores de `02_crud.js` empiezan por el nombre de la excepción: `e_entrega_no_registrada`, `e_parametro_invalido`, `e_registro_no_encontrado`, `e_inspeccion_anulada`, `e_anulacion_invalida`.
