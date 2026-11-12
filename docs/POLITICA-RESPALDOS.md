# Política de respaldo y recuperación de SIRAV

Versión 1.0 · 11 de noviembre de 2026 · Entorno académico en VirtualBox.

## Alcance y objetivos

Se respalda **sirav_3fn en PostgreSQL y MongoDB como un mismo conjunto**, junto con las imágenes de inspección. PostgreSQL contiene usuarios, permisos, catálogo, reservas, alquileres, pagos, auditoría y outbox; MongoDB contiene inspecciones y bitácora. Las imágenes están en `/opt/sirav/evidencias` de SIRAV-Web, fuera de las bases.

| Regla | Política |
| --- | --- |
| Responsable | Administrador del proyecto; designar un suplente |
| Frecuencia | Una copia completa cada día de uso, a las 22:00 de Bogotá o antes de apagar el equipo |
| Copia adicional | Antes de migraciones SQL, cambios de versión o demostraciones importantes |
| Pérdida admisible (RPO) | Objetivo: máximo 24 horas durante días de uso, condicionado a copias correctas |
| Recuperación (RTO) | Objetivo inicial: 2 horas con VM disponibles; medir en simulacro, aún no acreditado |
| Retención | Todos los conjuntos de los últimos 14 días; además el último de 14 días distintos, 8 semanas distintas y 6 meses distintos |
| Verificación | SHA-256 en cada copia; restauración aislada mensual y después de cambios del esquema |
| Ubicaciones | Copia de trabajo en las VM, respaldo en Windows y segunda copia en disco externo cifrado o almacenamiento externo protegido |

Las franjas de retención pueden compartir un conjunto; no se duplican los archivos. Los identificadores y agrupaciones de retención usan UTC, mientras el horario operativo es Bogotá. Una VM guardada o un snapshot en el mismo disco no sustituye este respaldo.

## Procedimiento para las tres VM

