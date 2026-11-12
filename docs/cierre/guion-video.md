# Guion del video

Historia de Jira: SIRAV-37. Video demostrativo de 14 minutos y 30 segundos (el máximo es 15) para David Felipe Bejarano Montes y Jose David Rodriguez. Sigue la demostración de la sección 9 de la propuesta, sobre el despliegue real en las tres máquinas virtuales.

Cada escena dice quién habla, qué se muestra en pantalla y el texto sugerido. No hace falta leerlo palabra por palabra: lo importante es mostrar cada cosa en el orden indicado.

**Reparto:** David presenta el modelo de datos, PostgreSQL, MongoDB y la seguridad. Jose David presenta la infraestructura, el flujo del cliente y del operador, los reportes y las pruebas. Cada uno habla unos 7 minutos.

## Antes de grabar (lista de preparación)

**Un día antes**

- [ ] Publicar la API nueva y actualizar la base de las VM, en ese orden (guía de instalación, parte A, "Actualizar las VM").
- [ ] Comprobar que `pruebas-excepciones.sql` muestra las ocho líneas `[OK]`.
- [ ] Ejecutar el primer respaldo real: `scripts/backup-vms.ps1`. Luego `scripts/test-backup-vms.ps1 -BackupDirectory backups/<id>`. Guardar el `manifest.json`: se muestra en la escena 9.

**El día de la grabación**

- [ ] Encender las tres VM con `scripts/manage-sirav-vms.ps1 -Action Start` y esperar a `-Action Check` en verde. La API puede tardar hasta unos 11 minutos en arrancar.
- [ ] Abrir la aplicación en una ventana privada del navegador (`http://localhost:8088` o la IP de SIRAV-Web en la red local), con zoom al 110 %.
- [ ] Elegir **un vehículo libre hoy y mañana** y anotar su placa: `______`.
- [ ] Tener dos imágenes de prueba (PNG o JPEG, menos de 5 MB): una de entrega y una de un rayón.
- [ ] Dejar abiertas tres terminales con letra de 16 pt o más:
  - **T1**: PowerShell en la raíz del proyecto.
  - **T2**: `psql` conectado a `127.0.0.1:15432` como `sirav_owner`.
  - **T3**: SSH a SIRAV-MongoDB (`ssh -i .runtime/virtualbox/id_ed25519 -p 2222 sirav@127.0.0.1`).
- [ ] Dejar abiertas en pestañas: los diagramas de `docs/diagramas/` y el workflow **SIRAV CI** en GitHub Actions.
- [ ] **Cuidar los secretos:** no mostrar `.env`, `.runtime/` ni contraseñas en pantalla. Escribir la contraseña de psql sin mostrarla.
- [ ] Grabar a 1920×1080, con los micrófonos probados y las notificaciones silenciadas.

## Escenas

### Escena 0. Presentación (0:00 a 0:40, David)

**Pantalla:** portada (README del repositorio o diapositiva con el nombre del proyecto).

> **David:** Buenas, profesor. Somos David Bejarano y Jose David Rodríguez, y este es SIRAV, el Sistema Integral de Reservas y Alquiler de Vehículos, nuestro proyecto final de Bases de Datos 2. En los próximos catorce minutos le vamos a mostrar el modelo de datos, las reglas que viven en PostgreSQL, el uso de MongoDB, el despliegue en máquinas virtuales Linux y las pruebas que hicimos.

### Escena 1. Problema y arquitectura (0:40 a 2:00, Jose David)

**Pantalla:** VirtualBox con las tres VM encendidas. Luego el diagrama `SIRAV_arquitectura_3VM.png`.

> **Jose David:** El problema es el de una empresa pequeña de alquiler que hoy maneja reservas en hojas de cálculo. El riesgo principal es asignar el mismo carro a dos clientes en fechas que se cruzan, sobre todo cuando dos personas reservan al mismo tiempo. Además, las inspecciones de daños quedan sueltas, sin estructura.
>
> Aquí está la infraestructura: tres máquinas virtuales Ubuntu Server 24.04 en VirtualBox, cada una con 2 GB de RAM. Una tiene PostgreSQL 17, otra MongoDB 8 y la tercera la parte web: Nginx con React y la API en Java con Spring Boot, que corre como servicio del sistema. Se comunican por una red privada; las bases no se exponen a la red local y el navegador solo entra por el puerto 80 de la máquina web.

