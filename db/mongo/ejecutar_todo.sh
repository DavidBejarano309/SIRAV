#!/bin/bash
# =====================================================================
# SIRAV - MongoDB | Crea colecciones, usuarios y datos, y ejecuta las pruebas.
# Uso (en la VM, desde cualquier carpeta):
#   SIRAV_MONGO_ADMIN_URI='mongodb://admin:<clave>@localhost:27017/admin' ./ejecutar_todo.sh
#   ... ./ejecutar_todo.sh --sin-pruebas
# Variables opcionales:
#   SIRAV_MONGO_HOST          host:puerto para las pruebas de permisos (localhost:27017)
#   SIRAV_MONGO_APP_PWD       contraseña de sirav_app_mongo
#   SIRAV_MONGO_REPORTES_PWD  contraseña de sirav_reportes_mongo
# La prueba de permisos solo tiene sentido con autorización activada.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
: "${SIRAV_MONGO_ADMIN_URI:?Defina SIRAV_MONGO_ADMIN_URI con un usuario administrador}"

echo ">> 01_colecciones.js"; mongosh --quiet "$SIRAV_MONGO_ADMIN_URI" 01_colecciones.js
echo ">> 03_datos.js";       mongosh --quiet "$SIRAV_MONGO_ADMIN_URI" 03_datos.js

[ "${1:-}" = "--sin-pruebas" ] && { echo "Listo (sin pruebas)."; exit 0; }

echo; echo "===== Pruebas ====="
FALLOS=0
mongosh --quiet "$SIRAV_MONGO_ADMIN_URI" pruebas/01_pruebas_crud.js || FALLOS=$((FALLOS + 1))
echo
mongosh --quiet "$SIRAV_MONGO_ADMIN_URI" pruebas/02_pruebas_permisos.js || FALLOS=$((FALLOS + 1))

# Se recargan los datos para dejar la base limpia
mongosh --quiet "$SIRAV_MONGO_ADMIN_URI" 03_datos.js > /dev/null

echo; [ "$FALLOS" -eq 0 ] && echo "Todas las pruebas pasaron." || { echo "Hay archivos de prueba con FALLO."; exit 1; }
