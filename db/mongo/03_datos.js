// =====================================================================
// SIRAV - MongoDB | 03_datos.js  (SIRAV-25)
// Datos de ejemplo enlazados con 02_insercion.sql de PostgreSQL: mismos
// id_alquiler, vehículos, km, combustible y fechas relativas a hoy.
//   - Inspecciones de entrega y devolución de los alquileres 1 a 8 (cerrados)
//   - Inspección de entrega del alquiler 9 (activo)
//   - Eventos de bitácora: sesiones, reservas, alquileres e inspecciones
// El daño del alquiler 6 (250.000) coincide con su cargo DANO en PostgreSQL.
// Uso (después de 01_colecciones.js, desde db/mongo):
//   mongosh "<uri de administrador>" 03_datos.js
// =====================================================================

load('00_comun.js');
load('02_crud.js');

// Vehículos de los alquileres (id_vehiculo, placa, categoría como en PostgreSQL)
const V = {
  1:  { id_vehiculo: 1,  placa: 'JKL101', categoria: 'ECONOMICO' },
  2:  { id_vehiculo: 2,  placa: 'JKL102', categoria: 'ECONOMICO' },
  6:  { id_vehiculo: 6,  placa: 'MNP201', categoria: 'COMPACTO' },
  7:  { id_vehiculo: 7,  placa: 'MNP202', categoria: 'COMPACTO' },
  11: { id_vehiculo: 11, placa: 'QRS301', categoria: 'SEDAN' },
  12: { id_vehiculo: 12, placa: 'QRS302', categoria: 'SEDAN' },
  16: { id_vehiculo: 16, placa: 'TUV401', categoria: 'SUV' },
  17: { id_vehiculo: 17, placa: 'TUV402', categoria: 'SUV' },
  21: { id_vehiculo: 21, placa: 'XYZ501', categoria: 'CAMIONETA' }
};

// id_alquiler, id_reserva, vehículo, entrega, devolución, inspector, daños
const ALQUILERES = [
  { a: 1, r: 1,  v: 1,  ent: [-70, '09:00', 15000, 100], dev: [-67, '17:00', 15420, 95],  insp: 2,
    danos_ent: [], danos_dev: [] },
  { a: 2, r: 2,  v: 6,  ent: [-66, '08:30', 12100, 100], dev: [-61, '18:10', 12880, 100], insp: 3,
    danos_ent: [{ zona: 'parachoques_trasero', severidad: 'BAJA', descripcion: 'Rayón leve preexistente' }],
    danos_dev: [{ zona: 'parachoques_trasero', severidad: 'BAJA', descripcion: 'Rayón leve preexistente' }] },
  { a: 3, r: 3,  v: 11, ent: [-59, '10:00', 18300, 100], dev: [-54, '12:30', 18900, 90],  insp: 2,
    danos_ent: [],
    danos_dev: [{ zona: 'rin', severidad: 'BAJA', descripcion: 'Raspón en rin delantero derecho', costo_estimado: 0 }],
    obs_dev: 'Devuelto 2 días después de la fecha pactada. Raspón por desgaste normal, no se cobra.' },
  { a: 4, r: 4,  v: 16, ent: [-51, '07:45', 20800, 100], dev: [-44, '19:00', 21950, 40],  insp: 3,
    danos_ent: [{ zona: 'espejo_der', severidad: 'BAJA', descripcion: 'Carcasa del espejo con rayón preexistente' }],
    danos_dev: [{ zona: 'espejo_der', severidad: 'BAJA', descripcion: 'Carcasa del espejo con rayón preexistente' }],
    obs_dev: 'Tanque al 40 %; se cobra combustible.' },
  { a: 5, r: 5,  v: 2,  ent: [-40, '09:15', 28000, 100], dev: [-38, '16:40', 28310, 85],  insp: 2,
    danos_ent: [], danos_dev: [] },
  { a: 6, r: 6,  v: 21, ent: [-36, '08:00', 25900, 100], dev: [-31, '17:20', 26750, 100], insp: 3,
    danos_ent: [],
    danos_dev: [{ zona: 'puerta_trasera_izq', severidad: 'ALTA', descripcion: 'Rayón profundo de 25 cm en la puerta trasera izquierda', costo_estimado: 250000 }],
    obs_dev: 'Daño reportado por el cliente al devolver. Se cobra según cotización de taller.' },
  { a: 7, r: 7,  v: 7,  ent: [-29, '11:00', 23900, 100], dev: [-27, '15:30', 24150, 90],  insp: 2,
    danos_ent: [],
    danos_dev: [{ zona: 'parabrisas', severidad: 'MEDIA', descripcion: 'Fisura de 3 cm por impacto de piedra', costo_estimado: 0 }],
    obs_dev: 'Impacto de piedra en carretera, no atribuible al cliente; se envía a revisión.' },
  { a: 8, r: 8,  v: 12, ent: [-26, '09:00', 26900, 100], dev: [-21, '18:00', 27560, 100], insp: 3,
    danos_ent: [], danos_dev: [] },
  { a: 9, r: 10, v: 17, ent: [-2, '08:40', 22000, 100],  dev: null, insp: 2,
    danos_ent: [{ zona: 'parachoques_delantero', severidad: 'BAJA', descripcion: 'Rayón leve preexistente' }] }
];

