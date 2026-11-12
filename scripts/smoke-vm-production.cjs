const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const directory = path.resolve(process.argv[2]);
const base = new URL('http://192.168.1.18');
const values = Object.fromEntries(fs.readFileSync(path.join(root, '.env'), 'utf8').split(/\r?\n/).filter(l => /^[A-Z_]+=/.test(l)).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^['"]|['"]$/g, '')]; }));
let token;
const results = [];
async function request(route, method = 'GET', body) {
  const start = performance.now();
  const response = await fetch(new URL(route, base), {
    method, signal: AbortSignal.timeout(30000),
    headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  assert.equal(response.status, 200, `${method} ${route}: ${response.status}`);
  const data = await response.json();
  results.push({ route, status: response.status, ms: Math.round(performance.now() - start), ...(Array.isArray(data) ? { rows: data.length } : {}) });
  return data;
}
(async () => {
  let ready = false;
  for (let attempt = 0; attempt < 180; attempt++) {
    try {
      const response = await fetch(new URL('/actuator/health', base), { signal: AbortSignal.timeout(5000) });
      if (response.ok && (await response.json()).status === 'UP') { ready = true; break; }
    } catch {}
    if (attempt % 10 === 0) console.log('Esperando el arranque de la API actualizada...');
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
  assert(ready, 'La API no alcanzo el estado UP dentro del plazo de comprobacion');
  const login = await request('/api/auth/login', 'POST', { email: 'admin@sirav.local', password: values.DEMO_PASSWORD });
  token = login.token;
  const today = new Date();
  const from = new Date(today.getTime() - 30 * 86400000).toISOString().slice(0, 10);
  const to = new Date(today.getTime() + 86400000).toISOString().slice(0, 10);
  const dates = `?from=${from}&to=${to}`;
  await request('/api/auth/me');
  for (const route of ['/api/categories', '/api/clients', '/api/rates', '/api/maintenance', '/api/charges', '/api/users', '/api/inspections', '/api/inspections?severe=true', '/api/inspections/analytics', '/api/audit/reservations' + dates, '/api/audit/events' + dates]) await request(route);
  const vehicles = await request('/api/vehicles');
  assert(vehicles.length >= 25);
  const qfrom = new Date(today.getTime() + 5 * 86400000).toISOString().slice(0, 10);
  const qto = new Date(today.getTime() + 6 * 86400000).toISOString().slice(0, 10);
  await request(`/api/vehicles/${vehicles[0].id_vehiculo}/quote?from=${qfrom}&to=${qto}`);
  for (const report of ['occupancy', 'revenue', 'ranking', 'clients', 'late', 'availability']) await request('/api/reports/' + report + dates);
  const reservations = await request('/api/reservations');
  if (reservations.length) {
    await request(`/api/reservations/${reservations[0].id_reserva}`);
    await request(`/api/reservations/${reservations[0].id_reserva}/history`);
  }
  const rentals = await request('/api/rentals');
  if (rentals.length) {
    const id = rentals[0].id_alquiler;
    await request(`/api/rentals/${id}/payments`);
    await request(`/api/rentals/${id}/inspections`);
    const status = await request(`/api/rentals/${id}/inspection-status`);
    assert.equal(status.estado, 'DISPONIBLE');
  }
  for (let i = 0; i < 20; i++) {
    assert.equal((await request('/actuator/health')).status, 'UP');
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  fs.writeFileSync(path.join(directory, 'production-smoke.json'), JSON.stringify({ completed: new Date().toISOString(), result: 'PASS', url: base.origin, requests: results.length, healthChecks: 20, results }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', requests: results.length, healthChecks: 20, url: base.origin }));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
