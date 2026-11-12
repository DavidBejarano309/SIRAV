# Análisis de selección de sistema operativo y RDBMS — SIRAV

Historia de Jira: **SIRAV-14**. Datos consultados el 11 de noviembre de 2026 en las fuentes oficiales listadas al final.

**Decisión:** **Ubuntu Server 24.04 LTS** con **PostgreSQL** y **MongoDB 8.0**, desplegados en tres máquinas virtuales. Ubuntu obtiene 4,85 sobre 5, frente a 4,40 de Rocky Linux y 4,05 de Debian. PostgreSQL obtiene 5,00, frente a 3,40 de MariaDB y 2,80 de MySQL. Se confirma la hipótesis de la propuesta (sección 6.7), con una precisión: **Ubuntu 24.04 y no 26.04**, porque MongoDB 8.x no soporta Ubuntu 26.04.

**Versiones desplegadas:** las imágenes oficiales `postgres:17.6-alpine` y `mongo:8.0.5`, fijadas en `compose.yaml`. La comparación de motores se hizo con PostgreSQL 16, la versión que trae Ubuntu 24.04. Los criterios no cambian en la 17: exclusión GiST, PL/pgSQL y `SECURITY DEFINER` funcionan igual. Los scripts se probaron en ambas versiones: 16 en local y 17.6 en la integración continua.

Escala de 1 (no cumple) a 5 (cumple totalmente). Los pesos suman 100 y el puntaje final es el promedio ponderado.

## 1. Sistema operativo

| Criterio | Peso | Ubuntu Server 24.04 LTS | Debian 13 | Rocky Linux 10 |
|---|---|---|---|---|
| Soporte oficial de MongoDB | 25 | **5** · MongoDB 7.x, 8.x y 9.x | **3** · solo MongoDB 9.x | **5** · MongoDB 7.x, 8.x y 9.x |
| Paquetes de PostgreSQL | 15 | **5** · repositorio oficial PGDG y PostgreSQL 16 incluido | **5** · repositorio oficial PGDG | **5** · repositorio oficial PGDG |
| Soporte durante el proyecto y después | 15 | **5** · hasta mayo de 2029 | **5** · seguridad hasta agosto de 2028 | **5** · activo hasta mayo de 2030 |
| Documentación y comunidad (systemd, Spring Boot, MongoDB) | 15 | **5** | **4** | **3** |
| Consumo de recursos en la VM (perfil mínimo de 4 GB) | 15 | **4** | **5** | **4** |
| Experiencia del equipo | 15 | **5** · usado en Sistemas Operacionales | **3** | **4** · experiencia con Red Hat |
| **Puntaje ponderado** | **100** | **4,85** | **4,05** | **4,40** |

- **Por qué gana Ubuntu.** Es el único que suma soporte oficial de MongoDB 8.x, documentación abundante para el stack (PostgreSQL, MongoDB, Java y systemd) y experiencia previa del equipo.
- **Debian 13** es más liviano, pero MongoDB solo lo soporta desde la serie 9.x, que es muy reciente.
- **Rocky Linux 10** tiene el soporte más largo y MongoDB lo soporta bien, pero agrega SELinux y firewalld a la configuración, y hay menos guías del stack completo.

### ¿Ubuntu 24.04 o 26.04?

| | Ubuntu 24.04 LTS | Ubuntu 26.04 LTS |
|---|---|---|
| MongoDB | 8.x y 9.x | Solo 9.0.4 o superior (soporte agregado el 14 oct 2026) |
| PostgreSQL incluido | 16 | 18 |
| Fin del soporte estándar | Mayo 2029 | Mayo 2031 |

Se elige **24.04** porque soporta la serie estable de MongoDB 8.x y el ciclo de soporte cubre de sobra el proyecto. **Si la VM ya se instaló con 26.04**, no hay que reinstalarla: basta con usar **MongoDB 9.0.4 o superior**. Con Docker, además, la imagen de MongoDB trae sus propias bibliotecas, así que lo que debe soportar el sistema anfitrión es Docker Engine, no MongoDB. `database/mongo/init.js` y la aplicación usan solo funciones disponibles en 7.x, 8.x y 9.x.

## 2. Motor relacional

