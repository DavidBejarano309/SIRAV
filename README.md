# SIRAV 3FN — siete módulos

Prototipo académico con **Java 21 / Spring Boot, React, PostgreSQL y MongoDB**, adaptado al esquema 3FN y a los 101 supuestos funcionales de `Supuestos_SIRAV.docx`. Los importes son simulaciones en COP y los datos son ficticios.

## Qué cambió

- Se conserva íntegro el esquema de 13 entidades en `database/postgres/01-schema.sql`.
- Un cliente con cuenta obtiene nombre y correo desde `USUARIO`; esos campos quedan NULL en `CLIENTE`.
- Un cliente sin cuenta conserva su identidad en `CLIENTE`.
- Las reservas, las listas de clientes y los reportes leen `v_cliente_contacto`.
- Se incluyen administración básica de cuentas y roles múltiples, perfil y cambio de contraseña.
- La carga inicial tiene 25 vehículos y 5 categorías en una sede. La carga demo agrega historial puntual, tardío y cancelado sin sobrescribir operaciones existentes.
- Se adjuntan y descargan imágenes PNG/JPEG protegidas. MongoDB conserva referencias; los archivos viven fuera de las bases.
- Se protegen tarifas históricas, reintentos de liquidación y eventos pendientes de MongoDB.
- Se comparte el formulario de inspección entre entrega, devolución y corrección. Los estilos y la navegación son más pequeños.

| Módulo | Funciones principales |
| --- | --- |
| Usuarios y perfiles | Registro cliente, JWT, roles N:M, alta administrativa, desactivación, perfil y cambio local de contraseña |
| Catálogo | Flota, categorías, tarifas vigentes, disponibilidad y cotización |
| Reservas | Solicitud, confirmación por personal, cancelación con motivo, historial y clientes de mostrador |
| Alquileres e inspecciones | Entrega/devolución manual, daños, imágenes, versiones y anulación lógica |
| Mantenimiento | Programar, editar fechas/motivo, completar/cancelar y bloquear conflictos |
| Cobros simulados | Base, 50% diario por retraso, cargos y pago simulado al cerrar |
| Historial y reportes | Auditoría SQL, bitácora MongoDB, seis reportes SQL y tres agregaciones |

Los permisos se comprueban en backend. CLIENTE consulta solo sus operaciones. ADMIN gestiona cuentas, catálogo y tarifas; ADMIN/OPERADOR gestionan la operación. Mi perfil está en el encabezado.

## Arranque con Docker

Requiere Docker con Compose v2. Desde la raíz:

```powershell
./scripts/configure.ps1
docker compose up --build -d
```

En Linux usa `bash scripts/configure.sh` para preparar `.env`. Abre http://localhost:8088 cuando el backend indique que inició. La configuración usa un proyecto Compose y volúmenes nuevos: **no reutiliza los datos de la versión anterior**.

Si ya existe una instalación 3FN, aplica la ampliación sin recrear sus datos antes de actualizar:

```sh
docker compose exec -T postgres psql -U sirav_owner -d sirav_3fn -v ON_ERROR_STOP=1 --single-transaction -f /schema/06-supuestos.sql
docker compose exec -T postgres psql -U sirav_owner -d sirav_3fn -v ON_ERROR_STOP=1 --single-transaction -f /schema/07-concurrency-validation.sql
docker compose exec -T mongo sh -c 'mongosh --username root --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin /docker-entrypoint-initdb.d/init.js'
docker compose up --build -d
```

Las imágenes usan el volumen persistente `evidence_data`. `backup.sh` incluye PostgreSQL, MongoDB y archivos; respalda sin operaciones concurrentes y comprueba restauración en ensayo.

## Arranque local en este equipo Windows

```powershell
./scripts/start-local.ps1
```

Abre http://localhost:5173. El script utiliza PostgreSQL instalado en Windows, puerto 55432, y MongoDB en el puerto 57017. Necesita las dependencias locales ya instaladas y el JAR compilado. Si vas a recompilar, ejecuta `mvn -f backend/pom.xml clean verify`. Para otra instalación se recomienda Compose.

La base se llama **sirav_3fn** en ambos motores. El inicializador instala tablas si está vacía y aplica `06-supuestos.sql` a una instalación 3FN existente. La base anterior **sirav** se conserva. El esquema suministrado no migra datos del modelo antiguo.

