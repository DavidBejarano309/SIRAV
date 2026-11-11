// =====================================================================
// SIRAV - MongoDB | pruebas/01_pruebas_crud.js  (evidencia SIRAV-25)
// Prueba validación, índices, CRUD, patrón Computed y patrón Bucket.
// Trabaja en la base sirav_pruebas (copia de colecciones, validadores e
// índices de sirav) y la borra al final. Cada línea debe empezar por OK.
// Uso (desde db/mongo, después de 01 y 03):
//   mongosh "<uri de administrador>" pruebas/01_pruebas_crud.js
// =====================================================================

const SIRAV_DB_NOMBRE_PRUEBAS = 'sirav_pruebas';
load('00_comun.js');
load('02_crud.js');

const real = db.getSiblingDB('sirav');
const prueba = db.getSiblingDB(SIRAV_DB_NOMBRE_PRUEBAS);
prueba.dropDatabase();

// Copiar colecciones con sus validadores e índices
for (const info of real.getCollectionInfos()) {
  prueba.createCollection(info.name, info.options);
  for (const ix of real.getCollection(info.name).getIndexes()) {
    if (ix.name === '_id_') continue;
    const r_opts = { name: ix.name };
    if (ix.unique) r_opts.unique = true;
    if (ix.partialFilterExpression) r_opts.partialFilterExpression = ix.partialFilterExpression;
    prueba.getCollection(info.name).createIndex(ix.key, r_opts);
  }
}

let vn_ok = 0, vn_fallo = 0;
function verificar(param_caso, param_esperado, param_obtenido) {
  const vb_ok = JSON.stringify(param_esperado) === JSON.stringify(param_obtenido);
  vb_ok ? vn_ok++ : vn_fallo++;
  print(`${vb_ok ? 'OK   ' : 'FALLO'} | ${param_caso}  (esperado: ${JSON.stringify(param_esperado)}, obtenido: ${JSON.stringify(param_obtenido)})`);
}
// Código de error de MongoDB o prefijo e_ del mensaje; 'SIN_ERROR' si no falla
function errorDe(param_fn) {
  try { param_fn(); return 'SIN_ERROR'; }
  catch (e) { return e.code ? 'codigo ' + e.code : e.message.split(':')[0]; }
}

const VEH = { id_vehiculo: 4, placa: 'JKL104', categoria: 'ECONOMICO' };
const base = (o) => Object.assign({
  tipo: 'ENTREGA', id_alquiler: 9001, vehiculo: VEH, fecha: momento(1, '09:00'), km: 9800, combustible: 100,
  danos: [], evidencias: ['p_ent_01.jpg'], id_usuario_inspector: 2, estado: 'VIGENTE', version_esquema: 1
}, o);
const insertarCrudo = (o) => () => prueba.inspecciones_vehiculo.insertOne(base(o));

// ---------------------------------------------------------------------
// 1. Validación $jsonSchema (121 = DocumentValidationFailure)
// ---------------------------------------------------------------------
verificar('V1 Tipo de inspección inválido', 'codigo 121', errorDe(insertarCrudo({ tipo: 'REVISION' })));
verificar('V2 Sin id_alquiler', 'codigo 121', errorDe(() => { const d = base({}); delete d.id_alquiler; prueba.inspecciones_vehiculo.insertOne(d); }));
verificar('V3 Combustible de 150 %', 'codigo 121', errorDe(insertarCrudo({ combustible: 150 })));
verificar('V4 Severidad de daño inválida', 'codigo 121', errorDe(insertarCrudo({ danos: [{ zona: 'capo', severidad: 'GRAVE', descripcion: 'Golpe', nuevo: false }] })));
verificar('V5 Zona de daño fuera del catálogo', 'codigo 121', errorDe(insertarCrudo({ danos: [{ zona: 'motor', severidad: 'BAJA', descripcion: 'Ruido', nuevo: false }] })));
verificar('V6 Placa con formato inválido', 'codigo 121', errorDe(insertarCrudo({ vehiculo: { id_vehiculo: 4, placa: 'jkl-104', categoria: 'ECONOMICO' } })));
verificar('V7 Polymorphic: DEVOLUCION sin resumen', 'codigo 121', errorDe(insertarCrudo({ tipo: 'DEVOLUCION' })));
verificar('V8 Polymorphic: ENTREGA con resumen', 'codigo 121', errorDe(insertarCrudo({
  resumen: { total_danos: 0, danos_nuevos: 0, severidad_maxima: null, km_recorridos: 0, combustible_consumido: 0, monto_danos_estimado: 0 } })));
verificar('V9 Evidencia que no es imagen (binarios no van en la base)', 'codigo 121', errorDe(insertarCrudo({ evidencias: ['video.mp4'] })));
verificar('V10 Campo no previsto en el esquema', 'codigo 121', errorDe(insertarCrudo({ precio: 1000 })));