**Pantalla:** T1, `scripts/manage-sirav-vms.ps1 -Action Check`.

> **Jose David:** Con este script comprobamos que las tres están arriba y que la API responde con las dos bases conectadas.

### Escena 2. Modelo de datos (2:00 a 3:30, David)

**Pantalla:** `SIRAV_ER_Chen.png`, luego `SIRAV_ER_Extendido.png` y luego `SIRAV_Relacional_CrowsFoot.png`.

> **David:** El modelo relacional tiene trece entidades. En el modelo de Chen se ven las relaciones uno a uno, como reserva y alquiler; uno a muchos, como vehículo y reservas; y muchos a muchos, como usuario y rol, resuelta con la tabla `usuario_rol`.
>
> En el EER modelamos dos especializaciones. Una es la de usuario por perfiles, que es superpuesta porque una persona puede ser operador y cliente. La otra es la de cliente, que es disyunta y total: o tiene cuenta, o se registró en mostrador.
>
> Esa segunda especialización vino de corregir la tercera forma normal. Al principio el cliente repetía su nombre y su correo aunque tuviera cuenta, y eso generaba datos contradictorios al actualizar. Ahora la identidad se guarda en un solo lugar: una restricción CHECK lo garantiza y la vista `v_cliente_contacto` la lee sin copiarla.
>
> Este diagrama Crow's Foot lo generamos directamente del catálogo de la base, así que coincide exactamente con lo que está desplegado.

### Escena 3. Flujo del cliente (3:30 a 5:00, Jose David)

**Pantalla:** la aplicación. Iniciar sesión con `cliente@sirav.local`.

> **Jose David:** Ahora entro como cliente. En **Nuestra flota** están los 25 vehículos de prueba en cinco categorías. Busco disponibilidad de hoy a mañana.

**Acción:** elegir las fechas de hoy a mañana, elegir el vehículo anotado, mostrar la cotización y reservar.

> **Jose David:** La aplicación me muestra el costo: días por tarifa diaria vigente. Esa tarifa queda congelada en la reserva, para que si mañana sube el precio, mi reserva conserve el que pacté. Reservo… y queda en estado **SOLICITADA**. Por dentro, la API no inserta directamente en la tabla: llama al procedimiento almacenado `sp_crear_reserva`.

### Escena 4. La regla principal en la base (5:00 a 6:30, David)

**Pantalla:** la aplicación (misma sesión de cliente).

> **David:** Ahora la prueba importante. Intento reservar el mismo vehículo con fechas que se cruzan…

**Acción:** reservar el mismo vehículo de mañana a pasado mañana. Aparece "El vehículo no está disponible en esas fechas".

> **David:** …y la base la rechaza. Esa regla no la cuida la pantalla, sino PostgreSQL.

**Pantalla:** T2. Ejecutar `\d reserva` y señalar `ex_reserva_vehiculo_periodo`.

> **David:** Es una restricción de exclusión GiST sobre el rango de fechas, con intervalo semiabierto: el día de devolución el carro ya queda libre. Además, el procedimiento bloquea el vehículo con `FOR UPDATE`, así que si dos personas reservan a la vez, solo una gana. Eso lo comprueba una prueba automática con dos hilos simultáneos.

**Pantalla:** T2. Ejecutar `\i database/postgres/pruebas-excepciones.sql`.

> **David:** Cada regla que la base rechaza tiene su propia excepción con nombre y código, como pide la propuesta. Este script provoca las ocho a propósito y lo revierte todo al final: reserva solapada, mantenimiento solapado, transición inválida, inspección faltante, vehículo no disponible, tarifa no vigente, parámetro inválido y tarifa histórica. Las ocho devuelven su código y su nombre.