Después de recompilar usa `./scripts/start-local.ps1 -RestartApi` para reiniciar únicamente la API de este proyecto y cargar el JAR nuevo.

## Usuarios de demostración

| Rol | Correo | Contraseña inicial |
| --- | --- | --- |
| Administrador | admin@sirav.local | SiravDemo2026! |
| Operador | operador@sirav.local | SiravDemo2026! |
| Cliente | cliente@sirav.local | SiravDemo2026! |

Se crean con `SEED_DEMO=true`; la contraseña proviene de `DEMO_PASSWORD`. El registro público solo crea clientes. ADMIN asigna roles y desactiva cuentas sin eliminar historial. Las modificaciones de permisos y el cambio de contraseña revocan sesiones. Los secretos técnicos están en `.env`, ignorado por Git.

## Organización del código

```text
backend/src/main/java/co/edu/sirav/
  security/     registro, login, JWT, roles y cierre de sesión
  catalog/      flota, clientes, categorías, tarifas y mantenimiento
  rental/       operaciones que invocan procedimientos de PL/pgSQL
  inspection/   MongoDB y publicación de inspecciones pendientes
  report/       seis reportes SQL de solo lectura
  common/       errores y documentación OpenAPI
frontend/src/
  App.jsx               sesión y navegación
  components.jsx        formularios, tabla y ventana de diálogo
  InspectionFields.jsx  formulario de inspección compartido
  views/                pantallas de los siete módulos y perfil
database/               esquema, procedimientos y configuración MongoDB
```

Los procedimientos `sp_crear_reserva`, `sp_confirmar_reserva`, `sp_cancelar_reserva`, `sp_iniciar_alquiler` y `sp_cerrar_alquiler` concentran las operaciones transaccionales. Los scripts adicionales al esquema agregan reglas de negocio, índices y una tabla técnica outbox para sincronizar MongoDB sin perder inspecciones. Esa tabla no es una nueva entidad de dominio.

Se utiliza **PL/pgSQL de PostgreSQL**. `sp_cargar_historial_demo` es auxiliar y se invoca con `SEED_DEMO=true`. Se usan intervalos [inicio,fin), COP con dos decimales y días calendario de Bogotá. Las reservas se reprograman mediante cancelación y nueva solicitud.

El contrato REST está en http://localhost:8080/swagger-ui.html. Las consultas SQL están en `backend/src/main/resources/sql/reports/`.

## Pruebas

```powershell
./scripts/test-local.ps1 -Maven RUTA-A-MVN
cd frontend
npm run test:e2e
```

Las pruebas de backend usan `sirav_3fn_test`; las de navegador requieren la aplicación iniciada y generan datos de demostración. Las pruebas unitarias se ejecutan con `mvn -f backend/pom.xml test` y `npm --prefix frontend test`.

## Documentación vigente

- [Política de respaldos, retención y recuperación de ambas bases y evidencias](docs/POLITICA-RESPALDOS.md)
- [Auditoría SQL, PL/pgSQL, MongoDB y concurrencia: resultados y correcciones](docs/AUDITORIA-FUNCIONAL-VM.md)
- [Aplicación completa en tres VM y acceso desde otros equipos](docs/WEB-EN-VIRTUALBOX.md)
- [Dos servidores de 2 GB en VirtualBox: PostgreSQL y MongoDB](docs/DOS-SERVIDORES-VIRTUALBOX.md)
- [Cambios y compatibilidad 3FN](docs/CAMBIOS-3FN.md)
- [Arquitectura](docs/ARQUITECTURA.md)
- [Diccionario de datos](docs/DICCIONARIO.md)
- [Modelo de datos](docs/MODELOS.md)
- [Manual de uso](docs/MANUAL.md)
- [Pruebas](docs/PRUEBAS.md)
- [Requisitos conservados](docs/REQUISITOS.md)
- [Matriz de los 101 supuestos funcionales](docs/SUPUESTOS-CUMPLIMIENTO.md)

El paquete vigente es `SIRAV-3FN-supuestos.zip`. Se conservan los anteriores. La VM Linux, su dimensionamiento, el video, los respaldos restaurados, el historial Git y la participación del equipo requieren evidencias reales de los estudiantes; esta implementación no las acredita.
