// =====================================================================
// SIRAV - MongoDB | 02_crud.js  (SIRAV-25)
// Operaciones CRUD de inspecciones y registro de eventos en la bitácora.
// Es la lógica que replicará la aplicación Spring Boot (SIRAV-30).
//
//   C  registrarInspeccion(datos)            -> _id (texto)
//   R  consultarInspecciones(id_alquiler)    -> inspecciones VIGENTES
//      historialVehiculo(id_vehiculo)        -> inspecciones del vehículo
//   U  corregirInspeccion(id, cambios, id_usuario)
//   D  anularInspeccion(id, motivo, id_usuario)  (anulación lógica)
//      registrarEvento(tipo, id_usuario, detalle, ts)  (bitácora, Bucket)
//
// Uso: load('00_comun.js'); load('02_crud.js'); desde db/mongo.
// Errores: Error con mensaje que empieza por el nombre e_ de la excepción.
// =====================================================================

const siravCrud = db.getSiblingDB(SIRAV_DB_NOMBRE);

// ---------------------------------------------------------------------
// Bitácora (patrón Bucket): agrega el evento al bucket del día que aún
// tenga espacio; si no existe o está lleno, upsert crea uno nuevo.
// ---------------------------------------------------------------------
function registrarEvento(param_tipo, param_id_usuario, param_detalle, param_ts) {
  const vd_ts = param_ts || new Date();
  siravCrud.bitacora_operaciones.updateOne(
    { fecha: diaDe(vd_ts), count: { $lt: BITACORA_MAX_EVENTOS } },
    {
      $push: { eventos: { tipo: param_tipo, ts: vd_ts, id_usuario: param_id_usuario ?? null, detalle: param_detalle || {} } },
      $inc:  { count: 1 },
      $min:  { primer_ts: vd_ts },
      $max:  { ultimo_ts: vd_ts }
    },
    { upsert: true }
  );
}

function entregaVigente(param_id_alquiler) {
  return siravCrud.inspecciones_vehiculo.findOne({ id_alquiler: param_id_alquiler, tipo: 'ENTREGA', estado: 'VIGENTE' });
}

function devolucionVigente(param_id_alquiler) {
  return siravCrud.inspecciones_vehiculo.findOne({ id_alquiler: param_id_alquiler, tipo: 'DEVOLUCION', estado: 'VIGENTE' });
}

// Marca como nuevos los daños cuya zona no aparecía en la entrega
function marcarDanosNuevos(param_danos, param_entrega) {
  const r_zonas_previas = new Set((param_entrega.danos || []).map(d => d.zona));
  return (param_danos || []).map(d => Object.assign({}, d, { nuevo: d.nuevo ?? !r_zonas_previas.has(d.zona) }));
}

// ---------------------------------------------------------------------
// C: registrar una inspección de ENTREGA o DEVOLUCION
// ---------------------------------------------------------------------
function registrarInspeccion(param) {
  const r_doc = {
    tipo: param.tipo,
    id_alquiler: param.id_alquiler,
    vehiculo: param.vehiculo,
    fecha: param.fecha || new Date(),
    km: param.km,
    combustible: param.combustible,
    danos: (param.danos || []).map(d => Object.assign({ nuevo: false }, d)),
    evidencias: param.evidencias || [],
    id_usuario_inspector: param.id_usuario_inspector,
    estado: 'VIGENTE',
    version_esquema: 1
  };
  if (param.observaciones) r_doc.observaciones = param.observaciones;

  if (param.tipo === 'DEVOLUCION') {
    const r_entrega = entregaVigente(param.id_alquiler);
    if (!r_entrega) {
      throw new Error(`e_entrega_no_registrada: el alquiler ${param.id_alquiler} no tiene inspección de entrega vigente`);
    }
    if (param.km < r_entrega.km) {
      throw new Error(`e_parametro_invalido: km de devolución ${param.km} menor que el de entrega ${r_entrega.km}`);
    }
    if (param.vehiculo.id_vehiculo !== r_entrega.vehiculo.id_vehiculo) {
      throw new Error('e_parametro_invalido: el vehículo no coincide con el de la entrega');
    }
    r_doc.danos = marcarDanosNuevos(param.danos, r_entrega);
    r_doc.resumen = calcularResumen(r_entrega, r_doc);   // Computed
  }

  const r_res = siravCrud.inspecciones_vehiculo.insertOne(r_doc);
  registrarEvento('INSPECCION_REGISTRADA', param.id_usuario_inspector,
                  { id_alquiler: param.id_alquiler, tipo: param.tipo, id_inspeccion: r_res.insertedId.toString() },
                  r_doc.fecha);
  return r_res.insertedId.toString();
}