// ---------------------------------------------------------------------
// 2. CRUD y patrón Computed
// ---------------------------------------------------------------------
verificar('C1 Devolución sin entrega -> e_entrega_no_registrada', 'e_entrega_no_registrada',
  errorDe(() => registrarInspeccion({ tipo: 'DEVOLUCION', id_alquiler: 9001, vehiculo: VEH, km: 10000, combustible: 80, id_usuario_inspector: 2 })));

const vv_ent = registrarInspeccion({
  tipo: 'ENTREGA', id_alquiler: 9001, vehiculo: VEH, fecha: momento(1, '09:00'), km: 9800, combustible: 100,
  danos: [{ zona: 'espejo_izq', severidad: 'BAJA', descripcion: 'Rayón preexistente' }],
  evidencias: ['p_ent_01.jpg'], id_usuario_inspector: 2 });
verificar('C2 Registrar entrega', 'VIGENTE', prueba.inspecciones_vehiculo.findOne({ _id: ObjectId(vv_ent) }).estado);

verificar('C3 Segunda entrega vigente del mismo alquiler -> índice único (11000)', 'codigo 11000',
  errorDe(() => registrarInspeccion({ tipo: 'ENTREGA', id_alquiler: 9001, vehiculo: VEH, km: 9800, combustible: 100, id_usuario_inspector: 2 })));
verificar('C4 Devolución con km menor que la entrega -> e_parametro_invalido', 'e_parametro_invalido',
  errorDe(() => registrarInspeccion({ tipo: 'DEVOLUCION', id_alquiler: 9001, vehiculo: VEH, km: 9000, combustible: 80, id_usuario_inspector: 2 })));

const vv_dev = registrarInspeccion({
  tipo: 'DEVOLUCION', id_alquiler: 9001, vehiculo: VEH, fecha: momento(4, '17:00'), km: 10350, combustible: 70,
  danos: [{ zona: 'espejo_izq', severidad: 'BAJA', descripcion: 'Rayón preexistente' },
          { zona: 'puerta_delantera_der', severidad: 'MEDIA', descripcion: 'Abolladura de 5 cm', costo_estimado: 180000 }],
  evidencias: ['p_dev_01.jpg', 'p_dev_02.jpg'], id_usuario_inspector: 3 });
const r_res = prueba.inspecciones_vehiculo.findOne({ _id: ObjectId(vv_dev) }).resumen;
verificar('C5 Computed: resumen calculado al guardar la devolución',
  { total_danos: 2, danos_nuevos: 1, severidad_maxima: 'MEDIA', km_recorridos: 550, combustible_consumido: 30, monto_danos_estimado: 180000 }, r_res);
verificar('C6 Daño en zona ya vista en la entrega queda como no nuevo', [false, true],
  prueba.inspecciones_vehiculo.findOne({ _id: ObjectId(vv_dev) }).danos.map(d => d.nuevo));

verificar('C7 Consultar inspecciones del alquiler', ['ENTREGA', 'DEVOLUCION'], consultarInspecciones(9001).map(i => i.tipo));
verificar('C8 Historial del vehículo (más reciente primero)', ['DEVOLUCION', 'ENTREGA'], historialVehiculo(4).map(i => i.tipo));

corregirInspeccion(vv_dev, {
  danos: [{ zona: 'espejo_izq', severidad: 'BAJA', descripcion: 'Rayón preexistente' },
          { zona: 'puerta_delantera_der', severidad: 'MEDIA', descripcion: 'Abolladura de 5 cm', costo_estimado: 180000 },
          { zona: 'llanta', severidad: 'ALTA', descripcion: 'Llanta trasera pinchada y cortada', costo_estimado: 320000 }],
  observaciones: 'Se agrega la llanta tras revisión en taller' }, 3);
verificar('C9 Corregir devolución recalcula el resumen', [3, 2, 'ALTA', 500000],
  (r => [r.total_danos, r.danos_nuevos, r.severidad_maxima, r.monto_danos_estimado])(prueba.inspecciones_vehiculo.findOne({ _id: ObjectId(vv_dev) }).resumen));

corregirInspeccion(vv_ent, { combustible: 90 }, 2);
verificar('C10 Corregir la entrega actualiza el resumen de la devolución', 20,
  prueba.inspecciones_vehiculo.findOne({ _id: ObjectId(vv_dev) }).resumen.combustible_consumido);

verificar('C11 Corregir un campo no permitido -> e_parametro_invalido', 'e_parametro_invalido',
  errorDe(() => corregirInspeccion(vv_dev, { id_alquiler: 1 }, 3)));
verificar('C12 Anular entrega con devolución vigente -> e_anulacion_invalida', 'e_anulacion_invalida',
  errorDe(() => anularInspeccion(vv_ent, 'Prueba', 3)));

