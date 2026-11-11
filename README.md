# SIRAV 3FN sencillo

Versión simplificada con **Java 21 / Spring Boot, React, PostgreSQL y MongoDB**, adaptada a `01-schema-SIRAV-revisado-3FN.sql` del usuario.

## Qué cambió

- Se conserva íntegro el esquema de 13 entidades en `database/postgres/01-schema.sql`.
- Un cliente con cuenta obtiene nombre y correo desde `USUARIO`; esos campos quedan NULL en `CLIENTE`.
- Un cliente sin cuenta conserva su identidad en `CLIENTE`.
- Las reservas, las listas de clientes y los reportes leen `v_cliente_contacto`.
- Se quitaron dashboard, interfaz de administración de usuarios, edición de perfil, edición de clientes y exportación CSV.
- Se comparte el formulario de inspección entre entrega, devolución y corrección. Los estilos y la navegación son más pequeños.

Se mantienen JWT y tres roles, vehículos, categorías, tarifas, creación de clientes, reservas, entrega, devolución, mantenimiento, pagos simulados, historial, CRUD de inspecciones y reportes SQL/MongoDB. La auditoría de reservas permanece en la base mediante triggers.

## Arranque con Docker

Requiere Docker con Compose v2. Desde la raíz:

```powershell
./scripts/configure.ps1
docker compose up --build -d
```

En Linux usa `bash scripts/configure.sh` para preparar `.env`. Abre http://localhost:8088 cuando el backend indique que inició. La configuración usa un proyecto Compose y volúmenes nuevos: **no reutiliza los datos de la versión anterior**.

## Arranque local en este equipo Windows

```powershell
./scripts/start-local.ps1
```

Abre http://localhost:5173. El script utiliza PostgreSQL instalado en Windows, puerto 55432, y MongoDB en el puerto 57017. Necesita las dependencias locales ya instaladas y el JAR compilado. Si vas a recompilar, ejecuta `mvn -f backend/pom.xml clean verify`. Para otra instalación se recomienda Compose.

La base de esta versión se llama **sirav_3fn** en ambos motores. El inicializador crea esa base y solo instala tablas si está vacía. La base anterior **sirav** se conserva. El archivo suministrado es un esquema de creación, no una migración automática de datos anteriores.

Después de recompilar usa `./scripts/start-local.ps1 -RestartApi` para reiniciar únicamente la API de este proyecto y cargar el JAR nuevo.

## Usuarios de demostración

| Rol | Correo | Contraseña inicial |
| --- | --- | --- |
| Administrador | admin@sirav.local | SiravDemo2026! |
| Operador | operador@sirav.local | SiravDemo2026! |
| Cliente | cliente@sirav.local | SiravDemo2026! |

Se crean con `SEED_DEMO=true`; la contraseña proviene de `DEMO_PASSWORD`. El registro público solo crea clientes. Los roles se mantienen fijos para simplificar esta versión. La clave JWT y las contraseñas técnicas se configuran en `.env`, ignorado por Git.

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
  views/                las seis vistas necesarias
database/               esquema, procedimientos y configuración MongoDB
```

Los procedimientos `sp_crear_reserva`, `sp_confirmar_reserva`, `sp_cancelar_reserva`, `sp_iniciar_alquiler` y `sp_cerrar_alquiler` concentran las operaciones transaccionales. Los scripts adicionales al esquema agregan reglas de negocio, índices y una tabla técnica outbox para sincronizar MongoDB sin perder inspecciones. Esa tabla no es una nueva entidad de dominio.

El contrato REST está en http://localhost:8080/swagger-ui.html. Las consultas SQL están en `backend/src/main/resources/sql/reports/`.

## Pruebas

```powershell
./scripts/test-local.ps1 -Maven RUTA-A-MVN
cd frontend
npm run test:e2e
```

Las pruebas de backend usan `sirav_3fn_test`; las de navegador requieren la aplicación iniciada y generan datos de demostración. Las pruebas unitarias se ejecutan con `mvn -f backend/pom.xml test` y `npm --prefix frontend test`.

## Documentación vigente

- [Cambios y compatibilidad 3FN](docs/CAMBIOS-3FN.md)
- [Arquitectura](docs/ARQUITECTURA.md)
- [Diccionario de datos](docs/DICCIONARIO.md)
- [Modelo de datos](docs/MODELOS.md)
- [Manual de uso](docs/MANUAL.md)
- [Pruebas](docs/PRUEBAS.md)
- [Requisitos conservados](docs/REQUISITOS.md)

El paquete `SIRAV-3FN-sencillo.zip` contiene los documentos vigentes. El ZIP e informe ejecutivo de octubre corresponden a la versión anterior. La VM Linux, el video y la participación del equipo siguen requiriendo evidencias reales de los estudiantes.
