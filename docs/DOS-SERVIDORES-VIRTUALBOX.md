# SIRAV: dos servidores de bases de datos en VirtualBox

La instalación completa incluye además la VM **SIRAV-Web** con frontend y API. Para abrir la aplicación desde otros navegadores y administrar las tres VM, consulta [Web en VirtualBox](WEB-EN-VIRTUALBOX.md).

El proyecto usa PostgreSQL para sus entidades, reglas y transacciones, y MongoDB para inspecciones y bitácora. Esta instalación separa los motores en dos VM Ubuntu Server 24.04 LTS sin escritorio. La API Java y React pueden ejecutarse en Windows.

| Recurso | Relacional | No relacional |
| --- | --- | --- |
| Nombre en VirtualBox | SIRAV-PostgreSQL | SIRAV-MongoDB |
| RAM | 2048 MB | 2048 MB |
| CPU virtuales | 2 | 2 |
| Disco dinámico máximo | 20 GB | 20 GB |
| Motor del proyecto | PostgreSQL 17.6 | MongoDB 8.0.5 |
| Base | sirav_3fn | sirav_3fn |
| Dirección privada | 192.168.56.21 | 192.168.56.22 |
| Conexión desde Windows | 127.0.0.1:15432 | 127.0.0.1:17017 |
| SSH desde Windows | 127.0.0.1:2221 | 127.0.0.1:2222 |

Cada máquina tiene un adaptador NAT para Internet y otro solo-anfitrión para comunicarse con Windows y la otra VM. Los puertos NAT se publican exclusivamente en 127.0.0.1. El adaptador privado existente tiene dirección 192.168.56.1/24; las IP estáticas elegidas están fuera de su rango DHCP 192.168.56.101–254. No se cambia la configuración de otras VM.

Los motores se ejecutan en contenedores Docker dentro de las VM. Se reutilizan las imágenes y los inicializadores de `compose.yaml`, sin instalar el backend ni el frontend dentro de estas máquinas de 2 GB. Cada contenedor tiene límite de 1200 MB; MongoDB usa caché WiredTiger de 0.25 GB. Cada invitado dispone además de 1 GB de swap. Los volúmenes Docker conservan los datos entre apagados.

Este equipo ejecuta VirtualBox sobre el hipervisor de Windows (modo NEM). Se seleccionó paravirtualización `minimal` y reloj HPET para probar compatibilidad tras observar bloqueos con el proveedor KVM predeterminado. El arranque puede ser lento; no se desactivó Hyper-V ni se cambiaron funciones de seguridad de Windows.

## Encender, consultar y apagar

Desde PowerShell, en la raíz del proyecto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/manage-database-vms.ps1 -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/manage-database-vms.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/manage-database-vms.ps1 -Action Check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/manage-database-vms.ps1 -Action Stop
```

`Stop` solicita un apagado normal. `-Machine Postgres` o `-Machine Mongo` permite operar una sola máquina. También aparecen en la ventana habitual de VirtualBox; «Mostrar» permite abrir sus consolas. El primer arranque descarga Docker y las imágenes: espera a que `cloud-init status` indique `done` y verifica los servicios.

Si la inicialización falla, `-Action Diagnose -Machine Postgres` (o `Mongo`) muestra los registros. `-Action Repair` permite completar una instalación interrumpida en estas VM: conserva respaldos de los registros temporales inválidos de paquetes bajo `/root/sirav-recovery`. Cuando la provisión ya terminó, no se repite la carga inicial.

## Administrar por SSH

El usuario Linux es `sirav`. La clave privada está en `.runtime/virtualbox/id_ed25519`. La contraseña de consola se genera durante la preparación y se conserva en `.runtime/virtualbox/access.json`; consulta ese archivo localmente si necesitas iniciar sesión en la consola de VirtualBox. El acceso SSH utiliza clave, sin contraseña.

```powershell
ssh -i .runtime/virtualbox/id_ed25519 -p 2221 sirav@127.0.0.1
ssh -i .runtime/virtualbox/id_ed25519 -p 2222 sirav@127.0.0.1
```

En cualquiera de los invitados:

```bash
cloud-init status --long
sudo tail -n 60 /var/log/sirav-provision.log
sudo docker ps
```

En PostgreSQL:

```bash
sudo docker exec -it sirav-postgres psql -U sirav_owner -d sirav_3fn
```

En MongoDB, solicita la contraseña de `sirav_app` de `.env`:

```bash
sudo docker exec -it sirav-mongo mongosh --username sirav_app --authenticationDatabase sirav_3fn sirav_3fn --password
```

## Conectar la aplicación

Las credenciales técnicas se toman del `.env` existente. La preparación genera `.runtime/virtualbox/backend.env` con las conexiones a las VM. Los archivos de `.runtime` están ignorados por Git y contienen secretos; no deben compartirse ni incluirse en capturas.

Para una API alojada en otra VM conectada a esta misma red privada, los destinos son `192.168.56.21:5432` y `192.168.56.22:27017`. Los puertos 15432 y 17017 corresponden al acceso desde Windows por NAT.

Con ambas bases listas y el JAR compilado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-vm-api.ps1
```

