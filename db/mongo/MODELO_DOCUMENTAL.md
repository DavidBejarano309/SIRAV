# Modelo documental de MongoDB — SIRAV

Historia de Jira: **SIRAV-23**. Implementación y pruebas: **SIRAV-25** (`01_colecciones.js`, `02_crud.js`, `03_datos.js`, `pruebas/`).

MongoDB guarda dos colecciones de la base `sirav`: **`inspecciones_vehiculo`** y **`bitacora_operaciones`**. El diseño aplica cuatro patrones del capítulo 13 del *Manual MQL MongoDB* del curso: **Embedding, Polymorphic, Computed y Bucket**. Descarta Subset y Outlier porque los datos de SIRAV no tienen el problema que esos patrones resuelven.

## 1. Por qué NoSQL para estos datos

| | PostgreSQL | MongoDB |
|---|---|---|
| Qué guarda | Reservas, alquileres, pagos, cargos, tarifas, vehículos, usuarios y auditoría de estados | Inspecciones de entrega y devolución, y bitácora de eventos de la aplicación |
| Naturaleza del dato | Estructurado, con relaciones e integridad transaccional | Estructura variable, se lee como documento completo |
| Reglas | RN-01 a RN-05 en restricciones, procedimientos y triggers | Validación `$jsonSchema` e índice único parcial |
| Papel | **Fuente única de verdad** del negocio | Registro documental complementario |

- **Inspecciones.** Cada inspección tiene cero o muchos daños, y cada daño trae zona, severidad, descripción y costo. Además lleva una lista variable de fotos. En SQL serían tres tablas (inspección, daño, evidencia) que siempre se consultan juntas. En MongoDB es un solo documento que se lee y se escribe de una vez.
- **Bitácora.** Es de escritura continua, no tiene relaciones y cada tipo de evento trae datos distintos (un inicio de sesión fallido no se parece a una reserva rechazada). En SQL obligaría a una tabla por evento o a muchas columnas vacías.
- **Lo que no va en MongoDB.** El estado oficial de reservas y alquileres, los pagos y la auditoría transaccional se quedan en PostgreSQL. MongoDB no copia esos datos (se evita el anti-patrón de usar MongoDB como caché de SQL).

## 2. Colección `inspecciones_vehiculo`

Un documento por inspección. Cada alquiler tiene una de **ENTREGA** y, al cerrarse, una de **DEVOLUCION**.

| Campo | Tipo | Notas |
|---|---|---|
| `tipo` | `ENTREGA` \| `DEVOLUCION` | Define la forma del documento (Polymorphic) |
| `id_alquiler` | int | **Referencia lógica** a `alquiler.id_alquiler` de PostgreSQL. No hay llave foránea entre motores: la valida la aplicación |
| `vehiculo` | `{id_vehiculo, placa, categoria}` | Copia de datos casi inmutables, necesaria para agrupar por categoría sin consultar PostgreSQL |
| `fecha` | date | Momento de la inspección |
| `km`, `combustible` | int, número 0–100 | Lectura del tablero; combustible en porcentaje |
| `danos[]` | `{zona, severidad, descripcion, nuevo, costo_estimado?}` | Embebidos. Máximo 30. `nuevo` indica si el daño no estaba en la entrega |
| `evidencias[]` | texto | **Solo nombres de archivo** `.jpg`/`.png`, máximo 20; las imágenes no se guardan en la base |
| `observaciones` | texto | Opcional |
| `resumen` | objeto | **Solo en DEVOLUCION**, calculado al guardar (Computed) |
| `id_usuario_inspector` | int | Operador que hizo la inspección |
| `estado` | `VIGENTE` \| `ANULADA` | Las inspecciones no se borran: se anulan con motivo |
| `anulacion` | `{motivo, fecha, id_usuario}` | Solo si está anulada |
| `version_esquema` | int | Hoy 1; permite evolucionar el documento sin migrar todo |

**Ejemplo: inspección de entrega** (alquiler 4; las fechas de los datos de ejemplo son relativas al día de carga)

```json
{
  "_id": { "$oid": "6af4f73ee6742ca95386fd2b" },
  "tipo": "ENTREGA",
  "id_alquiler": 4,
  "vehiculo": { "id_vehiculo": 16, "placa": "TUV401", "categoria": "SUV" },
  "fecha": { "$date": "2026-09-21T12:50:00Z" },
  "km": 20800,
  "combustible": 100,
  "danos": [
    { "zona": "espejo_der", "severidad": "BAJA", "descripcion": "Carcasa del espejo con rayón preexistente", "nuevo": false }
  ],
  "evidencias": ["alq4_ent_01.jpg", "alq4_ent_02.jpg"],
  "id_usuario_inspector": 3,
  "estado": "VIGENTE",
  "version_esquema": 1
}
```

