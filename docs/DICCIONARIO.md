# Diccionario de datos

El esquema conserva las 13 entidades de dominio del SQL original. Los identificadores simples se generan como identidades; Usuario_Rol conserva su clave compuesta. Los timestamps de eventos usan zona horaria.

## Relaciones y normalización

- Usuario–Cliente: 1 a 0..1 mediante FK única opcional.
- Reserva–Alquiler: 1 a 0..1 mediante FK única obligatoria en Alquiler.
- Usuario–Rol: N:M mediante Usuario_Rol con clave compuesta.
- Categoría–Vehículo, Categoría–Tarifa, Cliente–Reserva, Vehículo–Reserva y Vehículo–Mantenimiento: 1:N.
- Alquiler–Pago, Alquiler–Cargo_Adicional, Reserva–Auditoria_Reserva y Usuario–Auditoria_Reserva: 1:N.

El esquema sigue el diseño revisado aportado por el usuario. En clientes con cuenta, nombre, apellido y correo se almacenan exclusivamente en Usuario; en clientes sin cuenta, se almacenan en Cliente. La restricción ck_CLIENTE_origen_identidad impide duplicarlos. La vista v_cliente_contacto resuelve ambos casos sin copiar valores. Los totales financieros y la disponibilidad se calculan mediante vistas y funciones.

No se necesita especialización EER para este alcance: los perfiles de acceso son asignaciones N:M, no subtipos disjuntos. Las extensiones técnicas de seguridad e integración se documentan al final.

## USUARIO

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_usuario | BIGINT | No | PK; Identidad automática |
| nombre | VARCHAR(100) | No | Dato de dominio |
| apellido | VARCHAR(100) | No | Dato de dominio |
| email | VARCHAR(150) | No | UNIQUE |
| password_hash | VARCHAR(255) | No | Dato de dominio |
| activo | BOOLEAN | No | Dato de dominio |
| creado_en | TIMESTAMPTZ | No | Fecha actual por defecto |
| token_version | BIGINT | No | Dato de dominio |

## ROL

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_rol | BIGINT | No | PK; Identidad automática |
| nombre | VARCHAR(30) | No | UNIQUE |

## USUARIO_ROL

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_usuario | BIGINT | No | PK; FK → USUARIO |
| id_rol | BIGINT | No | PK; FK → ROL |
| asignado_en | TIMESTAMPTZ | No | Fecha actual por defecto |

## CLIENTE

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_cliente | BIGINT | No | PK; Identidad automática |
| id_usuario | BIGINT | Sí | UNIQUE; FK → USUARIO |
| nombres | VARCHAR(100) | Sí | Dato de dominio |
| apellidos | VARCHAR(100) | Sí | Dato de dominio |
| documento | VARCHAR(30) | No | UNIQUE |
| telefono | VARCHAR(25) | Sí | Dato de dominio |
| email | VARCHAR(150) | Sí | Dato de dominio |
| licencia_conduccion | VARCHAR(40) | Sí | Dato de dominio |

## CATEGORIA_VEHICULO

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_categoria | BIGINT | No | PK; Identidad automática |
| nombre | VARCHAR(70) | No | UNIQUE |
| descripcion | VARCHAR(4000) | Sí | Dato de dominio |

## VEHICULO

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_vehiculo | BIGINT | No | PK; Identidad automática |
| id_categoria | BIGINT | No | FK → CATEGORIA_VEHICULO |
| placa | VARCHAR(12) | No | UNIQUE |
| marca | VARCHAR(70) | No | Dato de dominio |
| modelo | VARCHAR(70) | No | Dato de dominio |
| anio | SMALLINT | No | Dato de dominio |
| color | VARCHAR(40) | Sí | Dato de dominio |
| kilometraje_actual | INTEGER | No | Dato de dominio |
| estado_operativo | VARCHAR(20) | No | Dato de dominio |

## TARIFA

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_tarifa | BIGINT | No | PK; Identidad automática |
| id_categoria | BIGINT | No | FK → CATEGORIA_VEHICULO |
| valor_diario | NUMERIC(12,2) | No | Dato de dominio |
| vigente_desde | DATE | No | Dato de dominio |
| vigente_hasta | DATE | Sí | Dato de dominio |

## RESERVA

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_reserva | BIGINT | No | PK; Identidad automática |
| id_cliente | BIGINT | No | FK → CLIENTE |
| id_vehiculo | BIGINT | No | FK → VEHICULO |
| id_tarifa | BIGINT | No | FK → TARIFA |
| fecha_inicio | DATE | No | Dato de dominio |
| fecha_fin | DATE | No | Dato de dominio |
| fecha_solicitud | TIMESTAMPTZ | No | Fecha actual por defecto |
| estado | VARCHAR(15) | No | Dato de dominio |