| Criterio | Peso | PostgreSQL 16 | MySQL 8.4 LTS | MariaDB 11.8 LTS |
|---|---|---|---|---|
| Regla RN-01 declarativa y condicional (sin solapamientos solo para reservas vigentes) | 30 | **5** · `EXCLUDE USING gist` con `daterange`, `btree_gist` y `WHERE` | **1** · no tiene restricción de solapamiento; requiere triggers y bloqueos | **3** · tiene `WITHOUT OVERLAPS` sobre periodos, pero solo en índices únicos sin condición, así que las reservas canceladas también bloquearían |
| Procedimientos, funciones, excepciones y transacciones | 20 | **5** · PL/pgSQL, `RAISE` con SQLSTATE propio, bloques de excepción | **3** · SQL/PSM con `SIGNAL` y manejadores, menos expresivo | **3** · igual que MySQL |
| Integridad: CHECK, tipos de rango, DDL transaccional | 15 | **5** · todo, incluido DDL que se puede revertir | **3** · CHECK sí; sin tipos de rango; el DDL hace COMMIT implícito | **3** · CHECK sí; sin tipos de rango; DDL con COMMIT implícito |
| SQL para reportes R1 a R6 (ventanas, CTE, `generate_series`) | 10 | **5** | **4** · sin `generate_series` | **4** · usa el motor `SEQUENCE` en su lugar |
| Seguridad: roles, privilegios por columna, `SECURITY DEFINER` | 10 | **5** · además seguridad por filas | **4** | **4** |
| Licencia, soporte y paquetes | 10 | **5** · licencia libre tipo BSD; soporte hasta noviembre de 2028 | **4** · GPL o comercial (Oracle); soporte premier hasta abril de 2029 | **4** · GPL; mantenimiento hasta 2028 |
| Integración con Spring Boot (JDBC, `SimpleJdbcCall`) | 5 | **5** | **5** | **5** |
| **Puntaje ponderado** | **100** | **5,00** | **2,80** | **3,40** |

- **El criterio decisivo es RN-01.** PostgreSQL es el único que expresa "un vehículo no puede tener dos reservas *vigentes* solapadas" como una sola restricción declarativa. Así la regla se cumple aunque dos usuarios reserven al mismo tiempo, que es la justificación central de la propuesta (sección 1.3). En MySQL habría que programarla con triggers y bloqueos. En MariaDB el `WITHOUT OVERLAPS` no permite excluir las reservas canceladas o cerradas.
- **Versión.** La aplicación usa PostgreSQL 17.6 en contenedor (soporte hasta noviembre de 2029). Los scripts de `database/postgres/` también funcionan en el PostgreSQL 16 de Ubuntu 24.04 si se instala sin Docker.

## 3. Resultado

| Componente | Elección | Dónde corre |
|---|---|---|
| Sistema operativo | Ubuntu Server 24.04 LTS (imagen *cloud* oficial, sin escritorio) | Tres VM de VirtualBox de 2 GB y 2 CPU cada una |
| RDBMS | PostgreSQL 17.6 con `btree_gist` (imagen `postgres:17.6-alpine`) | VM SIRAV-PostgreSQL (192.168.56.21) |
| Base documental | MongoDB 8.0.5 Community (imagen `mongo:8.0.5`) | VM SIRAV-MongoDB (192.168.56.22) |
| Aplicación | Nginx con React compilado y la API Spring Boot (Java 21) como servicio systemd | VM SIRAV-Web (192.168.56.23) |
| Contenedores | Docker Engine, instalado por cloud-init en las VM de las bases | Las dos VM de bases |

**Por qué tres VM de 2 GB y no una de 6 GB.** El equipo no tenía memoria para una sola VM grande (riesgo R2). Separar los motores además deja ver la arquitectura real, con la API conectada a dos servidores de bases por red, y permite apagar o respaldar cada componente por separado. Uso medido: 375 MB en PostgreSQL, 459 MB en MongoDB y 567 MB en la VM web.

**Por qué los motores van en contenedores dentro de las VM.** Fija las versiones exactas (17.6 y 8.0.5) y reutiliza los mismos inicializadores del repositorio (`init.sh`, `init.js`). La VM sigue siendo el servidor Linux exigido; el contenedor solo empaqueta el motor.

**Alternativa.** Todo el sistema puede correr con Docker Compose en una sola VM Ubuntu de 4 a 6 GB (`compose.yaml` y `compose.vm.yaml`), verificado en la integración continua. Ver `guia-instalacion.md`, parte B.

## Fuentes

- MongoDB, [plataformas soportadas](https://www.mongodb.com/docs/enterprise-platform-support/) (Ubuntu 26.04 solo en 9.x; Debian 13 solo en 9.x; RHEL/Rocky 10 en 7.x, 8.x y 9.x).
- MongoDB, [notas de la versión 9.0](https://www.mongodb.com/docs/v9.0/release-notes/9.0/) y [anuncio de 9.0.4](https://www.mongodb.com/community/forums/t/mongodb-9-0-4-is-released/344302) (SERVER-131625: soporte para Ubuntu 26.04).
- Canonical, [ciclo de lanzamientos de Ubuntu](https://ubuntu.com/about/release-cycle).
- endoflife.date: [Debian](https://endoflife.date/debian), [Rocky Linux](https://endoflife.date/rocky-linux) y [MySQL](https://endoflife.date/mysql).
- Docker, [instalación de Docker Engine en Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
- PostgreSQL, [política de versiones](https://www.postgresql.org/support/versioning) y [paquetes para Ubuntu](https://www.postgresql.org/download/linux/ubuntu/).
- MariaDB, [versiones mantenidas en 2026](https://mariadb.org/?p=41784) y [periodos de aplicación con WITHOUT OVERLAPS](https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/application-time-periods).
- MySQL, [sentencias con COMMIT implícito](https://dev.mysql.com/doc/en/implicit-commit.html).
