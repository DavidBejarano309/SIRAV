#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ]; then echo '.env ya existe; se conserva.'; exit 0; fi
umask 077
for key in POSTGRES_PASSWORD DB_PASSWORD MONGO_ROOT_PASSWORD MONGO_PASSWORD JWT_SECRET; do printf '%s=%s\n' "$key" "$(openssl rand -hex 24)"; done > .env
printf 'DEMO_PASSWORD=SiravDemo2026!\nSEED_DEMO=true\n' >> .env
echo 'Configuración creada; revisa .env antes del despliegue.'