### Escena 5. Flujo del operador (6:30 a 8:45, Jose David)

**Pantalla:** cerrar sesión e iniciar como `operador@sirav.local`. Ir a **Reservas**.

> **Jose David:** Ahora soy el operador. Veo la reserva que hizo el cliente y la confirmo.

**Acción:** **Confirmar reserva**. Ir a **Alquileres e inspecciones** y registrar la **Entrega del vehículo**: kilometraje, combustible, observaciones y la imagen de entrega.

> **Jose David:** Para entregar el carro el sistema exige la inspección: kilometraje, combustible, daños y fotos. Sin inspección no hay entrega; esa es la excepción SR004 que vimos. La foto se guarda en el disco del servidor web y MongoDB guarda su referencia. El vehículo pasa a **ALQUILADO**.

**Acción:** registrar la **Devolución del vehículo**: un kilometraje mayor, 80 % de combustible, un daño en la zona "Puerta trasera" con severidad **ALTA** y la foto del rayón.

> **Jose David:** En la devolución registro un rayón grave. Al cerrar, el procedimiento `sp_cerrar_alquiler` calcula el costo y, si hubiera retraso, un cargo del 50 % de la tarifa por cada día. Luego registra el pago simulado, todo en una sola transacción.

**Pantalla:** **Cobros simulados**; luego, en **Reservas**, **Ver detalle** de la reserva para ver su **Historial**.

> **Jose David:** Aquí está el pago simulado aprobado. Y en el historial se ve la auditoría que llena un trigger: solicitada, confirmada, activa y cerrada, con quién hizo cada cambio y cuándo.

### Escena 6. MongoDB (8:45 a 10:15, David)

**Pantalla:** T3. Entrar a mongosh:

```bash
sudo docker exec -it sirav-mongo mongosh -u sirav_app --authenticationDatabase sirav_3fn sirav_3fn -p
```

Luego ejecutar `db.inspecciones_vehiculo.find({anulada:false}).sort({fecha:-1}).limit(1)`.

> **David:** Esta es la inspección que acabamos de registrar, en la VM de MongoDB. Usamos MongoDB para lo que tiene estructura variable: una inspección tiene cero o muchos daños, cada uno con zona, severidad y descripción, más las fotos. Todo va embebido en un solo documento, el patrón Embedding del manual. Entrega y devolución viven en la misma colección, distinguidas por el campo `tipo`: el patrón Polymorphic.
>
> ¿Cómo llega aquí sin transacciones distribuidas? El procedimiento escribe la inspección en una tabla outbox de PostgreSQL, en la misma transacción del alquiler. Un publicador la copia a MongoDB con reintentos y sin duplicar. Si MongoDB se cae, no se pierde nada.

**Pantalla:** la aplicación, **Alquileres e inspecciones**, sección de inspecciones. Usar **Corregir inspección** sobre esa inspección, cambiar la descripción y **Guardar corrección**. Después marcar el filtro de daños graves.

> **David:** Si un operador se equivoca, corrige la inspección. El documento guarda la versión anterior en su historial y sube el número de versión. Si dos personas corrigen a la vez, la segunda recibe un conflicto. Aquí filtramos los daños graves con una consulta `$elemMatch`.

**Pantalla:** **Historial y reportes**, con las tres agregaciones: **Promedios por categoría**, **Zonas con daños por mes** e **Incidencias por vehículo**.

> **David:** Y estas son las tres agregaciones: promedios por categoría, zonas con daños por mes e incidencias por vehículo.

### Escena 7. Reportes SQL (10:15 a 11:15, Jose David)

**Pantalla:** **Historial y reportes**: ocupación (R1), ranking (R3) y disponibilidad (R6).

> **Jose David:** Tenemos seis reportes SQL. El de ocupación genera un calendario con `generate_series` y lo cruza con los rangos de alquiler. El de ingresos agrega los pagos antes del JOIN, para no multiplicar montos. El ranking usa la función de ventana `rank` particionada por categoría. Y el de disponibilidad reutiliza la misma función de la base, junto con un `NOT EXISTS` contra los mantenimientos. Los seis responden en menos de 20 milisegundos con los datos de prueba.

