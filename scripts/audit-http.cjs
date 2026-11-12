const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, ''));
const base = new URL(process.argv[3] || 'http://192.168.1.18:8089');
assert.match(config.Database, /^sirav_audit_\d{14}$/);
assert.equal(base.port, '8089', 'Solo se permite el endpoint aislado de auditoria');
let token;
const report = { database: config.Database, url: base.origin, started: new Date().toISOString(), scenarios: [] };
const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms));
const today = (() => {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date()).map(p => [p.type, p.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
})();
const day = (offset) => { const date = new Date(today + 'T12:00:00Z'); date.setUTCDate(date.getUTCDate() + offset); return date.toISOString().slice(0, 10); };
async function request(route, method = 'GET', body, key = randomUUID()) {
  const started = performance.now();
  const response = await fetch(new URL('/api' + route, base), {
    method, signal: AbortSignal.timeout(60000),
    headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), 'Content-Type': 'application/json', 'Idempotency-Key': key },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let value;
  try { value = text ? JSON.parse(text) : null; } catch { value = { detail: 'Respuesta no JSON' }; }
  return { status: response.status, body: value, ms: Math.round(performance.now() - started) };
}
async function need(route, method, body, status = 200) {
  const response = await request(route, method, body);
  assert.equal(response.status, status, `${method || 'GET'} ${route}: ${response.status} ${response.body?.detail || ''}`);
  return response.body;
}
async function race(name, route, method, body, expected, key) {
  const started = performance.now();
  const responses = await Promise.all(Array.from({ length: 8 }, () => request(route, method, body, key || randomUUID())));
  const counts = {};
  for (const response of responses) counts[response.status] = (counts[response.status] || 0) + 1;
  assert.deepEqual(counts, expected, name);
  const times = responses.map(r => r.ms).sort((a, b) => a - b);
  const summary = { name, clients: 8, statuses: counts, elapsedMs: Math.round(performance.now() - started), p95Ms: times[Math.ceil(times.length * .95) - 1] };
  report.scenarios.push(summary);
  console.log(JSON.stringify(summary));
  return responses;
}
(async () => {
  token = (await need('/auth/login', 'POST', { email: 'admin@sirav.local', password: config.DEMO_PASSWORD })).token;
  const key = randomUUID().replaceAll('-', '');
  const category = await need('/categories', 'POST', { nombre: 'AUD-HTTP-' + key, descripcion: 'Auditoria concurrente aislada' });
  const rate = await need('/rates', 'POST', { idCategoria: category.id_categoria, valorDiario: 120000, vigenteDesde: '2020-01-01' });
  const vehicleInput = { idCategoria: category.id_categoria, placa: ('H' + key.slice(0, 11)).toUpperCase(), marca: 'AUDITORIA', modelo: 'HTTP', anio: 2025, kilometrajeActual: 1000, estadoOperativo: 'DISPONIBLE' };
  const vehicle = await need('/vehicles', 'POST', vehicleInput);
  await need(`/vehicles/${vehicle.id_vehiculo}`, 'PUT', { ...vehicleInput, modelo: 'HTTP verificado' });
  assert((await need('/categories')).some(c => c.id_categoria === category.id_categoria));
  assert((await need('/rates')).some(r => r.id_tarifa === rate.id_tarifa));
  const client = await need('/clients', 'POST', { nombres: 'Auditoria', apellidos: 'Concurrencia', documento: 'AHTTP' + key.slice(0, 20), licenciaConduccion: 'AUD-LIC' });
  const reservation = (from, to) => ({ idCliente: client.id_cliente, idVehiculo: vehicle.id_vehiculo, fechaInicio: from, fechaFin: to });
  for (let round = 0; round < 3; round++) {
    const replies = await race('reserva-mismo-vehiculo-' + (round + 1), '/reservations', 'POST', reservation(day(7 + round * 3), day(9 + round * 3)), { 201: 1, 409: 7 });
    const id = replies.find(r => r.status === 201).body.id_reserva;
    assert.equal((await request(`/vehicles/${vehicle.id_vehiculo}`, 'PUT', vehicleInput)).status, 409);
    assert.equal((await need(`/reservations/${id}`)).estado, 'SOLICITADA');
    await need(`/reservations/${id}/cancel`, 'POST', { motivo: 'AUDIT fin de ronda concurrente' }, 204);
  }
  const sameKey = randomUUID();
  const retries = await race('reintentos-idempotentes', '/reservations', 'POST', reservation(day(21), day(23)), { 201: 8 }, sameKey);
  const ids = new Set(retries.map(r => r.body.id_reserva));
  assert.equal(ids.size, 1);
  const retryId = [...ids][0];
  assert.equal((await need(`/reservations/${retryId}/history`)).length, 1);
  await need(`/reservations/${retryId}/cancel`, 'POST', { motivo: 'AUDIT fin de reintentos' }, 204);
  const active = await need('/reservations', 'POST', reservation(day(0), day(1)), 201);
  await need(`/reservations/${active.id_reserva}/confirm`, 'POST', undefined, 204);
  const handover = { kilometraje: 1000, combustible: 80, inspeccion: { danos: [], evidencias: [], observaciones: 'AUDIT HTTP simultaneo' } };
  const starts = await race('entrega-unica', `/reservations/${active.id_reserva}/start`, 'POST', handover, { 200: 1, 409: 7 });
  const rental = starts.find(r => r.status === 200).body.id_alquiler;
  // Use the same decoded image fixture as the Java and browser lifecycle tests.
  const image = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64');
  const form = new FormData();
  form.append('file', new Blob([image], { type: 'image/png' }), 'audit.png');
  const uploaded = await fetch(new URL(`/api/rentals/${rental}/evidence`, base), { method: 'POST', headers: { Authorization: 'Bearer ' + token }, body: form, signal: AbortSignal.timeout(60000) });
  assert.equal(uploaded.status, 201);
  const reference = (await uploaded.json()).referencia;
  const downloaded = await fetch(new URL(reference, base), { headers: { Authorization: 'Bearer ' + token } });
  assert.equal(downloaded.status, 200);
  assert(Buffer.from(await downloaded.arrayBuffer()).equals(image));
  const closes = await race('cierre-y-pago-unicos', `/rentals/${rental}/close`, 'POST', { ...handover, kilometraje: 1010 }, { 200: 1, 409: 7 });
  assert.equal(closes.filter(r => r.status === 200).length, 1);
  const payments = await need(`/rentals/${rental}/payments`);
  assert.equal(payments.pagos.length, 1);
  let inspections;
  for (let i = 0; i < 60; i++) {
    inspections = await need(`/rentals/${rental}/inspections`);
    if (inspections.length === 2) break;
    await pause(500);
  }
  assert.equal(inspections.length, 2);
  const original = inspections.find(d => d.tipo === 'ENTREGA');
  await race('correccion-mongo-version-unica', `/inspections/${original._id}`, 'PUT', { version: original.version, inspeccion: { danos: [{ zona: 'AUDIT HTTP', severidad: 'ALTA', descripcion: 'Correccion concurrente de prueba' }], evidencias: [], observaciones: 'AUDIT HTTP' } }, { 200: 1, 409: 7 });
  const corrected = (await need(`/rentals/${rental}/inspections`)).find(d => d.tipo === 'ENTREGA');
  assert.equal(corrected.version, 1);
  assert.equal(corrected.historial.length, 1);
  await race('anulacion-documental-unica', `/inspections/${original._id}`, 'DELETE', { motivo: 'AUDIT anulacion concurrente' }, { 204: 1, 404: 7 });
  const annulled = (await need(`/rentals/${rental}/inspections`)).find(d => d.tipo === 'ENTREGA');
  assert.equal(annulled.anulada, true);
  assert.equal(annulled.version, 2);
  assert.equal((await need(`/inspections?severe=true&vehicle=${vehicle.id_vehiculo}`)).length, 0);
  const maintenance = await need('/maintenance', 'POST', { idVehiculo: vehicle.id_vehiculo, fechaInicio: day(100), fechaFin: day(102), descripcion: 'AUDIT mantenimiento' });
  assert((await need('/maintenance')).some(m => m.id_mantenimiento === maintenance.id_mantenimiento));
  assert.equal((await need(`/vehicles/${vehicle.id_vehiculo}/quote?from=${day(100)}&to=${day(101)}`)).disponible, false);
  await need(`/maintenance/${maintenance.id_mantenimiento}`, 'PUT', { idVehiculo: vehicle.id_vehiculo, fechaInicio: day(102), fechaFin: day(104), descripcion: 'AUDIT reprogramado' });
  assert.equal((await need(`/vehicles/${vehicle.id_vehiculo}/quote?from=${day(100)}&to=${day(101)}`)).disponible, true);
  await need(`/maintenance/${maintenance.id_mantenimiento}`, 'PATCH', { estado: 'COMPLETADO' });
  assert.equal((await request(`/maintenance/${maintenance.id_mantenimiento}`, 'PATCH', { estado: 'CANCELADO' })).status, 409);
  assert.equal((await request(`/vehicles/${vehicle.id_vehiculo}`, 'PUT', { ...vehicleInput, kilometrajeActual: 1009 })).status, 409);
  await need(`/vehicles/${vehicle.id_vehiculo}`, 'PUT', { ...vehicleInput, kilometrajeActual: 1010, estadoOperativo: 'INACTIVO' });
  assert.equal((await need(`/vehicles/${vehicle.id_vehiculo}/quote?from=${day(100)}&to=${day(101)}`)).disponible, false);
  await need(`/vehicles/${vehicle.id_vehiculo}`, 'PUT', { ...vehicleInput, kilometrajeActual: 1010 });
  await need(`/rates/${rate.id_tarifa}/end`, 'PUT', { vigenteHasta: day(400) });
  await need('/rates', 'POST', { idCategoria: category.id_categoria, valorDiario: 130000, vigenteDesde: day(400) });
  assert.equal((await need(`/vehicles/${vehicle.id_vehiculo}/quote?from=${day(400)}&to=${day(401)}`)).total, 130000);
  report.health = [];
  for (let i = 0; i < 20; i++) {
    const started = performance.now();
    const response = await fetch(new URL('/actuator/health', base), { signal: AbortSignal.timeout(20000) });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).status, 'UP');
    report.health.push(Math.round(performance.now() - started));
    await pause(100);
  }
  report.completed = new Date().toISOString();
  report.parallelRequests = report.scenarios.reduce((sum, s) => sum + s.clients, 0);
  report.result = 'PASS';
  fs.writeFileSync(path.join(config.RunDirectory, 'http-concurrency.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ result: 'PASS', parallelRequests: report.parallelRequests, scenarios: report.scenarios.length, healthChecks: report.health.length }));
})().catch(error => {
  report.result = 'FAIL'; report.error = error.message;
  fs.writeFileSync(path.join(config.RunDirectory, 'http-concurrency.json'), JSON.stringify(report, null, 2));
  console.error(error.message); process.exitCode = 1;
});