anularInspeccion(vv_dev, 'Kilometraje mal digitado', 3);
verificar('C13 Anular devolución (borrado lógico)', ['ANULADA', 'Kilometraje mal digitado'],
  (d => [d.estado, d.anulacion.motivo])(prueba.inspecciones_vehiculo.findOne({ _id: ObjectId(vv_dev) })));
verificar('C14 La anulada no aparece en la consulta normal pero sí en el historial completo', [1, 2],
  [consultarInspecciones(9001).length, consultarInspecciones(9001, true).length]);
verificar('C15 Tras anular se puede registrar la devolución corregida', 'SIN_ERROR',
  errorDe(() => registrarInspeccion({ tipo: 'DEVOLUCION', id_alquiler: 9001, vehiculo: VEH, fecha: momento(4, '17:30'),
                                      km: 10530, combustible: 70, id_usuario_inspector: 3 })));
verificar('C16 Corregir una inspección anulada -> e_inspeccion_anulada', 'e_inspeccion_anulada',
  errorDe(() => corregirInspeccion(vv_dev, { observaciones: 'x' }, 3)));

// ---------------------------------------------------------------------
// 3. Patrón Bucket en la bitácora
// ---------------------------------------------------------------------
const vd_dia_prueba = dia(30);
for (let i = 0; i < BITACORA_MAX_EVENTOS + 5; i++) {
  registrarEvento('LOGIN', 2, { canal: 'prueba', n: i }, new Date(vd_dia_prueba.getTime() + (i + 1) * 60000));
}
verificar('B1 205 eventos del mismo día quedan en 2 buckets (200 + 5)', [200, 5],
  prueba.bitacora_operaciones.find({ fecha: vd_dia_prueba }).sort({ count: -1 }).toArray().map(b => b.count));
verificar('B2 El primer y último evento quedan registrados en el bucket', true,
  prueba.bitacora_operaciones.findOne({ fecha: vd_dia_prueba, count: 200 }).primer_ts.getTime() === vd_dia_prueba.getTime() + 60000);
verificar('B3 Un bucket no acepta más de 200 eventos (validación)', 'codigo 121',
  errorDe(() => prueba.bitacora_operaciones.updateOne({ fecha: vd_dia_prueba, count: 200 },
                 { $push: { eventos: { tipo: 'LOGIN', ts: new Date(), id_usuario: 2, detalle: {} } }, $inc: { count: 1 } })));
verificar('B4 Tipo de evento fuera del catálogo', 'codigo 121',
  errorDe(() => prueba.bitacora_operaciones.insertOne({ fecha: dia(31), count: 1, primer_ts: new Date(), ultimo_ts: new Date(),
                 eventos: [{ tipo: 'BORRADO_MASIVO', ts: new Date(), detalle: {} }] })));
verificar('B5 Las operaciones del CRUD quedaron en la bitácora',
  ['INSPECCION_ANULADA', 'INSPECCION_CORREGIDA', 'INSPECCION_REGISTRADA'],
  prueba.bitacora_operaciones.aggregate([{ $unwind: '$eventos' }, { $match: { 'eventos.tipo': /^INSPECCION/ } },
    { $group: { _id: '$eventos.tipo' } }, { $sort: { _id: 1 } }]).toArray().map(x => x._id));

// ---------------------------------------------------------------------
// 4. El modelo de la base real soporta las consultas de SIRAV-26
// ---------------------------------------------------------------------
verificar('Q1 $elemMatch: daños ALTA en los últimos 60 días -> alquiler 6', [6],
  real.inspecciones_vehiculo.find({ estado: 'VIGENTE', fecha: { $gte: dia(-60), $lte: dia(0) },
                                     danos: { $elemMatch: { severidad: 'ALTA', nuevo: true } } }).toArray().map(d => d.id_alquiler));
verificar('Q2 La consulta Q1 usa el índice ix_inspeccion_severidad_fecha', true,
  JSON.stringify(real.inspecciones_vehiculo.find({ fecha: { $gte: dia(-60) }, danos: { $elemMatch: { severidad: 'ALTA' } } })
                 .explain().queryPlanner.winningPlan).includes('ix_inspeccion_severidad_fecha'));
verificar('Q3 Promedio por categoría posible sin consultar PostgreSQL (5 categorías)', 5,
  real.inspecciones_vehiculo.aggregate([{ $match: { tipo: 'DEVOLUCION', estado: 'VIGENTE' } },
    { $group: { _id: '$vehiculo.categoria', km: { $avg: '$resumen.km_recorridos' } } }]).toArray().length);
verificar('Q4 Datos enlazados: alquileres 1 a 9 con entrega y 1 a 8 con devolución', [9, 8],
  [real.inspecciones_vehiculo.distinct('id_alquiler', { tipo: 'ENTREGA' }).length,
   real.inspecciones_vehiculo.distinct('id_alquiler', { tipo: 'DEVOLUCION' }).length]);

prueba.dropDatabase();
print(`\nResultado: ${vn_ok} OK, ${vn_fallo} FALLO`);
if (vn_fallo > 0) quit(1);