### Escena 8. Seguridad (11:15 a 12:30, David)

**Pantalla:** T2. Ejecutar:

```sql
SET ROLE sirav_app;
DELETE FROM reserva WHERE id_reserva = 1;
SET ROLE sirav_reportes;
SELECT password_hash FROM usuario LIMIT 1;
RESET ROLE;
```

> **David:** La seguridad también vive en la base. La API se conecta con el usuario `sirav_app`, que no puede insertar, modificar ni borrar reservas, alquileres, pagos ni auditoría directamente: solo a través de los procedimientos. Por eso este DELETE es rechazado. El perfil de reportes es de solo lectura y ni siquiera puede ver las contraseñas cifradas.

**Pantalla:** la aplicación como `admin@sirav.local`, en **Usuarios y perfiles**.

> **David:** En la aplicación, las contraseñas se guardan con BCrypt y las sesiones usan JWT de treinta minutos. El administrador asigna perfiles. Si cambia los permisos de alguien o esa persona cambia su contraseña, sus sesiones anteriores se revocan al instante.

### Escena 9. Pruebas, respaldos y equipo (12:30 a 13:45, Jose David)

**Pantalla:** GitHub Actions, última ejecución de **SIRAV CI** en verde.

> **Jose David:** Probamos contra motores reales, no simulados. En cada cambio, GitHub Actions crea una base nueva y corre setenta y dos pruebas de Java: integración, auditoría de SQL, concurrencia, API y MongoDB. Corre también la prueba de las ocho excepciones. En las máquinas virtuales hicimos una auditoría con ochenta y una pruebas aprobadas y sesenta y cuatro solicitudes simultáneas. Esa auditoría encontró siete fallos, como valores nulos que pasaban o errores 500, y los corregimos.

**Pantalla:** `backups/<id>/manifest.json`.

> **Jose David:** Para los respaldos tenemos una política diaria con retención de catorce días y verificación SHA-256. Este es el respaldo de las tres máquinas: la base relacional, la documental y las fotos, con su ensayo de restauración en bases nuevas.

**Pantalla:** el tablero de Jira y el repositorio de GitHub.

> **Jose David:** Trabajamos con Scrum en Jira y con ramas y pull requests en GitHub.

### Escena 10. Cierre (13:45 a 14:30, David y Jose David)

**Pantalla:** el README o la portada.

> **David:** Lo que más aprendimos es que las reglas críticas tienen que vivir en la base de datos. La restricción de exclusión impidió solapamientos que una validación en la pantalla no detecta cuando hay concurrencia.
>
> **Jose David:** Y que probar contra el sistema real encuentra errores reales: la auditoría en las VM y la integración continua encontraron fallos que en nuestros equipos no aparecían.
>
> **David:** Como trabajo futuro quedan una prueba de carga con más volumen y precalcular las agregaciones si los datos crecen.
>
> **Ambos:** Muchas gracias, profesor.

## Si algo falla durante la grabación

| Problema | Qué hacer |
|---|---|
| La API todavía no responde | Esperar: en este equipo puede tardar hasta unos 11 minutos. Comprobar con `manage-web-vm.ps1 -Action Check` |
| "El vehículo no está disponible" en la primera reserva | Ese vehículo ya tiene reserva para hoy: usar otro libre (escena 3) |
| La inspección no aparece aún en MongoDB | El publicador trabaja cada 2 segundos: esperar un momento y repetir la consulta |
| Error 500 en lugar del mensaje de la regla | Se actualizó la base sin publicar antes la API nueva: ejecutar `deploy-web-vm.ps1` |
| Se ve una contraseña o un secreto en pantalla | Cortar esa toma y repetirla; no publicar el video con secretos visibles |

**Después de grabar:** subir el video, poner el enlace en el README y en SIRAV-37, y guardar las capturas de evidencia que pide la guía de instalación.