// ---------------------------------------------------------------------
// R: consultas
// ---------------------------------------------------------------------
function consultarInspecciones(param_id_alquiler, param_incluir_anuladas) {
  const r_filtro = { id_alquiler: param_id_alquiler };
  if (!param_incluir_anuladas) r_filtro.estado = 'VIGENTE';
  return siravCrud.inspecciones_vehiculo.find(r_filtro).sort({ fecha: 1 }).toArray();
}

function historialVehiculo(param_id_vehiculo) {
  return siravCrud.inspecciones_vehiculo
    .find({ 'vehiculo.id_vehiculo': param_id_vehiculo, estado: 'VIGENTE' },
          { tipo: 1, id_alquiler: 1, fecha: 1, km: 1, combustible: 1, danos: 1, resumen: 1 })
    .sort({ fecha: -1 }).toArray();
}

// ---------------------------------------------------------------------
// U: corregir una inspección vigente (daños, evidencias, observaciones,
// km o combustible). Recalcula el resumen que dependa de ella.
// ---------------------------------------------------------------------
function corregirInspeccion(param_id, param_cambios, param_id_usuario) {
  const vo_id = ObjectId(param_id);
  const r_actual = siravCrud.inspecciones_vehiculo.findOne({ _id: vo_id });
  if (!r_actual) throw new Error(`e_registro_no_encontrado: la inspección ${param_id} no existe`);
  if (r_actual.estado !== 'VIGENTE') throw new Error(`e_inspeccion_anulada: la inspección ${param_id} está anulada`);

  const r_permitidos = ['danos', 'evidencias', 'observaciones', 'km', 'combustible'];
  const r_set = {};
  for (const k of Object.keys(param_cambios)) {
    if (!r_permitidos.includes(k)) throw new Error(`e_parametro_invalido: el campo ${k} no se puede corregir`);
    r_set[k] = param_cambios[k];
  }
  if (r_set.danos) r_set.danos = r_set.danos.map(d => Object.assign({ nuevo: false }, d));

  const r_nuevo = Object.assign({}, r_actual, r_set);
  if (r_actual.tipo === 'DEVOLUCION') {
    const r_entrega = entregaVigente(r_actual.id_alquiler);
    if (param_cambios.danos) r_set.danos = r_nuevo.danos = marcarDanosNuevos(param_cambios.danos, r_entrega);
    r_set.resumen = calcularResumen(r_entrega, r_nuevo);
  }
  siravCrud.inspecciones_vehiculo.updateOne({ _id: vo_id, estado: 'VIGENTE' }, { $set: r_set });

  // Si se corrigió la entrega, el resumen de la devolución cambia
  if (r_actual.tipo === 'ENTREGA') {
    const r_dev = devolucionVigente(r_actual.id_alquiler);
    if (r_dev) {
      const r_entrega_nueva = Object.assign({}, r_actual, r_set);
      const r_danos = marcarDanosNuevos(r_dev.danos.map(d => { const c = Object.assign({}, d); delete c.nuevo; return c; }), r_entrega_nueva);
      siravCrud.inspecciones_vehiculo.updateOne(
        { _id: r_dev._id },
        { $set: { danos: r_danos, resumen: calcularResumen(r_entrega_nueva, Object.assign({}, r_dev, { danos: r_danos })) } }
      );
    }
  }

  registrarEvento('INSPECCION_CORREGIDA', param_id_usuario,
                  { id_inspeccion: param_id, campos: Object.keys(param_cambios) });
}

// ---------------------------------------------------------------------
// D: anular (borrado lógico). No se borra para conservar la trazabilidad.
// Una entrega no se anula mientras tenga una devolución vigente.
// ---------------------------------------------------------------------
function anularInspeccion(param_id, param_motivo, param_id_usuario) {
  const vo_id = ObjectId(param_id);
  const r_actual = siravCrud.inspecciones_vehiculo.findOne({ _id: vo_id });
  if (!r_actual) throw new Error(`e_registro_no_encontrado: la inspección ${param_id} no existe`);
  if (r_actual.estado !== 'VIGENTE') throw new Error(`e_inspeccion_anulada: la inspección ${param_id} ya está anulada`);
  if (r_actual.tipo === 'ENTREGA' && devolucionVigente(r_actual.id_alquiler)) {
    throw new Error('e_anulacion_invalida: primero se debe anular la devolución del mismo alquiler');
  }
  siravCrud.inspecciones_vehiculo.updateOne(
    { _id: vo_id, estado: 'VIGENTE' },
    { $set: { estado: 'ANULADA', anulacion: { motivo: param_motivo, fecha: new Date(), id_usuario: param_id_usuario } } }
  );
  registrarEvento('INSPECCION_ANULADA', param_id_usuario, { id_inspeccion: param_id, motivo: param_motivo });
}