**Ejemplo: inspección de devolución** (alquiler 6; el daño de 250.000 es el mismo cargo `DANO` que tiene ese alquiler en PostgreSQL)

```json
{
  "_id": { "$oid": "6af4f73ee6742ca95386fd30" },
  "tipo": "DEVOLUCION",
  "id_alquiler": 6,
  "vehiculo": { "id_vehiculo": 21, "placa": "XYZ501", "categoria": "CAMIONETA" },
  "fecha": { "$date": "2026-10-11T22:20:00Z" },
  "km": 26750,
  "combustible": 100,
  "danos": [
    { "zona": "puerta_trasera_izq", "severidad": "ALTA",
      "descripcion": "Rayón profundo de 25 cm en la puerta trasera izquierda",
      "costo_estimado": 250000, "nuevo": true }
  ],
  "evidencias": ["alq6_dev_01.jpg", "alq6_dev_02.jpg", "alq6_dev_03.jpg"],
  "observaciones": "Daño reportado por el cliente al devolver. Se cobra según cotización de taller.",
  "resumen": {
    "total_danos": 1,
    "danos_nuevos": 1,
    "severidad_maxima": "ALTA",
    "km_recorridos": 850,
    "combustible_consumido": 0,
    "monto_danos_estimado": 250000
  },
  "id_usuario_inspector": 3,
  "estado": "VIGENTE",
  "version_esquema": 1
}
```

## 3. Colección `bitacora_operaciones`

Un documento por **día** con hasta **200 eventos**. Cuando un día supera los 200, se abre otro documento para el mismo día.

| Campo | Tipo | Notas |
|---|---|---|
| `fecha` | date | Medianoche (hora de Bogotá) del día del bucket |
| `count` | int 1–200 | Eventos en el bucket |
| `primer_ts`, `ultimo_ts` | date | Primer y último evento del bucket |
| `eventos[]` | `{tipo, ts, id_usuario, detalle}` | `detalle` cambia según `tipo` (Polymorphic) |

Tipos de evento: `LOGIN`, `LOGIN_FALLIDO`, `RESERVA_CREADA`, `RESERVA_RECHAZADA`, `RESERVA_CONFIRMADA`, `RESERVA_CANCELADA`, `ALQUILER_INICIADO`, `ALQUILER_CERRADO`, `INSPECCION_REGISTRADA`, `INSPECCION_CORREGIDA` e `INSPECCION_ANULADA`.

**Ejemplo de bucket** (recortado a 4 eventos)

```json
{
  "_id": { "$oid": "6af4f73e03eb5d953bee267b" },
  "fecha": { "$date": "2026-10-11T05:00:00Z" },
  "count": 4,
  "primer_ts": { "$date": "2026-10-11T17:10:00Z" },
  "ultimo_ts": { "$date": "2026-10-11T22:30:00Z" },
  "eventos": [
    { "tipo": "RESERVA_CREADA", "ts": { "$date": "2026-10-11T17:10:00Z" }, "id_usuario": 2,
      "detalle": { "id_reserva": 8, "id_vehiculo": 12 } },
    { "tipo": "RESERVA_CONFIRMADA", "ts": { "$date": "2026-10-11T20:10:00Z" }, "id_usuario": 3,
      "detalle": { "id_reserva": 8 } },
    { "tipo": "INSPECCION_REGISTRADA", "ts": { "$date": "2026-10-11T22:20:00Z" }, "id_usuario": 3,
      "detalle": { "id_alquiler": 6, "tipo": "DEVOLUCION", "id_inspeccion": "6af4f73ee6742ca95386fd30" } },
    { "tipo": "ALQUILER_CERRADO", "ts": { "$date": "2026-10-11T22:30:00Z" }, "id_usuario": 3,
      "detalle": { "id_alquiler": 6, "id_inspeccion_devolucion": "6af4f73ee6742ca95386fd30" } }
  ]
}
```

Un intento de reserva rechazado guarda la excepción de PostgreSQL:
`{ "tipo": "RESERVA_RECHAZADA", "detalle": { "id_vehiculo": 8, "sqlstate": "SR001", "excepcion": "e_reserva_solapada" } }`.

## 4. Patrones del capítulo 13

