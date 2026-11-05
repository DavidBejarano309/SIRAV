#!/bin/bash
# =====================================================================
# SIRAV - Crea la base desde cero y ejecuta las pruebas.
# Uso (en la VM, como el usuario del sistema postgres):
#   sudo -u postgres ./ejecutar_todo.sh            # crea todo + pruebas
#   sudo -u postgres ./ejecutar_todo.sh --sin-pruebas
# Variables opcionales: PGDATABASE (por defecto sirav), PGHOST, PGPORT,
#   PWD_ADMIN, PWD_APP, PWD_REPORTES (contraseñas de 07_seguridad.sql)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
export PGDATABASE="${PGDATABASE:-sirav}"

if ! psql -X -d postgres -tAc "select 1 from pg_database where datname = '$PGDATABASE'" | grep -q 1; then
  echo ">> Creando base de datos $PGDATABASE"
  psql -X -d postgres -qc "CREATE DATABASE $PGDATABASE ENCODING 'UTF8' TEMPLATE template0"
fi

for script in 01_creacion 02_insercion 03_funciones 04_procedimientos 05_triggers 06_reportes; do
  echo ">> $script.sql"
  psql -X -q -v ON_ERROR_STOP=1 -f "$script.sql" > /dev/null
done
echo ">> 07_seguridad.sql"
psql -X -q -v ON_ERROR_STOP=1 \
  ${PWD_ADMIN:+-v pwd_admin="$PWD_ADMIN"} ${PWD_APP:+-v pwd_app="$PWD_APP"} ${PWD_REPORTES:+-v pwd_reportes="$PWD_REPORTES"} \
  -f 07_seguridad.sql > /dev/null

[ "${1:-}" = "--sin-pruebas" ] && { echo "Listo (sin pruebas)."; exit 0; }

echo; echo "===== Pruebas ====="
FALLOS=0
for prueba in pruebas/01_pruebas_creacion.sql pruebas/03_pruebas_funciones.sql pruebas/04_pruebas_procedimientos.sql \
              pruebas/05_pruebas_triggers.sql pruebas/07_pruebas_seguridad.sql; do
  SALIDA=$(psql -X -q -f "$prueba" 2>&1 || true)
  # Cuenta casos OK y, en 01, los rechazos esperados de cada restricción
  OK=$(grep -cE '\| OK$|OK +\||violates|P2 OK' <<< "$SALIDA" || true)
  F=$(grep -c 'FALLO' <<< "$SALIDA" || true)
  printf '%-42s casos OK: %3s   FALLO: %s\n' "$prueba" "$OK" "$F"
  FALLOS=$((FALLOS + F))
done
echo ">> pruebas/04_concurrencia_dos_sesiones.sh"
./pruebas/04_concurrencia_dos_sesiones.sh | tail -2

# Las pruebas revierten sus cambios; se recargan los datos para dejar la base limpia
for script in 01_creacion 02_insercion 03_funciones 04_procedimientos 05_triggers 06_reportes; do
  psql -X -q -v ON_ERROR_STOP=1 -f "$script.sql" > /dev/null
done
psql -X -q -v ON_ERROR_STOP=1 \
  ${PWD_ADMIN:+-v pwd_admin="$PWD_ADMIN"} ${PWD_APP:+-v pwd_app="$PWD_APP"} ${PWD_REPORTES:+-v pwd_reportes="$PWD_REPORTES"} \
  -f 07_seguridad.sql > /dev/null

echo; [ "$FALLOS" -eq 0 ] && echo "Todas las pruebas pasaron." || { echo "Hay $FALLOS pruebas con FALLO."; exit 1; }
