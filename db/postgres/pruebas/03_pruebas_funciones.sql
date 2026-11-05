-- =====================================================================
-- SIRAV - 03_pruebas_funciones.sql  (evidencia SIRAV-19)
-- Ejecutar después de 01, 02 y 03. Casos con resultado esperado; cada
-- fila debe decir OK. No modifica datos.
-- =====================================================================
SET client_min_messages = warning;
SET search_path TO sirav, public;

-- Auxiliar de prueba: ejecuta una sentencia y devuelve el SQLSTATE del error
-- (o 'SIN_ERROR'). Vive en pg_temp, desaparece al cerrar la sesión.
CREATE OR REPLACE FUNCTION pg_temp.fn_sqlstate_de(param_sql TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE param_sql;
  RETURN 'SIN_ERROR';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$$;

WITH casos(caso, esperado, obtenido) AS (VALUES
  -- fn_vehiculo_disponible
  ('D1 Vehículo 4 libre en enero 2027',                 'true',  fn_vehiculo_disponible(4, '2027-01-10', '2027-01-12')::text),
  ('D2 Vehículo 8 con reserva CONFIRMADA 10-12 nov',    'false', fn_vehiculo_disponible(8, '2026-11-11', '2026-11-15')::text),
  ('D3 Solape solo en el borde (12 nov) también choca', 'false', fn_vehiculo_disponible(8, '2026-11-12', '2026-11-14')::text),
  ('D4 Vehículo 8 libre el día siguiente (13 nov)',     'true',  fn_vehiculo_disponible(8, '2026-11-13', '2026-11-15')::text),
  ('D5 Excluyendo su propia reserva (11) queda libre',  'true',  fn_vehiculo_disponible(8, '2026-11-10', '2026-11-12', 11)::text),
  ('D6 Reserva CANCELADA no bloquea (vehículo 3)',      'true',  fn_vehiculo_disponible(3, '2026-10-22', '2026-10-24')::text),
  ('D7 Reserva CERRADA no bloquea (vehículo 1)',        'true',  fn_vehiculo_disponible(1, '2026-09-02', '2026-09-03')::text),
  ('D8 Mantenimiento EN_CURSO bloquea (vehículo 5)',    'false', fn_vehiculo_disponible(5, '2026-11-08', '2026-11-10')::text),
  ('D9 Mantenimiento PROGRAMADO bloquea (vehículo 18)', 'false', fn_vehiculo_disponible(18, '2026-11-26', '2026-11-28')::text),
  ('D10 Vehículo INACTIVO nunca disponible (15)',       'false', fn_vehiculo_disponible(15, '2027-02-01', '2027-02-03')::text),
  ('D11 Alquiler ACTIVO bloquea (vehículo 17)',         'false', fn_vehiculo_disponible(17, '2026-11-05', '2026-11-06')::text),
  ('D12 Fechas invertidas -> e_parametro_invalido',     'SR007', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_vehiculo_disponible(4, '2027-01-12', '2027-01-10')$$)),
  ('D13 Vehículo inexistente -> e_registro_no_encontrado','SR008', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_vehiculo_disponible(999, '2027-01-10', '2027-01-12')$$)),
  -- fn_obtener_tarifa_vigente
  ('T1 Tarifa vigente ECONOMICO hoy = 6',               '6',     fn_obtener_tarifa_vigente(1, '2026-11-05')::text),
  ('T2 Tarifa histórica ECONOMICO en marzo = 1',        '1',     fn_obtener_tarifa_vigente(1, '2026-03-15')::text),
  ('T3 Sin tarifa en 2025 -> e_tarifa_no_vigente',      'SR006', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_obtener_tarifa_vigente(1, '2025-12-31')$$)),
  -- fn_calcular_costo (RN-04)
  ('C1 3 días x 110.000 = 330.000',                     '330000.00',  fn_calcular_costo(6, '2026-09-01', '2026-09-04')::text),
  ('C2 7 días x 230.000 = 1.610.000',                   '1610000.00', fn_calcular_costo(9, '2026-09-20', '2026-09-27')::text),
  ('C3 Mismo día se cobra 1 día = 280.000',             '280000.00',  fn_calcular_costo(10, '2026-12-01', '2026-12-01')::text),
  ('C4 Tarifa inexistente -> e_registro_no_encontrado', 'SR008', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_calcular_costo(999, '2026-12-01', '2026-12-02')$$)),
  -- fn_calcular_cargo_retraso (RN-04: 50 % por día)
  ('R1 Alquiler 3, 2 días tarde x 85.000 = 170.000',    '170000.00', fn_calcular_cargo_retraso(3)::text),
  ('R2 Alquiler 1 devuelto a tiempo = 0',               '0.00',      fn_calcular_cargo_retraso(1)::text),
  ('R3 Alquiler 9 (SUV) devuelto 10 nov: 2 x 115.000',  '230000.00', fn_calcular_cargo_retraso(9, '2026-11-10 10:00-05')::text),
  ('R4 Devolución 8 nov 23:30 Bogotá no es retraso',    '0.00',      fn_calcular_cargo_retraso(9, '2026-11-08 23:30-05')::text),
  ('R5 Alquiler inexistente -> e_registro_no_encontrado','SR008', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_calcular_cargo_retraso(999)$$))
)
SELECT caso, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'OK' ELSE 'FALLO' END AS resultado
FROM casos;
