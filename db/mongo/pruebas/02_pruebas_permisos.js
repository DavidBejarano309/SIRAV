// =====================================================================
// SIRAV - MongoDB | pruebas/02_pruebas_permisos.js  (evidencia SIRAV-25)
// Comprueba el mínimo privilegio de los usuarios de la base sirav.
// Requiere mongod con autorización activada (security.authorization).
// Uso (desde db/mongo; host y contraseñas por variable de entorno):
//   SIRAV_MONGO_HOST=localhost:27017 mongosh "<uri de administrador>" pruebas/02_pruebas_permisos.js
// 13 = Unauthorized. Cada línea debe empezar por OK.
// =====================================================================

const vv_host = process.env.SIRAV_MONGO_HOST || 'localhost:27017';
const vv_pwd_app = process.env.SIRAV_MONGO_APP_PWD || 'Sirav_Mongo_App_2026*';
const vv_pwd_rep = process.env.SIRAV_MONGO_REPORTES_PWD || 'Sirav_Mongo_Reportes_2026*';

const app = connect(`mongodb://sirav_app_mongo:${encodeURIComponent(vv_pwd_app)}@${vv_host}/sirav?authSource=sirav`);
const rep = connect(`mongodb://sirav_reportes_mongo:${encodeURIComponent(vv_pwd_rep)}@${vv_host}/sirav?authSource=sirav`);

let vn_ok = 0, vn_fallo = 0;
function verificar(param_caso, param_esperado, param_obtenido) {
  const vb_ok = JSON.stringify(param_esperado) === JSON.stringify(param_obtenido);
  vb_ok ? vn_ok++ : vn_fallo++;
  print(`${vb_ok ? 'OK   ' : 'FALLO'} | ${param_caso}  (esperado: ${JSON.stringify(param_esperado)}, obtenido: ${JSON.stringify(param_obtenido)})`);
}
function errorDe(param_fn) {
  try { param_fn(); return 'SIN_ERROR'; } catch (e) { return 'codigo ' + e.code; }
}

const vd_ts = new Date();
let vo_id_evento = null;

verificar('S1 App consulta inspecciones', 'SIN_ERROR', errorDe(() => app.inspecciones_vehiculo.find({ id_alquiler: 6 }).toArray()));
verificar('S2 App registra un evento en la bitácora', 'SIN_ERROR', errorDe(() => {
  vo_id_evento = app.bitacora_operaciones.insertOne({ fecha: vd_ts, count: 1, primer_ts: vd_ts, ultimo_ts: vd_ts,
    eventos: [{ tipo: 'LOGIN', ts: vd_ts, id_usuario: 2, detalle: { canal: 'prueba_permisos' } }] }).insertedId; }));
verificar('S3 App actualiza (corrige) una inspección', 'SIN_ERROR',
  errorDe(() => app.inspecciones_vehiculo.updateOne({ id_alquiler: 1, tipo: 'ENTREGA' }, { $set: { observaciones: 'Revisado' } })));
verificar('S4 App NO puede borrar inspecciones', 'codigo 13', errorDe(() => app.inspecciones_vehiculo.deleteMany({})));
verificar('S5 App NO puede eliminar la colección', 'codigo 13', errorDe(() => app.inspecciones_vehiculo.drop()));
verificar('S6 App NO puede crear colecciones nuevas', 'codigo 13', errorDe(() => app.createCollection('intrusa')));
verificar('S7 App NO puede cambiar el validador', 'codigo 13',
  errorDe(() => app.runCommand({ collMod: 'inspecciones_vehiculo', validator: {} }).ok || (() => { throw { code: 13 }; })()));
verificar('S8 App NO puede leer otras bases', 'codigo 13', errorDe(() => app.getSiblingDB('admin').system.users.find().toArray()));
verificar('S9 App NO puede crear usuarios', 'codigo 13', errorDe(() => app.createUser({ user: 'x', pwd: 'x', roles: [] })));
verificar('R1 Reportes consulta y agrega', 'SIN_ERROR', errorDe(() => rep.inspecciones_vehiculo.aggregate([{ $group: { _id: '$vehiculo.categoria' } }]).toArray()));
verificar('R2 Reportes NO puede insertar', 'codigo 13', errorDe(() => rep.bitacora_operaciones.insertOne({ fecha: vd_ts })));
verificar('R3 Reportes NO puede actualizar', 'codigo 13', errorDe(() => rep.inspecciones_vehiculo.updateOne({}, { $set: { observaciones: 'x' } })));

// Limpieza con el usuario administrador
const sirav = db.getSiblingDB('sirav');
if (vo_id_evento) sirav.bitacora_operaciones.deleteOne({ _id: vo_id_evento });
sirav.inspecciones_vehiculo.updateOne({ id_alquiler: 1, tipo: 'ENTREGA' }, { $unset: { observaciones: '' } });

print(`\nResultado: ${vn_ok} OK, ${vn_fallo} FALLO`);
if (vn_fallo > 0) quit(1);
