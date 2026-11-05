-- =====================================================================
-- SIRAV - 01_pruebas_creacion.sql  (evidencia SIRAV-16 / SIRAV-18)
-- Ejecutar después de 01_creacion.sql. Cada prueba negativa debe fallar
-- con el nombre de la restricción indicada; todo se revierte al final.
-- =====================================================================
SET search_path TO sirav, public;
\set ON_ERROR_STOP off

BEGIN;

-- Datos mínimos
-- Sin IDs explícitos: con IDENTITY un id manual no avanza la secuencia
-- y el siguiente INSERT chocaría con la PK.
INSERT INTO categoria_vehiculo (nombre) VALUES ('ECONOMICO');
INSERT INTO tarifa (id_categoria, valor_diario, vigente_desde) VALUES (1, 120000, '2026-01-01');
INSERT INTO vehiculo (id_categoria, placa, marca, modelo, anio) VALUES (1, 'ABC123', 'Renault', 'Kwid', 2024);
INSERT INTO cliente (nombres, apellidos, documento) VALUES ('Ana', 'Pérez', '1000000001');
INSERT INTO reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin)
VALUES (1, 1, 1, '2026-12-01', '2026-12-05');

\echo '--- P1 (debe fallar ex_reserva_solapada): reserva solapada mismo vehículo'
SAVEPOINT s;
INSERT INTO reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin)
VALUES (1, 1, 1, '2026-12-04', '2026-12-08');
ROLLBACK TO s;

\echo '--- P2 (debe funcionar): misma franja pero la primera se cancela'
SAVEPOINT s;
UPDATE reserva SET estado = 'CANCELADA' WHERE id_reserva = 1;
INSERT INTO reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin)
VALUES (1, 1, 1, '2026-12-04', '2026-12-08');
\echo 'P2 OK'
ROLLBACK TO s;

\echo '--- P3 (debe fallar ck_reserva_fechas): fin antes de inicio'
SAVEPOINT s;
INSERT INTO reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin)
VALUES (1, 1, 1, '2026-12-20', '2026-12-10');
ROLLBACK TO s;

\echo '--- P4 (debe fallar ck_reserva_estado): estado inválido'
SAVEPOINT s;
UPDATE reserva SET estado = 'PERDIDA' WHERE id_reserva = 1;
ROLLBACK TO s;

\echo '--- P5 (debe fallar ex_tarifa_vigencia_solapada): dos tarifas vigentes'
SAVEPOINT s;
INSERT INTO tarifa (id_categoria, valor_diario, vigente_desde) VALUES (1, 130000, '2026-06-01');
ROLLBACK TO s;

\echo '--- P6 (debe fallar uq_alquiler_id_reserva): dos alquileres por reserva'
SAVEPOINT s;
INSERT INTO alquiler (id_reserva, km_salida, combustible_salida) VALUES (1, 1000, 100);
INSERT INTO alquiler (id_reserva, km_salida, combustible_salida) VALUES (1, 1000, 100);
ROLLBACK TO s;

\echo '--- P7 (debe fallar ck_alquiler_km): km de entrada menor que salida'
SAVEPOINT s;
INSERT INTO alquiler (id_reserva, km_salida, km_entrada, combustible_salida) VALUES (1, 1000, 900, 100);
ROLLBACK TO s;

\echo '--- P8 (debe fallar ck_alquiler_cierre): cerrar sin datos de devolución'
SAVEPOINT s;
INSERT INTO alquiler (id_reserva, km_salida, combustible_salida, estado) VALUES (1, 1000, 100, 'CERRADO');
ROLLBACK TO s;

\echo '--- P9 (debe fallar uq_vehiculo_placa): placa repetida'
SAVEPOINT s;
INSERT INTO vehiculo (id_categoria, placa, marca, modelo, anio) VALUES (1, 'ABC123', 'Kia', 'Picanto', 2023);
ROLLBACK TO s;

\echo '--- P10 (debe fallar fk_reserva_vehiculo): vehículo inexistente'
SAVEPOINT s;
INSERT INTO reserva (id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin)
VALUES (1, 999, 1, '2027-01-01', '2027-01-02');
ROLLBACK TO s;

\echo '--- P11 (debe fallar ck_pago_monto): pago con monto 0'
SAVEPOINT s;
INSERT INTO alquiler (id_reserva, km_salida, combustible_salida) VALUES (1, 1000, 100);
INSERT INTO pago (id_alquiler, monto, tipo)
VALUES ((SELECT id_alquiler FROM alquiler WHERE id_reserva = 1), 0, 'EFECTIVO');
ROLLBACK TO s;

ROLLBACK;
\echo '=== Fin de pruebas (todo revertido) ==='