Ejecutar desde la raíz del proyecto con la misma cuenta Windows que creó las VM y tiene acceso a `.runtime/virtualbox/id_ed25519`. Las tres VM deben estar encendidas, inicializadas y con la API activa. El script **no enciende VM** ni cierra aplicaciones del equipo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/backup-vms.ps1
```

El procedimiento comprueba ambos motores antes de detener la API; detiene `sirav-api.service` para impedir que las operaciones y el publicador outbox cambien los datos mientras se copian las dos bases y los archivos. **No ejecutar otras API locales, auditorías, cambios de esquema ni escrituras directas durante esta ventana.** MongoDB es standalone: este procedimiento no usa `--oplog`. PostgreSQL ofrece consistencia propia por dump, pero esa propiedad no sincroniza por sí sola ambos motores y los archivos. Véanse [pg_dump de PostgreSQL 17](https://www.postgresql.org/docs/17/app-pgdump.html) y [mongodump de MongoDB](https://www.mongodb.com/docs/database-tools/mongodump/).

La web no permite operar durante la pausa. La copia debe terminar antes de 29 minutos; un temporizador de recuperación solicita el arranque de la API a los 30 minutos si Windows se interrumpe. El bloque de limpieza también solicita su arranque ante errores. En este equipo el arranque en frío de Java puede tardar aproximadamente 15 minutos adicionales: reservar una ventana de mantenimiento y comprobar la salud al finalizar. El temporizador es una protección de recuperación, no garantiza disponibilidad si la VM está apagada.

Cada carpeta `backups/FECHA-IDENTIFICADOR/` contiene:

| Archivo | Contenido |
| --- | --- |
| `postgres.dump` | Datos, tablas, secuencias, vistas, funciones PL/pgSQL, procedimientos, triggers, índices y permisos de la base |
| `postgres-roles.sql` | Roles PostgreSQL sin contraseñas; conservar para reconstruir un servidor vacío |
| `postgres-counts.tsv` | Número de filas por tabla pública al respaldar |
| `mongodb.archive.gz` | Documentos y metadatos de colecciones, incluidos índices; no incluye usuarios del motor |
| `mongodb-counts.json` | Número de documentos e índices por colección |
| `evidencias.tar.gz` | Imágenes de entrega y devolución |
| `manifest.json` | Identificador, tiempos UTC, motores, tamaño y SHA-256 de cada archivo |

Un conjunto sin manifiesto completo o con hashes incorrectos no es utilizable. Los errores no deben tomarse como un respaldo exitoso. Los archivos temporales se eliminan de las VM al finalizar; una copia fallida local se conserva para diagnóstico. La carpeta local tiene acceso restringido a la cuenta ejecutora y SYSTEM. **Esto no cifra los datos**: usar discos cifrados y controlar permisos del destino externo. Ni `.env` ni las claves SSH se incluyen; guardar los secretos y el acceso de recuperación por separado en un medio cifrado o gestor de contraseñas.

Ejemplo con un disco externo ya preparado y cifrado:

```powershell
./scripts/backup-vms.ps1 -MirrorDirectory 'E:\SIRAV-respaldos'
./scripts/manage-web-vm.ps1 -Action Check
```

Cambiar `E:` por la unidad real. El script vuelve a verificar la copia externa; no configura cifrado ni servicios de nube. Si falla el espejo, conservar la copia local y corregir el destino. No se considera cumplida la protección fuera del equipo hasta verificar esa segunda copia. OneDrive puede sincronizar la carpeta del proyecto: revisar permisos y cifrado antes de guardar datos reales allí.

## Restauración de ensayo

```powershell
./scripts/test-backup-vms.ps1 -BackupDirectory 'backups/IDENTIFICADOR' -IntegrityOnly
./scripts/test-backup-vms.ps1 -BackupDirectory 'backups/IDENTIFICADOR'
```

El primer comando solo comprueba manifiesto, tamaños y SHA-256, sin conectar a las VM. El segundo restaura en bases nuevas `sirav_restore_...` en los motores existentes, sin `--drop` ni modificación de `sirav_3fn`. Compara filas de todas las tablas y documentos e índices de todas las colecciones, y extrae las imágenes a una carpeta aislada en SIRAV-Web. Necesita espacio libre y las tres VM encendidas; los roles SQL originales deben existir en ese servidor. Guarda `restore-drill-.../result.json` con PASS y duración, o `failure.txt` si falla. Conserva las bases y archivos de ensayo para revisión: retirarlos manualmente después de documentar el resultado y verificar sus nombres.

Este ensayo comprueba que los archivos se pueden restaurar; completar cada simulacro con una API de prueba configurada contra las bases recuperadas: login, consulta de reserva y pago, inspección e imagen, seis reportes SQL y tres agregaciones MongoDB. No conectar usuarios reales a las bases de ensayo. Un hash correcto por sí solo no acredita recuperación funcional.

## Recuperación ante pérdida real

1. Detener escrituras y registrar el incidente, último respaldo válido y pérdida esperada. Conservar el estado averiado para análisis; no sobrescribirlo.
2. Verificar hashes y ejecutar primero el ensayo aislado. Usar **las dos bases y las imágenes del mismo identificador**.
3. Preparar servidores vacíos con PostgreSQL 17 y MongoDB 8 compatibles, espacio libre y conectividad. Recuperar proyecto y secretos desde sus medios separados.
4. En PostgreSQL, revisar y aplicar `postgres-roles.sql` en el servidor vacío, asignar contraseñas nuevas a `sirav_owner`/`sirav_app`, crear `sirav_3fn` propiedad de `sirav_owner` y restaurar con `pg_restore --exit-on-error --single-transaction -U sirav_owner -d sirav_3fn postgres.dump`. No aplicar una carga demo sobre lo recuperado.
5. En MongoDB, con usuario administrativo, restaurar `mongodb.archive.gz` con `mongorestore --archive=... --gzip --stopOnError --nsInclude='sirav_3fn.*'` sobre una base vacía. Recrear el usuario de aplicación con `readWrite` sobre `sirav_3fn`; no ejecutar inicializadores que reemplacen datos. Las credenciales se recuperan por separado.
6. Recuperar `evidencias/` en `/opt/sirav`, asignar acceso a `sirav:sirav`, configurar `/opt/sirav/application.env` con secretos protegidos y verificar direcciones entre VM. Reponer la aplicación compatible con el esquema respaldado.
7. Comparar inventarios, arrancar la API y probar salud, autenticación, reservas, cobros, imágenes y reportes. Revisar outbox pendiente: puede conservar eventos que deberán reintentarse. No habilitar operación hasta validar permisos y consistencia.
8. Registrar tiempos reales, responsable, diferencias y autorización de retorno al servicio; crear una copia nueva después de la recuperación.

## Retención, control y programación

```powershell
# Mostrar qué conservaría y qué retiraría; no elimina nada.
./scripts/backup-retention.ps1
# Aplicar después de revisar el listado y comprobar el espejo externo.
./scripts/backup-retention.ps1 -Prune
```

La limpieza solo considera carpetas con identificadores del script y seis archivos verificados. Conserva conjuntos inválidos o incompletos para revisión. No elimina datos de las VM ni aplica retención automáticamente al disco externo; revisar también ese destino según la misma política. Mantener al menos un respaldo con ensayo PASS antes de depurar copias históricas.

Para automatizar, crear una tarea del Programador de tareas de Windows a las 22:00, bajo **la cuenta propietaria de las VM**, con programa `powershell.exe`, directorio de inicio la raíz del proyecto y argumentos:

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\Users\Jose David\OneDrive\Documents\ChatGPT\ProyectoBaseDeDatos2\scripts\backup-vms.ps1"
```

Activar ejecución al recuperar un inicio omitido y evitar instancias simultáneas. Capturar la salida en un registro, revisar el resultado de la tarea y el manifiesto al día siguiente, y corregir cualquier fallo durante el mismo día. Si Windows o una VM están apagados/guardados no se genera copia: ejecutar manualmente tras iniciarlos y antes del siguiente apagado. Una tarea omitida amplía el RPO real. El script tiene bloqueo contra ejecuciones simultáneas con el mismo directorio de respaldo.

**Estado de entrega:** política y scripts incluidos; no se instaló una tarea programada, no se configuró destino externo y no se acredita todavía un respaldo real ni un ensayo de restauración de estos scripts. PostgreSQL estaba apagado durante la preparación. Registrar la primera ejecución correcta antes de considerar activa la política.
