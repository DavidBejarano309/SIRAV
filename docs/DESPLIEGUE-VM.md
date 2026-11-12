# Despliegue en una máquina virtual Linux

Para la instalación con **dos servidores de 2 GB de RAM cada uno**, PostgreSQL y MongoDB separados y la aplicación en Windows, consulta [Dos servidores en VirtualBox](DOS-SERVIDORES-VIRTUALBOX.md). Los recursos de la guía siguiente corresponden a alojar todo el conjunto en una sola VM.

El requisito académico pide una VM Linux o Unix implementada. Los contenedores no sustituyen esa evidencia: ejecútalos dentro de una VM Ubuntu Server y conserva capturas de la máquina, la red, los servicios y el acceso web.

## Selección de sistema operativo

Escala de 1 a 5, ponderación: soporte 30%, documentación 25%, facilidad operativa 25%, consumo 20%. Es una evaluación de diseño, no una medición experimental.

| Sistema | Soporte | Documentación | Operación | Consumo | Total ponderado |
| --- | --- | --- | --- | --- | --- |
| Ubuntu Server 24.04 LTS | 5 | 5 | 5 | 4 | 4.80 |
| Debian 12 | 5 | 4 | 4 | 5 | 4.50 |
| Rocky Linux 9 | 5 | 4 | 3 | 4 | 4.05 |

Se propone Ubuntu Server 24.04 LTS por su documentación y facilidad de instalación del conjunto. Verifica disponibilidad y soporte de las imágenes oficiales al crear la VM.

## Selección del motor relacional

Oracle queda excluido por el documento oficial. Se valoran: prevención de cruces 35%, lenguaje procedural 25%, licencia académica 20%, integración Java 20%.

| Motor permitido | Cruces de intervalos | Lógica procedural | Licencia | Java | Total |
| --- | --- | --- | --- | --- | --- |
| PostgreSQL | 5 | 5 | 5 | 5 | 5.00 |
| MariaDB | 3 | 4 | 5 | 5 | 4.05 |
| MySQL | 3 | 4 | 4 | 5 | 3.85 |
| SQL Server | 3 | 5 | 3 | 5 | 3.90 |

PostgreSQL permite una restricción de exclusión sobre `daterange`, además de procedimientos, triggers y funciones. En otros motores el control necesitaría otra estrategia de bloqueo. Las puntuaciones justifican la selección; no afirman que los otros motores sean incapaces de implementar las reglas.

## Crear la VM

1. En VirtualBox, VMware o el hipervisor disponible, crea una VM Ubuntu Server con 2 vCPU, 4 GB RAM como mínimo (6 GB recomendado) y 40 GB de disco.
2. Instala desde una ISO oficial y habilita SSH si vas a administrar remotamente.
3. Usa red puente o NAT. Con NAT reenvía el puerto del anfitrión 8088 al puerto 8088 del invitado, además de SSH si lo necesitas.
4. Captura el nombre del sistema, recursos asignados, IP y fecha. No incluyas claves privadas ni `.env` en las capturas.
5. Instala Docker Engine y el plugin Compose siguiendo la [documentación oficial para Ubuntu](https://docs.docker.com/engine/install/ubuntu/). No ejecutes scripts de instalación de procedencia desconocida.

## Instalar SIRAV

```bash
git clone <URL-REAL-DEL-REPOSITORIO> sirav
cd sirav
bash scripts/configure.sh
docker compose up --build -d
docker compose ps
docker compose logs --tail 100 backend
```

La configuración predeterminada publica la web solo en `127.0.0.1:8088`. Para acceder desde el anfitrión a la VM crea `compose.vm.yaml` con:

```yaml
services:
  frontend:
    ports: !override
      - "8088:80"
```

Ejecuta `docker compose -f compose.yaml -f compose.vm.yaml up --build -d`. `!override` requiere Compose 2.24.4 o superior. También puedes modificar el único mapeo existente de `compose.yaml` a `8088:80` para una instalación con una versión anterior de Compose. Limita el acceso con el firewall a la red o IP del equipo de demostración.

Añade `CORS_ORIGIN=http://IP-DE-LA-VM:8088` a `.env` antes de iniciar el backend y visita esa misma dirección. Las peticiones API usan Nginx; no necesitan abrir el puerto 8080 ni los de las bases. Los healthchecks comprueban la disponibilidad de las bases antes de iniciar el backend. Los contenedores se reinician con `unless-stopped` cuando Docker arranca; habilita el servicio Docker del invitado.

## Respaldo y recuperación

```bash
bash scripts/backup.sh
```

El script genera `backups/FECHA/postgres.dump` y `mongodb.archive.gz`. Cópialos fuera del disco de la VM. Para recuperar en servicios recién inicializados compatibles:

```bash
docker compose exec -T postgres pg_restore -U sirav_owner -d sirav --clean --if-exists < backups/FECHA/postgres.dump
docker compose exec -T mongo sh -c 'mongorestore --username root --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --drop' < backups/FECHA/mongodb.archive.gz
```

Ejecuta restauraciones sobre un entorno detenido para escrituras, conservando un respaldo previo. Verifica flota, reservas, pagos y contador de eventos pendientes después de restaurar. Las copias de ambos motores tomadas en instantes distintos pueden requerir que el publicador vuelva a proyectar eventos; realiza las copias durante una ventana sin operaciones para la demostración.

## Evidencias de entrega

- Pantalla del hipervisor con nombre y recursos de la VM.
- `cat /etc/os-release`, `ip address`, `docker version` y `docker compose ps` dentro del invitado.
- Navegador del anfitrión abierto en la IP de la VM.
- Una reserva rechazada por cruce, un cierre con pago simulado y las dos inspecciones consultadas.
- Logs del backend y consulta a ambas bases sin credenciales en pantalla.
- Respaldo generado y una restauración probada en otra instancia de ensayo.

No se presenta esta guía como prueba de que la VM ya exista. Esa evidencia debe capturarse cuando el equipo la implemente.
