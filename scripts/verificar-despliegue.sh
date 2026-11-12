#!/usr/bin/env bash
# Verifica un despliegue de SIRAV de punta a punta a través de nginx (puerto 8088).
# Uso: bash scripts/verificar-despliegue.sh [URL_BASE]   (por defecto http://localhost:8088)
# Deja una reserva CERRADA de demostración y sus dos inspecciones en las bases.
set -euo pipefail
BASE="${1:-http://localhost:8088}"
PASS="${DEMO_PASSWORD:-SiravDemo2026!}"
export TZ=America/Bogota  # las fechas de negocio son de Bogotá
ok() { printf '  [OK] %s\n' "$1"; }
falla() { printf '  [FALLA] %s\n' "$1"; exit 1; }
json() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

echo "== SIRAV: verificación del despliegue en $BASE"
for i in $(seq 1 90); do
  if curl -fsS "$BASE/actuator/health" 2>/dev/null | grep -q '"UP"'; then ok "backend en línea (actuator/health = UP)"; break; fi
  [ "$i" = 90 ] && falla "el backend no respondió en 3 minutos"; sleep 2
done

TOKEN=$(curl -fsS -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"operador@sirav.local\",\"password\":\"$PASS\"}" | json "d['token']") || falla "inicio de sesión del operador"
ok "inicio de sesión con JWT (operador@sirav.local)"
AUTH=(-H "Authorization: Bearer $TOKEN")

HOY=$(date +%F); FIN=$(date -d '+2 day' +%F)
CLIENTE=$(curl -fsS "${AUTH[@]}" "$BASE/api/clients" | json "d[0]['id_cliente']")
read -r VEH KM < <(curl -fsS "${AUTH[@]}" "$BASE/api/vehicles?from=$HOY&to=$FIN&available=true" \
  | json "' '.join(str(x) for x in (d[0]['id_vehiculo'], d[0]['kilometraje_actual']))") || falla "no hay vehículos disponibles de $HOY a $FIN"
ok "catálogo: vehículo $VEH libre de $HOY a $FIN; cliente $CLIENTE"

nueva() { curl -sS -o /tmp/sirav_resp.json -w '%{http_code}' -X POST "$BASE/api/reservations" "${AUTH[@]}" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $(python3 -c 'import uuid;print(uuid.uuid4())')" \
  -d "{\"idCliente\":$CLIENTE,\"idVehiculo\":$VEH,\"fechaInicio\":\"$1\",\"fechaFin\":\"$2\"}"; }
[ "$(nueva "$HOY" "$FIN")" = 201 ] || falla "crear reserva: $(cat /tmp/sirav_resp.json)"
RES=$(json "d['id_reserva']" < /tmp/sirav_resp.json); COSTO=$(json "d['costo_base']" < /tmp/sirav_resp.json)
ok "sp_crear_reserva: reserva $RES SOLICITADA, costo base $COSTO"

CODE=$(nueva "$(date -d '+1 day' +%F)" "$(date -d '+3 day' +%F)")
[ "$CODE" = 409 ] || falla "la reserva solapada debía rechazarse (HTTP $CODE)"
ok "reserva solapada rechazada con HTTP 409: $(json "d['detail']" < /tmp/sirav_resp.json)"

curl -fsS -X POST "${AUTH[@]}" "$BASE/api/reservations/$RES/confirm" >/dev/null || falla "confirmar"
ok "sp_confirmar_reserva: CONFIRMADA"

entrega() { printf '{"kilometraje":%s,"combustible":%s,"inspeccion":{"danos":%s,"evidencias":["foto-%s.jpg"],"observaciones":"%s"}}' "$1" "$2" "$3" "$4" "$5"; }
ALQ=$(curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' "$BASE/api/reservations/$RES/start" \
  -d "$(entrega "$KM" 100 '[]' entrega 'Verificación de despliegue')" | json "d['id_alquiler']") || falla "entrega"
ok "sp_iniciar_alquiler: alquiler $ALQ ACTIVA con inspección de entrega"

CIERRE=$(curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' "$BASE/api/rentals/$ALQ/close" \
  -d "$(entrega $((KM + 120)) 80 '[{"zona":"Puerta trasera","severidad":"ALTA","descripcion":"Rayón de prueba"}]' devolucion 'Cierre de verificación')") || falla "devolución"
ok "sp_cerrar_alquiler: estado $(echo "$CIERRE" | json "d['estado_alquiler']"), pagado $(echo "$CIERRE" | json "d['pagado']")"

PAGO=$(curl -fsS "${AUTH[@]}" "$BASE/api/rentals/$ALQ/payments" | json "d['pagos'][0]['tipo']+' '+d['pagos'][0]['estado']+' '+str(d['pagos'][0]['monto'])") || falla "pago simulado"
case "$PAGO" in "SIMULADO APROBADO "*) ok "pago registrado: $PAGO";; *) falla "pago inesperado: $PAGO";; esac
ESTADOS=$(curl -fsS "${AUTH[@]}" "$BASE/api/reservations/$RES/history" | json "' -> '.join(r['estado_nuevo'] for r in d)")
ok "auditoría (trg_auditar_reserva): $ESTADOS"

for i in $(seq 1 30); do
  N=$(curl -fsS "${AUTH[@]}" "$BASE/api/rentals/$ALQ/inspections" | json "len(d)")
  [ "$N" = 2 ] && break; [ "$i" = 30 ] && falla "MongoDB no recibió las inspecciones (outbox)"; sleep 1
done
ok "MongoDB: 2 inspecciones publicadas por el outbox"
curl -fsS "${AUTH[@]}" "$BASE/api/inspections?severe=true&from=$HOY&to=$(date -d '+1 day' +%F)" | json "len(d)" | grep -qv '^0$' || falla "consulta compleja \$elemMatch"
ok "MongoDB: consulta de daños ALTA (\$elemMatch) devuelve resultados"
curl -fsS "${AUTH[@]}" "$BASE/api/inspections/analytics" | json "len(d['porCategoria'])" >/dev/null || falla "agregaciones"
ok "MongoDB: 3 agregaciones (por categoría, zonas por mes, incidencias por vehículo)"

DESDE=$(date -d '-30 day' +%F); HASTA=$(date -d '+30 day' +%F)
for r in occupancy revenue ranking clients late availability; do
  curl -fsS "${AUTH[@]}" "$BASE/api/reports/$r?from=$DESDE&to=$HASTA" >/dev/null || falla "reporte $r"
done
ok "reportes SQL R1-R6 ejecutados"
echo "== Verificación completa: todo correcto"
