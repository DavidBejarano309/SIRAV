#!/usr/bin/env bash
# Invoked over authenticated SSH by scripts/backup-vms.ps1; never prints credentials.
set -euo pipefail
umask 077
mode=${1:?}; id=${2:?}
[[ "$id" =~ ^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || exit 2
work="/home/sirav/sirav-backup-$id"
case "$mode" in
  check-web)
    systemctl is-active --quiet sirav-api.service
    test -d /opt/sirav/evidencias
    # Other application instances must not write during the maintenance window.
    if systemctl list-units --type=service --state=running --no-legend | grep -q 'sirav-audit-'; then
      echo 'Stop the temporary audit API before backing up.' >&2; exit 3
    fi
    ;;
  check-pg) docker exec sirav-postgres pg_isready -U sirav_owner -d sirav_3fn >/dev/null ;;
  check-mongo)
    docker exec sirav-mongo sh -c 'mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "if(db.adminCommand({ping:1}).ok!==1)quit(2)"' >/dev/null
    ;;
  pause)
    # Recovery even if the Windows process disappears. A late expiry invalidates the set.
    systemd-run --quiet --unit="sirav-backup-resume-$id" --on-active=30m /usr/bin/systemctl start sirav-api.service
    systemctl stop sirav-api.service
    ! systemctl is-active --quiet sirav-api.service
    ;;
  resume)
    systemctl start --no-block sirav-api.service
    systemctl stop "sirav-backup-resume-$id.timer" || true
    ;;
  pg)
    mkdir -m 700 "$work"
    docker exec sirav-postgres pg_dump -U sirav_owner -d sirav_3fn -Fc > "$work/postgres.dump"
    docker exec -i sirav-postgres pg_restore --list < "$work/postgres.dump" >/dev/null
    docker exec sirav-postgres pg_dumpall -U sirav_owner --roles-only --no-role-passwords > "$work/postgres-roles.sql"
    docker exec -i sirav-postgres sh > "$work/postgres-counts.tsv" <<'PG'
set -eu
query=$(psql -U sirav_owner -d sirav_3fn -Atc "SELECT string_agg(format('SELECT %L AS tabla, count(*) AS filas FROM %I.%I',tablename,schemaname,tablename), ' UNION ALL ' ORDER BY tablename) FROM pg_tables WHERE schemaname='public'")
psql -U sirav_owner -d sirav_3fn -At -F '|' -v ON_ERROR_STOP=1 -c "$query ORDER BY tabla"
PG
    chown -R sirav:sirav "$work"
    ;;
  mongo)
    mkdir -m 700 "$work"
    docker exec sirav-mongo sh -c 'mongodump --quiet --username root --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --db sirav_3fn --archive --gzip' > "$work/mongodb.archive.gz"
    docker exec sirav-mongo sh -c 'mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin sirav_3fn --eval '\''let out={}; for (let n of db.getCollectionNames().sort()) {out[n]={count:await db.getCollection(n).countDocuments({}),indexes:(await db.getCollection(n).getIndexes()).length};} print(JSON.stringify(out));'\''' > "$work/mongodb-counts.json"
    chown -R sirav:sirav "$work"
    ;;
  evidence)
    # A watchdog restart means the maintenance interval expired: fail, never publish.
    ! systemctl is-active --quiet sirav-api.service
    mkdir -m 700 "$work"
    tar -czf "$work/evidencias.tar.gz" -C /opt/sirav evidencias
    gzip -t "$work/evidencias.tar.gz"
    ! systemctl is-active --quiet sirav-api.service
    chown -R sirav:sirav "$work"
    ;;
  still-paused) ! systemctl is-active --quiet sirav-api.service ;;
  restore-prepare)
    mkdir -m 700 "$work"
    chown sirav:sirav "$work"
    ;;
  restore-pg)
    target="sirav_restore_${id//[-TZ]/}"
    docker exec sirav-postgres createdb -U sirav_owner -O sirav_owner "$target"
    docker exec -i sirav-postgres pg_restore -U sirav_owner -d "$target" --exit-on-error --single-transaction < "$work/postgres.dump"
    docker exec -i sirav-postgres sh -s -- "$target" > "$work/postgres-counts.tsv" <<'PG'
set -eu
target=$1
query=$(psql -U sirav_owner -d "$target" -Atc "SELECT string_agg(format('SELECT %L AS tabla, count(*) AS filas FROM %I.%I',tablename,schemaname,tablename), ' UNION ALL ' ORDER BY tablename) FROM pg_tables WHERE schemaname='public'")
psql -U sirav_owner -d "$target" -At -F '|' -v ON_ERROR_STOP=1 -c "$query ORDER BY tabla"
PG
    chown sirav:sirav "$work/postgres-counts.tsv"
    ;;
  restore-mongo)
    target="sirav_restore_${id//[-TZ]/}"
    # Refuse existing namespaces. Never use --drop or the production name.
    docker exec -i sirav-mongo sh -s -- "$target" "$work" <<'MG'
set -eu
target=$1
mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$target" --eval 'if(db.getCollectionNames().length!==0)quit(3)'
MG
    docker exec -i sirav-mongo sh -c 'exec mongorestore --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --stopOnError --nsInclude="sirav_3fn.*" --nsFrom="sirav_3fn.*" --nsTo="'"$target"'.*"' < "$work/mongodb.archive.gz"
    docker exec sirav-mongo sh -c 'mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin '"$target"' --eval '\''let out={}; for (let n of db.getCollectionNames().sort()) {out[n]={count:await db.getCollection(n).countDocuments({}),indexes:(await db.getCollection(n).getIndexes()).length};} print(JSON.stringify(out));'\''' > "$work/mongodb-counts.json"
    chown sirav:sirav "$work/mongodb-counts.json"
    ;;
  restore-evidence)
    # Verify compression and extract only below a fresh drill directory; reject links.
    gzip -t "$work/evidencias.tar.gz"
    tar -tzf "$work/evidencias.tar.gz" | awk '$0 !~ /^evidencias\// || $0 ~ /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}'
    if tar -tvzf "$work/evidencias.tar.gz" | grep -Eq '^[lh]'; then exit 4; fi
    mkdir -m 700 "$work/restored"
    tar -xzf "$work/evidencias.tar.gz" -C "$work/restored" --no-same-owner --no-same-permissions
    chown -R sirav:sirav "$work/restored"
    ;;
  cleanup)
    if test -d "$work" && ! test -L "$work"; then
      rm -f -- "$work/postgres.dump" "$work/postgres-roles.sql" "$work/postgres-counts.tsv" "$work/mongodb.archive.gz" "$work/mongodb-counts.json" "$work/evidencias.tar.gz"
      rmdir -- "$work"
    fi
    ;;
  *) exit 2 ;;
esac