El script usa Java 23 instalado en este equipo y permite cambiarlo con `-Java RUTA`. Requiere Java 21 o posterior. Si otra API ya ocupa 8080, detén esa instancia desde su terminal antes de ejecutar el comando. Para compilar el JAR usa `mvn -f backend/pom.xml verify`.

En otra terminal:

```powershell
npm --prefix frontend run dev -- --host 127.0.0.1
```

Abre http://localhost:5173. La salud de la API se consulta en http://localhost:8080/actuator/health. `scripts/start-local.ps1` corresponde a las bases locales anteriores de Windows; para usar estas VM utiliza `start-vm-api.ps1`.

Las VM inicializan una base nueva con el esquema y los datos de arranque del proyecto. Los datos operativos de las bases locales de Windows no se migran automáticamente. Copiar archivos del directorio de datos entre versiones no sustituye un respaldo y una restauración.

## Preparación reproducible

`scripts/create-database-vms.ps1` verifica el SHA-256 de la imagen oficial descargada, genera claves y datos de cloud-init, crea las VM y deja el arranque a cargo del usuario. Usa por defecto `C:\Users\Jose David\VirtualBox VMs`, fuera de OneDrive. Una ejecución posterior reconoce las VM creadas mediante comprobantes UUID y conserva las máquinas ya preparadas.

Imagen oficial: [Ubuntu Server 24.04 LTS](https://cloud-images.ubuntu.com/releases/noble/release/). Procedimiento de referencia: [Ubuntu: imágenes cloud en VirtualBox](https://ubuntu.com/docs/public-images/public-images-how-to/run-an-ova-using-virtualbox/).

Las evidencias académicas deben mostrar las dos VM, sus 2048 MB, el sistema operativo, la red privada, los contenedores funcionando y consultas reales a ambos motores. Conserva respaldos fuera de los discos virtuales antes de modificar o eliminar datos.

## Verificación realizada

Se comprobó la conexión a PostgreSQL desde Windows en `127.0.0.1:15432` como `sirav_app`: base `sirav_3fn`, versión 17.6, 14 tablas públicas (13 entidades y la tabla técnica), 25 vehículos y procedimiento `sp_cargar_historial_demo()` disponible. En MongoDB se verificó el acceso autenticado a `sirav_3fn`, las colecciones `inspecciones_vehiculo` y `bitacora_operaciones`, y los cuatro índices de inspecciones, incluido el único por `alquilerId`/`tipo`.

Un reinicio normal de PostgreSQL confirmó el arranque automático del contenedor y la persistencia de tablas y datos; `cloud-init status` terminó en `done`. Se observaron aproximadamente 375 MB de memoria usados en ese invitado y 459 MB en MongoDB durante la comprobación, con 2048 MB asignados a cada VM. Ambas quedaron encendidas.