| Patrón | Dónde | Por qué |
|---|---|---|
| **Embedding** (13.1) | `danos[]`, `evidencias[]` y `vehiculo` dentro de la inspección | Se leen siempre con la inspección, son pocos (hasta 30 y 20) y no se consultan solos. Una lectura trae todo |
| **Polymorphic** (13.6) | `tipo` en inspecciones; `tipo` + `detalle` en eventos | Entrega y devolución comparten casi todo, pero solo la devolución tiene `resumen`; el validador exige una forma por tipo (`oneOf`). En la bitácora cada evento trae su propio detalle |
| **Computed** (13.3) | `resumen` de la devolución | Daños nuevos, severidad máxima, km recorridos, combustible consumido y monto de daños se calculan **una vez al guardar** en lugar de en cada consulta. Lo usan las agregaciones de SIRAV-26 y el cierre del alquiler. Si se corrige la entrega o la devolución, el resumen se recalcula |
| **Bucket** (13.2) | Bitácora por día, 200 eventos por documento | Agrupa la escritura continua en pocos documentos, facilita consultar un día completo y el tope evita arrays sin límite |

**Descartados.** **Subset (13.4)** sirve cuando un documento tiene un array enorme del que solo se muestra una parte; aquí una inspección tiene pocos daños. **Outlier (13.5)** sirve cuando unos pocos documentos son mucho más grandes que el resto; aquí todos tienen tamaño parecido.

**Anti-patrones evitados (13.7).** Arrays sin límite (topes de 30, 20 y 200); MongoDB como copia de SQL (solo se copian placa y categoría, que casi no cambian); `$lookup` masivos (no se necesitan); binarios en la base (solo nombres de archivo).

## 5. Relación con PostgreSQL

1. **Entrega.** `sp_iniciar_alquiler` crea el alquiler y devuelve `id_alquiler`. La aplicación guarda la inspección de ENTREGA con ese id.
2. **Devolución.** La aplicación guarda primero la inspección de DEVOLUCION en MongoDB (se calcula el `resumen`).
3. **Cierre.** Llama a `sp_cerrar_alquiler` con `param_id_inspeccion` = el `_id` de esa inspección y `param_monto_danos` = `resumen.monto_danos_estimado`. Sin el id, PostgreSQL rechaza el cierre (**RN-05**, `e_cierre_invalido`).
4. **Consistencia.** No hay transacción entre motores. Si el cierre falla, la inspección queda registrada y se puede volver a intentar el cierre o anular la inspección; la bitácora deja constancia.

## 6. Índices

| Índice | Campos | Para qué |
|---|---|---|
| `ux_inspeccion_alquiler_tipo` | `id_alquiler`, `tipo` (único, solo `VIGENTE`) | Una entrega y una devolución vigentes por alquiler; las anuladas no cuentan |
| `ix_inspeccion_vehiculo_fecha` | `vehiculo.id_vehiculo`, `fecha` | Historial e incidencias por vehículo |
| `ix_inspeccion_severidad_fecha` | `danos.severidad`, `fecha` | Consulta compleja con `$elemMatch` por severidad y fechas |
| `ix_inspeccion_tipo_categoria` | `tipo`, `vehiculo.categoria` | Promedio de km y combustible por categoría |
| `ix_bitacora_fecha_count` | `fecha`, `count` | Encontrar el bucket del día con espacio |
| `ix_bitacora_tipo_fecha` | `eventos.tipo`, `fecha` | Buscar eventos por tipo (sesiones fallidas, reservas rechazadas) |

## 7. Validación y seguridad

- **Validación.** `$jsonSchema` estricto en las dos colecciones: tipos, catálogos (zona, severidad, tipo de evento), rangos (combustible 0–100), formato de placa y de evidencias, sin campos extra y con una forma por tipo de inspección.
- **Usuarios** (mínimo privilegio, como en PostgreSQL):
  - `sirav_app_mongo`: consulta, inserta y actualiza las dos colecciones. No puede borrar, eliminar colecciones, cambiar validadores, crear usuarios ni leer otras bases. Por eso las inspecciones se **anulan**, no se borran.
  - `sirav_reportes_mongo`: solo lectura.

## 8. Operaciones

| Operación | Dónde |
|---|---|
| CRUD: registrar, consultar, corregir y anular inspecciones | `02_crud.js` (SIRAV-25) |
| Consulta compleja: daños de severidad ALTA en un rango de fechas con `$elemMatch` | SIRAV-26 (Jose David); el índice ya existe |
| Agregación 1: km y combustible promedio por categoría | SIRAV-26; usa `resumen` y `vehiculo.categoria` |
| Agregación 2: zonas de daño más frecuentes por mes (`$unwind` y `$group`) | SIRAV-26; usa `danos[]` |
| Agregación 3: incidencias por vehículo | SIRAV-26; usa `vehiculo.id_vehiculo` y `danos[]` |
