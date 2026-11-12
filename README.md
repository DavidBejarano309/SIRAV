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

El contrato REST está en http://localhost:8080/swagger-ui.html cuando el backend se ejecuta localmente (en Docker el puerto 8080 no se publica). Las consultas SQL están en `backend/src/main/resources/sql/reports/`.

## Pruebas

```powershell
./scripts/test-local.ps1 -Maven RUTA-A-MVN
cd frontend
npm run test:e2e
```

Las pruebas de backend usan `sirav_3fn_test`; las de navegador requieren la aplicación iniciada y generan datos de demostración. Las pruebas unitarias se ejecutan con `mvn -f backend/pom.xml test` y `npm --prefix frontend test`.

## Documentación de la entrega final

| Fase | Documento |
|---|---|
| Fase 1 | [Propuesta v1.2](docs/fase-1/SIRAV_Propuesta.docx) · [Supuestos](docs/fase-1/supuestos.md) · [Requerimientos y trazabilidad](docs/fase-1/requerimientos.md) · [Matriz de riesgos](docs/fase-1/matriz-riesgos.md) · [Diccionario de datos y 3FN](docs/fase-1/diccionario-datos.md) · [Reportes SQL R1–R6](docs/fase-1/reportes-sql.md) |
| Modelado | [Diagramas](docs/diagramas/): Chen, EER, Crow's Foot lógico y relacional, arquitectura, estados y modelo documental (fuentes `.dot`/`.mmd` en `docs/diagramas/fuentes/`) |
| Gestión | [Metodología, Gantt, RACI y seguimiento](docs/gestion/README.md) |
| Fase 2 | [Selección de SO y RDBMS](docs/fase-2/seleccion-so-rdbms.md) · [Guía de instalación, puertos, arranque y respaldos](docs/fase-2/guia-instalacion.md) · [Modelo documental MongoDB](docs/fase-2/modelo-documental-mongodb.md) · [Pruebas](docs/fase-2/pruebas.md) |
| Cierre | [Informe ejecutivo](docs/cierre/SIRAV_Informe_Ejecutivo.pdf) · [Guion del video](docs/cierre/guion-video.md) |
| Aplicación | [Arquitectura](docs/ARQUITECTURA.md) · [Manual de uso](docs/MANUAL.md) · [Cambios 3FN](docs/CAMBIOS-3FN.md) · [Funciones conservadas](docs/REQUISITOS.md) |

**Despliegue en la VM:** `bash scripts/configure.sh` y `docker compose -f compose.yaml -f compose.vm.yaml up --build -d`; verificación con `bash scripts/verificar-despliegue.sh` (ver la guía).
