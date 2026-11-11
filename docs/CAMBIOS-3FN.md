# Adaptación al esquema revisado

Fuente: `01-schema-SIRAV-revisado-3FN.sql` suministrado el 8 de noviembre de 2026. Se conserva una copia exacta en `database/postgres/01-schema.sql` y otra de referencia en `docs/referencias/`.

## Identidad del cliente

| Caso | USUARIO | CLIENTE | Lectura para la aplicación |
| --- | --- | --- | --- |
| Cliente con cuenta | Nombre, apellido, correo y credenciales | id_usuario, documento, teléfono y licencia; nombres/apellidos/email NULL | v_cliente_contacto |
| Cliente sin cuenta | Sin fila asociada | Nombre, apellidos, correo opcional y datos de contacto | v_cliente_contacto |

El registro público inserta la identidad una sola vez en USUARIO y crea el perfil en CLIENTE sin copiarla. DemoSeed aplica la misma regla. La API que registra clientes de mostrador crea CLIENTE sin id_usuario. Las consultas de reservas y los reportes de clientes/devoluciones usan la vista.

No se ejecuta dos veces el ALTER que añadía token_version ni se duplica la exclusión GiST de reservas: ambos objetos ya existen en el esquema revisado. La versión del token es BIGINT, según el archivo recibido. Las reglas adicionales de combustible, estados, tarifas, mantenimiento y transacciones siguen en los scripts 02 y 03.

## Funciones retiradas

- Dashboard y tarjetas de indicadores generales.
- CRUD administrativo de usuarios y cambio de roles desde la interfaz.
- Edición de perfil y edición de clientes.
- Exportación CSV y su código de descarga.
- Interceptor genérico de auditoría HTTP.
- Ilustraciones y estilos decorativos del frontend.

La auditoría oficial de reservas, la bitácora de sus estados en MongoDB, los seis reportes SQL y las tres agregaciones documentales se mantienen. El formulario de inspecciones se define una sola vez. La autorización se sigue comprobando en el servidor.

## Datos anteriores

El nuevo esquema es para crear una base nueva. Esta versión utiliza sirav_3fn y volúmenes Compose nuevos. No borra ni altera sirav. Si se necesitan operaciones históricas anteriores, se debe planear una migración de datos que resuelva diferencias de identidad antes de aplicar la nueva restricción; no se mezcla ese trabajo con la simplificación solicitada.

## Entrega

El ZIP nuevo excluye secretos, datos locales, dependencias descargadas, artefactos anteriores y documentos obsoletos. La copia anterior del proyecto permanece disponible en output/SIRAV-proyecto-completo.zip.