## ALQUILER

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_alquiler | BIGINT | No | PK; Identidad automática |
| id_reserva | BIGINT | No | UNIQUE; FK → RESERVA |
| fecha_entrega | TIMESTAMPTZ | No | Dato de dominio |
| fecha_devolucion | TIMESTAMPTZ | Sí | Dato de dominio |
| km_salida | INTEGER | No | Dato de dominio |
| km_entrada | INTEGER | Sí | Dato de dominio |
| combustible_salida | NUMERIC(5,2) | No | Dato de dominio |
| combustible_entrada | NUMERIC(5,2) | Sí | Dato de dominio |
| estado | VARCHAR(15) | No | Dato de dominio |

## PAGO

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_pago | BIGINT | No | PK; Identidad automática |
| id_alquiler | BIGINT | No | FK → ALQUILER |
| fecha_pago | TIMESTAMPTZ | No | Fecha actual por defecto |
| monto | NUMERIC(12,2) | No | Dato de dominio |
| tipo | VARCHAR(30) | No | Dato de dominio |
| estado | VARCHAR(15) | No | Dato de dominio |

## CARGO_ADICIONAL

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_cargo | BIGINT | No | PK; Identidad automática |
| id_alquiler | BIGINT | No | FK → ALQUILER |
| concepto | VARCHAR(60) | No | Dato de dominio |
| descripcion | VARCHAR(4000) | Sí | Dato de dominio |
| monto | NUMERIC(12,2) | No | Dato de dominio |
| fecha_registro | TIMESTAMPTZ | No | Fecha actual por defecto |

## MANTENIMIENTO

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_mantenimiento | BIGINT | No | PK; Identidad automática |
| id_vehiculo | BIGINT | No | FK → VEHICULO |
| fecha_inicio | DATE | No | Dato de dominio |
| fecha_fin | DATE | No | Dato de dominio |
| descripcion | VARCHAR(4000) | No | Dato de dominio |
| estado | VARCHAR(15) | No | Dato de dominio |

## AUDITORIA_RESERVA

| Campo | Tipo | Nulo | Claves y valores |
| --- | --- | --- | --- |
| id_auditoria | BIGINT | No | PK; Identidad automática |
| id_reserva | BIGINT | No | FK → RESERVA |
| id_usuario | BIGINT | Sí | FK → USUARIO |
| estado_anterior | VARCHAR(15) | Sí | Dato de dominio |
| estado_nuevo | VARCHAR(15) | No | Dato de dominio |
| fecha_evento | TIMESTAMPTZ | No | Fecha actual por defecto |
| observacion | VARCHAR(4000) | Sí | Dato de dominio |

## Extensiones implementadas

| Tabla/campo | Tipo | Propósito |
| --- | --- | --- |
| Reserva.idempotencia | UUID NOT NULL UNIQUE | Reintentos de la misma solicitud |
| Evento_Outbox.id | UUID PK | Identidad idempotente del evento |
| Evento_Outbox.coleccion | VARCHAR(50) NOT NULL | Destino documental permitido |
| Evento_Outbox.documento | JSONB NOT NULL | Documento durable hasta publicación |
| Evento_Outbox.creado_en | TIMESTAMPTZ NOT NULL DEFAULT now() | Orden y trazabilidad |
| Evento_Outbox.publicado_en | TIMESTAMPTZ opcional | Confirmación de escritura MongoDB |
| Evento_Outbox.intentos | INTEGER NOT NULL DEFAULT 0 | Reintentos realizados |

## Restricciones adicionales

Fechas fin posteriores al inicio; tarifas positivas y vigencias sin cruces; kilómetros no negativos ni decrecientes al devolver; combustible entre 0 y 100; estados enumerados; pagos exclusivamente SIMULADO; reservas vigentes sin cruces; mantenimiento sin cruces con reservas. Ver `database/postgres/02-integrity.sql` para la definición ejecutable.

## Modelo documental

`inspecciones_vehiculo`: `_id` UUID del evento, `alquilerId`, `vehiculoId`, `categoriaId`, `tipo`, `fecha`, `actor`, `kilometraje`, `combustible`, `danos[]` (zona, severidad, descripción), `evidencias[]`, `observaciones`, `anulada`, `version` e historial de correcciones. Índice único por alquiler y tipo; índices de vehículo/fecha y severidad/fecha.

`bitacora_operaciones`: `_id`, acción, actor, fecha y datos variables del evento. Índice de fecha descendente. La auditoría oficial de reservas se conserva en PostgreSQL, incluso si la proyección documental está pendiente.

Las listas variables de daños y evidencias justifican el almacenamiento documental. Las relaciones monetarias y el control de disponibilidad permanecen en el motor relacional. No existen FK entre motores; la API verifica pertenencia e identidad del alquiler.
