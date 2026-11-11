#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
backup_dir="backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
docker compose exec -T postgres pg_dump -U sirav_owner -d sirav_3fn -Fc > "$backup_dir/postgres.dump"
docker compose exec -T mongo sh -c 'mongodump --username root --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --db sirav_3fn --archive --gzip' > "$backup_dir/mongodb.archive.gz"
echo "Respaldos guardados en $backup_dir"
