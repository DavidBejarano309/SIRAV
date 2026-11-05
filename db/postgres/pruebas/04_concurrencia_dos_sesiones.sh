#!/bin/bash
# =====================================================================
# SIRAV - Prueba de concurrencia con dos sesiones (SIRAV-20, apoya SIRAV-18/33)
# Dos clientes intentan reservar el mismo vehículo y las mismas fechas a la vez.
#   Sesión A: crea la reserva y mantiene la transacción abierta 3 s.
#   Sesión B: arranca 1 s después; queda esperando el bloqueo FOR UPDATE
#             del vehículo y, cuando A confirma, recibe e_reserva_solapada.
# Uso: PGHOST=... PGPORT=... PGUSER=... PGDATABASE=sirav ./04_concurrencia_dos_sesiones.sh
# No deja datos: al final borra la reserva de la sesión A.
# =====================================================================
set -u
VEH=10
INI=$(psql -X -tAc "select (now() at time zone 'America/Bogota')::date + 90")
FIN=$(psql -X -tAc "select (now() at time zone 'America/Bogota')::date + 92")

echo "Vehículo $VEH, del $INI al $FIN"

psql -X -q -v ON_ERROR_STOP=1 <<SQL > /tmp/sirav_sesion_a.log 2>&1 &
SET search_path TO sirav, public;
BEGIN;
SELECT 'A inicia ' || clock_timestamp()::time(0);
CALL sp_crear_reserva(1, $VEH, '$INI', '$FIN', 2);
SELECT 'A reservó; mantiene la transacción abierta 3 s';
SELECT pg_sleep(3);
COMMIT;
SELECT 'A confirma (COMMIT) ' || clock_timestamp()::time(0);
SQL
PID_A=$!

sleep 1
psql -X -q <<SQL > /tmp/sirav_sesion_b.log 2>&1 &
SET search_path TO sirav, public;
SELECT 'B inicia ' || clock_timestamp()::time(0) || ' (A aún no confirma)';
\set VERBOSITY verbose
CALL sp_crear_reserva(2, $VEH, '$INI', '$FIN', 2);
SELECT 'B termina ' || clock_timestamp()::time(0);
SQL
PID_B=$!

wait $PID_A $PID_B
echo "----- Sesión A -----"; grep -v '^$\|^-\|row' /tmp/sirav_sesion_a.log
echo "----- Sesión B -----"; grep -v '^$\|^-\|row' /tmp/sirav_sesion_b.log
echo "----- Reservas vigentes del vehículo $VEH en esas fechas (debe ser 1) -----"
psql -X -tAc "select count(*) from sirav.reserva where id_vehiculo = $VEH and fecha_inicio = '$INI' and estado <> 'CANCELADA'"

# Limpieza
psql -X -qc "delete from sirav.auditoria_reserva where id_reserva in (select id_reserva from sirav.reserva where id_vehiculo = $VEH and fecha_inicio = '$INI');
             delete from sirav.reserva where id_vehiculo = $VEH and fecha_inicio = '$INI';"
