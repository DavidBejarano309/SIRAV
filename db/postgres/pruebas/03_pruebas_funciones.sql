-- =====================================================================
-- SIRAV - 03_pruebas_funciones.sql  (evidencia SIRAV-19)
-- Ejecutar después de 01, 02 y 03. Casos con resultado esperado; cada
-- fila debe decir OK. No modifica datos.
-- =====================================================================
SET client_min_messages = warning;
SET search_path TO sirav, public;
SET TIME ZONE 'America/Bogota';

-- Las fechas de los datos de prueba son relativas al día de ejecución
-- (ver 02_insercion.sql); los casos usan CURRENT_DATE + n con los mismos
-- desplazamientos.

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
  ('D1 Vehículo 4 libre en enero 2027',                 'true',  fn_vehiculo_disponible(4, CURRENT_DATE + 60, CURRENT_DATE + 62)::text),
  ('D2 Vehículo 8 con reserva CONFIRMADA (hoy+2 a hoy+4)', 'false', fn_vehiculo_disponible(8, CURRENT_DATE + 3, CURRENT_DATE + 7)::text),
  ('D3 Solape solo en el borde (hoy+4) también choca',   'false', fn_vehiculo_disponible(8, CURRENT_DATE + 4, CURRENT_DATE + 6)::text),
  ('D4 Vehículo 8 libre el día siguiente (hoy+5)',      'true',  fn_vehiculo_disponible(8, CURRENT_DATE + 5, CURRENT_DATE + 7)::text),
  ('D5 Excluyendo su propia reserva (11) queda libre',  'true',  fn_vehiculo_disponible(8, CURRENT_DATE + 2, CURRENT_DATE + 4, 11)::text),
  ('D6 Reserva CANCELADA no bloquea (vehículo 3)',      'true',  fn_vehiculo_disponible(3, CURRENT_DATE - 19, CURRENT_DATE - 17)::text),
  ('D7 Reserva CERRADA no bloquea (vehículo 1)',        'true',  fn_vehiculo_disponible(1, CURRENT_DATE - 69, CURRENT_DATE - 68)::text),
  ('D8 Mantenimiento EN_CURSO bloquea (vehículo 5)',    'false', fn_vehiculo_disponible(5, CURRENT_DATE + 3, CURRENT_DATE + 5)::text),
  ('D9 Mantenimiento PROGRAMADO bloquea (vehículo 18)', 'false', fn_vehiculo_disponible(18, CURRENT_DATE + 15, CURRENT_DATE + 17)::text),
  ('D10 Vehículo INACTIVO nunca disponible (15)',       'false', fn_vehiculo_disponible(15, CURRENT_DATE + 80, CURRENT_DATE + 82)::text),
  ('D14 Mantenimiento FINALIZADO no bloquea (vehículo 1)', 'true', fn_vehiculo_disponible(1, CURRENT_DATE - 79, CURRENT_DATE - 79)::text),
  ('D11 Alquiler ACTIVO bloquea (vehículo 17)',         'false', fn_vehiculo_disponible(17, CURRENT_DATE, CURRENT_DATE + 1)::text),
  ('D12 Fechas invertidas -> e_parametro_invalido',     'SR007', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_vehiculo_disponible(4, CURRENT_DATE + 62, CURRENT_DATE + 60)$$)),
  ('D13 Vehículo inexistente -> e_registro_no_encontrado','SR008', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_vehiculo_disponible(999, CURRENT_DATE + 60, CURRENT_DATE + 62)$$)),
  -- fn_obtener_tarifa_vigente
  ('T1 Tarifa vigente ECONOMICO hoy = 6',               '6',     fn_obtener_tarifa_vigente(1, CURRENT_DATE)::text),
  ('T2 Tarifa histórica ECONOMICO hace 200 días = 1',   '1',     fn_obtener_tarifa_vigente(1, CURRENT_DATE - 200)::text),
  ('T3 Sin tarifa hace 400 días -> e_tarifa_no_vigente', 'SR006', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_obtener_tarifa_vigente(1, CURRENT_DATE - 400)$$)),
  -- fn_calcular_costo (RN-04)
  ('C1 3 días x 110.000 = 330.000',                     '330000.00',  fn_calcular_costo(6, '2026-09-01', '2026-09-04')::text),
  ('C2 7 días x 230.000 = 1.610.000',                   '1610000.00', fn_calcular_costo(9, '2026-09-20', '2026-09-27')::text),
  ('C3 Mismo día se cobra 1 día = 280.000',             '280000.00',  fn_calcular_costo(10, '2026-12-01', '2026-12-01')::text),
  ('C4 Tarifa inexistente -> e_registro_no_encontrado', 'SR008', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_calcular_costo(999, '2026-12-01', '2026-12-02')$$)),
  -- fn_calcular_cargo_retraso (RN-04: 50 % por día)
  ('R1 Alquiler 3, 2 días tarde x 85.000 = 170.000',    '170000.00', fn_calcular_cargo_retraso(3)::text),
  ('R2 Alquiler 1 devuelto a tiempo = 0',               '0.00',      fn_calcular_cargo_retraso(1)::text),
  ('R3 Alquiler 9 (SUV) devuelto 2 días tarde: 2 x 115.000', '230000.00', fn_calcular_cargo_retraso(9, (CURRENT_DATE + 5 + time '10:00')::timestamptz)::text),
  ('R4 Devolución el día final a las 23:30 no es retraso', '0.00',  fn_calcular_cargo_retraso(9, (CURRENT_DATE + 3 + time '23:30')::timestamptz)::text),
  ('R5 Alquiler inexistente -> e_registro_no_encontrado','SR008', pg_temp.fn_sqlstate_de($$SELECT sirav.fn_calcular_cargo_retraso(999)$$))
)
SELECT caso, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'OK' ELSE 'FALLO' END AS resultado
FROM casos;
