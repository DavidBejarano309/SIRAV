// =====================================================================
// SIRAV - MongoDB | 00_comun.js
// Constantes y funciones compartidas por los demás scripts de mongosh.
// Se carga con load('00_comun.js') desde la carpeta db/mongo.
// Autores: David Bejarano, Jose David Rodriguez
// =====================================================================

// Las pruebas definen SIRAV_DB_NOMBRE_PRUEBAS antes de cargar este archivo
// para trabajar en una base aparte que se borra al final.
const SIRAV_DB_NOMBRE = (typeof SIRAV_DB_NOMBRE_PRUEBAS !== 'undefined') ? SIRAV_DB_NOMBRE_PRUEBAS : 'sirav';

// Bucket: máximo de eventos por documento de bitácora (evita arrays sin límite)
const BITACORA_MAX_EVENTOS = 200;

const TIPOS_INSPECCION = ['ENTREGA', 'DEVOLUCION'];
const SEVERIDADES = ['BAJA', 'MEDIA', 'ALTA'];
const ZONAS = [
  'parachoques_delantero', 'parachoques_trasero', 'capo', 'techo', 'baul',
  'puerta_delantera_izq', 'puerta_delantera_der', 'puerta_trasera_izq', 'puerta_trasera_der',
  'guardabarros_delantero_izq', 'guardabarros_delantero_der', 'guardabarros_trasero_izq', 'guardabarros_trasero_der',
  'parabrisas', 'vidrio_lateral', 'espejo_izq', 'espejo_der', 'rin', 'llanta', 'tapiceria', 'tablero', 'otro'
];
const TIPOS_EVENTO = [
  'LOGIN', 'LOGIN_FALLIDO',
  'RESERVA_CREADA', 'RESERVA_RECHAZADA', 'RESERVA_CONFIRMADA', 'RESERVA_CANCELADA',
  'ALQUILER_INICIADO', 'ALQUILER_CERRADO',
  'INSPECCION_REGISTRADA', 'INSPECCION_CORREGIDA', 'INSPECCION_ANULADA'
];

// Fechas en hora de Bogotá (UTC-5, sin horario de verano), relativas a hoy,
// igual que pg_temp.dia(n) y pg_temp.momento(n, hora) de 02_insercion.sql.
const BOGOTA_OFFSET_HORAS = 5;

function hoyBogota() {
  const vd_ahora = new Date(Date.now() - BOGOTA_OFFSET_HORAS * 3600 * 1000);
  return { anio: vd_ahora.getUTCFullYear(), mes: vd_ahora.getUTCMonth(), dia: vd_ahora.getUTCDate() };
}

// Medianoche de Bogotá de hoy + param_dias
function dia(param_dias) {
  const h = hoyBogota();
  return new Date(Date.UTC(h.anio, h.mes, h.dia + param_dias, BOGOTA_OFFSET_HORAS, 0));
}

// Hoy + param_dias a la hora 'HH:MM' de Bogotá
function momento(param_dias, param_hora) {
  const h = hoyBogota();
  const [vn_hh, vn_mm] = param_hora.split(':').map(Number);
  return new Date(Date.UTC(h.anio, h.mes, h.dia + param_dias, vn_hh + BOGOTA_OFFSET_HORAS, vn_mm));
}

// Medianoche de Bogotá del día al que pertenece un instante (clave del bucket)
function diaDe(param_fecha) {
  const vd_local = new Date(param_fecha.getTime() - BOGOTA_OFFSET_HORAS * 3600 * 1000);
  return new Date(Date.UTC(vd_local.getUTCFullYear(), vd_local.getUTCMonth(), vd_local.getUTCDate(), BOGOTA_OFFSET_HORAS, 0));
}

// ---------------------------------------------------------------------
// Patrón Computed: resumen de la inspección de devolución, calculado al
// guardar a partir de la inspección de entrega del mismo alquiler.
// ---------------------------------------------------------------------
function calcularResumen(param_entrega, param_devolucion) {
  const vn_orden = { BAJA: 1, MEDIA: 2, ALTA: 3 };
  const r_nuevos = (param_devolucion.danos || []).filter(d => d.nuevo);
  let vv_maxima = null;
  for (const d of param_devolucion.danos || []) {
    if (vv_maxima === null || vn_orden[d.severidad] > vn_orden[vv_maxima]) vv_maxima = d.severidad;
  }
  return {
    total_danos: (param_devolucion.danos || []).length,
    danos_nuevos: r_nuevos.length,
    severidad_maxima: vv_maxima,
    km_recorridos: param_devolucion.km - param_entrega.km,
    combustible_consumido: param_entrega.combustible - param_devolucion.combustible,
    monto_danos_estimado: r_nuevos.reduce((s, d) => s + (d.costo_estimado || 0), 0)
  };
}