const sirav = db.getSiblingDB(SIRAV_DB_NOMBRE);
sirav.inspecciones_vehiculo.deleteMany({});
sirav.bitacora_operaciones.deleteMany({});

function evid(param_a, param_tipo, param_n) {
  return Array.from({ length: param_n }, (_, i) => `alq${param_a}_${param_tipo}_0${i + 1}.jpg`);
}

for (const x of ALQUILERES) {
  const vd_ent = momento(x.ent[0], x.ent[1]);
  registrarEvento('LOGIN', x.insp, { canal: 'web' }, new Date(vd_ent.getTime() - 15 * 60000));
  registrarEvento('ALQUILER_INICIADO', x.insp, { id_alquiler: x.a, id_reserva: x.r, id_vehiculo: x.v }, vd_ent);
  registrarInspeccion({
    tipo: 'ENTREGA', id_alquiler: x.a, vehiculo: V[x.v], fecha: new Date(vd_ent.getTime() + 5 * 60000),
    km: x.ent[2], combustible: x.ent[3], danos: x.danos_ent, evidencias: evid(x.a, 'ent', 2),
    id_usuario_inspector: x.insp
  });
  if (x.dev) {
    const vd_dev = momento(x.dev[0], x.dev[1]);
    const r_dev = {
      tipo: 'DEVOLUCION', id_alquiler: x.a, vehiculo: V[x.v], fecha: vd_dev,
      km: x.dev[2], combustible: x.dev[3], danos: x.danos_dev,
      evidencias: evid(x.a, 'dev', 2 + x.danos_dev.filter(d => d.costo_estimado !== undefined).length),
      id_usuario_inspector: x.insp
    };
    if (x.obs_dev) r_dev.observaciones = x.obs_dev;
    const vv_id = registrarInspeccion(r_dev);
    registrarEvento('ALQUILER_CERRADO', x.insp, { id_alquiler: x.a, id_inspeccion_devolucion: vv_id },
                    new Date(vd_dev.getTime() + 10 * 60000));
  }
}

// Reservas (mismos momentos de solicitud que 02_insercion.sql)
const RESERVAS = [[1, 1, -74, '10:12'], [2, 6, -72, '15:40'], [3, 11, -63, '09:05'], [4, 16, -57, '18:22'],
                  [5, 2, -42, '11:00'], [6, 21, -41, '08:45'], [7, 7, -32, '17:30'], [8, 12, -31, '12:10'],
                  [9, 3, -23, '14:00'], [10, 17, -6, '09:30'], [11, 8, -3, '16:15'], [12, 13, -1, '19:50'], [13, 22, 0, '08:20']];
for (const [vn_r, vn_v, vn_d, vv_h] of RESERVAS) {
  const vd_sol = momento(vn_d, vv_h);
  if (vd_sol > new Date()) continue;   // la de hoy puede ser posterior a la hora actual
  registrarEvento('RESERVA_CREADA', 2, { id_reserva: vn_r, id_vehiculo: vn_v }, vd_sol);
  if (![9, 12].includes(vn_r)) {
    registrarEvento('RESERVA_CONFIRMADA', 3, { id_reserva: vn_r }, new Date(vd_sol.getTime() + 3 * 3600000));
  }
}
registrarEvento('RESERVA_CANCELADA', 2, { id_reserva: 9, motivo: 'El cliente cambió de planes' }, momento(-21, '10:00'));

// Intentos rechazados e inicios de sesión fallidos (lo que pide la propuesta)
registrarEvento('RESERVA_RECHAZADA', 2, { id_vehiculo: 8, sqlstate: 'SR001', excepcion: 'e_reserva_solapada' }, momento(-2, '11:20'));
registrarEvento('RESERVA_RECHAZADA', 4, { id_vehiculo: 5, sqlstate: 'SR002', excepcion: 'e_mantenimiento_solapado' }, momento(-1, '09:05'));
registrarEvento('LOGIN_FALLIDO', null, { email: 'operador1@sirav.test', motivo: 'Contraseña incorrecta' }, momento(-5, '07:58'));
registrarEvento('LOGIN_FALLIDO', null, { email: 'desconocido@correo.test', motivo: 'Usuario inexistente' }, momento(-5, '08:01'));

print('Inspecciones: ' + sirav.inspecciones_vehiculo.countDocuments() +
      ' (entregas ' + sirav.inspecciones_vehiculo.countDocuments({ tipo: 'ENTREGA' }) +
      ', devoluciones ' + sirav.inspecciones_vehiculo.countDocuments({ tipo: 'DEVOLUCION' }) + ')');
print('Buckets de bitácora: ' + sirav.bitacora_operaciones.countDocuments() +
      ' con ' + sirav.bitacora_operaciones.aggregate([{ $group: { _id: null, n: { $sum: '$count' } } }]).toArray()[0].n + ' eventos');
