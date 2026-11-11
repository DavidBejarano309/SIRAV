-- =====================================================================
-- SIRAV - Sistema Integral de Reservas y Alquiler de Vehículos
-- Script 02_insercion.sql  (SIRAV-17)
-- Motor: PostgreSQL 16 | Ejecutar después de 01_creacion.sql
-- Autores: David Bejarano, Jose David Rodriguez
--
-- Datos de demostración (valores en pesos colombianos, sin pagos reales):
--   - 3 roles y 8 usuarios (administrador, operadores y clientes)
--   - 12 clientes (5 con cuenta web, 7 registrados en mostrador)
--   - 5 categorías, 10 tarifas (histórica y vigente por categoría)
--   - 25 vehículos (5 por categoría)
--   - Historial: 8 alquileres cerrados con pagos y cargos, 1 reserva
--     cancelada, 1 alquiler activo y 3 reservas futuras
--   - 3 mantenimientos (finalizado, en curso y programado)
--
-- Contraseña de todos los usuarios de prueba: Sirav2026*
-- (hash BCrypt $2a$10$, compatible con Spring Security)
--
-- Se usan IDs explícitos para que las referencias sean legibles; al
-- final se ajustan las secuencias IDENTITY con setval.
--
-- Fechas relativas al día de ejecución (hora de Bogotá): el historial
-- queda en el pasado, el alquiler activo en curso y las reservas futuras
-- en el futuro, sin importar cuándo se cargue la base. Se usan dos
-- funciones temporales: pg_temp.dia(n) = hoy + n días y
-- pg_temp.momento(n, 'HH:MI') = hoy + n días a esa hora.
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO sirav, public;
SET TIME ZONE 'America/Bogota';

CREATE OR REPLACE FUNCTION pg_temp.dia(param_dias INTEGER) RETURNS DATE
LANGUAGE sql STABLE AS $$ SELECT CURRENT_DATE + param_dias $$;

CREATE OR REPLACE FUNCTION pg_temp.momento(param_dias INTEGER, param_hora TEXT) RETURNS TIMESTAMPTZ
LANGUAGE sql STABLE AS $$ SELECT (CURRENT_DATE + param_dias + param_hora::time)::timestamptz $$;

BEGIN;

-- ---------------------------------------------------------------------
-- Roles y usuarios
-- ---------------------------------------------------------------------
INSERT INTO rol (id_rol, nombre) VALUES
  (1, 'ADMINISTRADOR'),
  (2, 'OPERADOR'),
  (3, 'CLIENTE');

INSERT INTO usuario (id_usuario, nombre, apellido, email, password_hash, activo, creado_en) VALUES
  (1, 'David',    'Bejarano',  'admin@sirav.test',     '$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-100, '08:00')),
  (2, 'Jose',     'Rodriguez', 'operador1@sirav.test', '$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-100, '08:05')),
  (3, 'Laura',    'Gómez',     'operador2@sirav.test', '$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-100, '08:10')),
  (4, 'Ana',      'Pérez',     'ana.perez@correo.test',      '$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-90, '10:00')),
  (5, 'Carlos',   'Martínez',  'carlos.martinez@correo.test','$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-88, '11:30')),
  (6, 'Valentina','Rojas',     'valentina.rojas@correo.test','$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-85, '09:15')),
  (7, 'Andrés',   'Castro',    'andres.castro@correo.test',  '$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', TRUE, pg_temp.momento(-80, '16:45')),
  (8, 'Camila',   'Herrera',   'camila.herrera@correo.test', '$2a$10$5Yd9NGe359lmmNSw/xz2ZOqXdJlR9FJmo6VIpD.ozxxpBDVA3zUHe', FALSE,pg_temp.momento(-75, '14:20'));

-- Especialización superpuesta: el administrador también es operador
INSERT INTO usuario_rol (id_usuario, id_rol, asignado_en) VALUES
  (1, 1, pg_temp.momento(-100, '08:00')),
  (1, 2, pg_temp.momento(-100, '08:00')),
  (2, 2, pg_temp.momento(-100, '08:05')),
  (3, 2, pg_temp.momento(-100, '08:10')),
  (4, 3, pg_temp.momento(-90, '10:00')),
  (5, 3, pg_temp.momento(-88, '11:30')),
  (6, 3, pg_temp.momento(-85, '09:15')),
  (7, 3, pg_temp.momento(-80, '16:45')),
  (8, 3, pg_temp.momento(-75, '14:20'));

-- ---------------------------------------------------------------------
-- Clientes (1 a 5 con cuenta web; 6 a 12 sin cuenta)
-- ---------------------------------------------------------------------
INSERT INTO cliente (id_cliente, id_usuario, nombres, apellidos, documento, telefono, email, licencia_conduccion) VALUES
  (1,  4,    'Ana',       'Pérez',     '1010101010', '3001234567', 'ana.perez@correo.test',       'LC-1010101010'),
  (2,  5,    'Carlos',    'Martínez',  '1020202020', '3012345678', 'carlos.martinez@correo.test', 'LC-1020202020'),
  (3,  6,    'Valentina', 'Rojas',     '1030303030', '3023456789', 'valentina.rojas@correo.test', 'LC-1030303030'),
  (4,  7,    'Andrés',    'Castro',    '1040404040', '3034567890', 'andres.castro@correo.test',   'LC-1040404040'),
  (5,  8,    'Camila',    'Herrera',   '1050505050', '3045678901', 'camila.herrera@correo.test',  'LC-1050505050'),
  (6,  NULL, 'Juan',      'López',     '79111222',   '3101112233', 'juan.lopez@correo.test',      'LC-79111222'),
  (7,  NULL, 'María',     'Sánchez',   '52333444',   '3112223344', NULL,                          'LC-52333444'),
  (8,  NULL, 'Felipe',    'Ramírez',   '80555666',   '3123334455', 'felipe.ramirez@correo.test',  'LC-80555666'),
  (9,  NULL, 'Daniela',   'Torres',    '1060606060', '3134445566', NULL,                          'LC-1060606060'),
  (10, NULL, 'Santiago',  'Moreno',    '1070707070', '3145556677', 'santiago.moreno@correo.test', 'LC-1070707070'),
  (11, NULL, 'Paula',     'Vargas',    '1080808080', NULL,         'paula.vargas@correo.test',    'LC-1080808080'),
  (12, NULL, 'Ricardo',   'Díaz',      '19999888',   '3156667788', NULL,                          NULL);

-- ---------------------------------------------------------------------
-- Categorías y tarifas (histórica: hace 365 a 181 días; vigente: desde hace 180)
-- ---------------------------------------------------------------------
INSERT INTO categoria_vehiculo (id_categoria, nombre, descripcion) VALUES
  (1, 'ECONOMICO', 'Citadinos de bajo consumo, 4 pasajeros'),
  (2, 'COMPACTO',  'Hatchback y compactos, 5 pasajeros'),
  (3, 'SEDAN',     'Sedanes medianos con baúl amplio'),
  (4, 'SUV',       'Camionetas SUV 4x2 y 4x4, 5 a 7 pasajeros'),
  (5, 'CAMIONETA', 'Pick-up doble cabina para carga ligera');

INSERT INTO tarifa (id_tarifa, id_categoria, valor_diario, vigente_desde, vigente_hasta) VALUES
  (1,  1, 100000, pg_temp.dia(-365), pg_temp.dia(-181)),
  (2,  2, 130000, pg_temp.dia(-365), pg_temp.dia(-181)),
  (3,  3, 160000, pg_temp.dia(-365), pg_temp.dia(-181)),
  (4,  4, 210000, pg_temp.dia(-365), pg_temp.dia(-181)),
  (5,  5, 260000, pg_temp.dia(-365), pg_temp.dia(-181)),
  (6,  1, 110000, pg_temp.dia(-180), NULL),
  (7,  2, 140000, pg_temp.dia(-180), NULL),
  (8,  3, 170000, pg_temp.dia(-180), NULL),
  (9,  4, 230000, pg_temp.dia(-180), NULL),
  (10, 5, 280000, pg_temp.dia(-180), NULL);

-- ---------------------------------------------------------------------
-- Vehículos (estado coherente con el historial de abajo)
-- ---------------------------------------------------------------------
INSERT INTO vehiculo (id_vehiculo, id_categoria, placa, marca, modelo, anio, color, kilometraje_actual, estado_operativo) VALUES
  -- ECONOMICO
  (1,  1, 'JKL101', 'Renault',    'Kwid',      2024, 'Blanco', 15420, 'DISPONIBLE'),
  (2,  1, 'JKL102', 'Kia',        'Picanto',   2023, 'Rojo',   28310, 'DISPONIBLE'),
  (3,  1, 'JKL103', 'Chevrolet',  'Spark GT',  2022, 'Gris',   41200, 'DISPONIBLE'),
  (4,  1, 'JKL104', 'Suzuki',     'Swift',     2024, 'Azul',    9800, 'DISPONIBLE'),
  (5,  1, 'JKL105', 'Hyundai',    'Grand i10', 2023, 'Plata',  33650, 'MANTENIMIENTO'),
  -- COMPACTO
  (6,  2, 'MNP201', 'Mazda',      '2 Hatchback', 2024, 'Rojo',   12880, 'DISPONIBLE'),
  (7,  2, 'MNP202', 'Volkswagen', 'Polo',        2023, 'Negro',  24150, 'DISPONIBLE'),
  (8,  2, 'MNP203', 'Renault',    'Stepway',     2024, 'Naranja', 8700, 'RESERVADO'),
  (9,  2, 'MNP204', 'Kia',        'Rio',         2022, 'Blanco', 39400, 'DISPONIBLE'),
  (10, 2, 'MNP205', 'Chevrolet',  'Onix',        2025, 'Gris',    3100, 'DISPONIBLE'),
  -- SEDAN
  (11, 3, 'QRS301', 'Mazda',      '3 Sedán',     2024, 'Gris',   18900, 'DISPONIBLE'),
  (12, 3, 'QRS302', 'Toyota',     'Corolla',     2023, 'Blanco', 27560, 'DISPONIBLE'),
  (13, 3, 'QRS303', 'Nissan',     'Versa',       2024, 'Azul',   14200, 'DISPONIBLE'),
  (14, 3, 'QRS304', 'Volkswagen', 'Virtus',      2023, 'Plata',  22800, 'DISPONIBLE'),
  (15, 3, 'QRS305', 'Hyundai',    'Accent',      2022, 'Negro',  45100, 'INACTIVO'),
  -- SUV
  (16, 4, 'TUV401', 'Mazda',      'CX-5',        2024, 'Rojo',   21950, 'DISPONIBLE'),
  (17, 4, 'TUV402', 'Toyota',     'RAV4',        2023, 'Blanco', 22000, 'ENTREGADO'),
  (18, 4, 'TUV403', 'Kia',        'Sportage',    2024, 'Gris',   16300, 'DISPONIBLE'),
  (19, 4, 'TUV404', 'Renault',    'Duster',      2023, 'Café',   31800, 'DISPONIBLE'),
  (20, 4, 'TUV405', 'Chevrolet',  'Tracker',     2025, 'Azul',    5400, 'DISPONIBLE'),
  -- CAMIONETA
  (21, 5, 'XYZ501', 'Toyota',     'Hilux',       2024, 'Plata',  26750, 'DISPONIBLE'),
  (22, 5, 'XYZ502', 'Ford',       'Ranger',      2023, 'Negro',  34100, 'RESERVADO'),
  (23, 5, 'XYZ503', 'Nissan',     'Frontier',    2024, 'Blanco', 19800, 'DISPONIBLE'),
  (24, 5, 'XYZ504', 'Chevrolet',  'Colorado',    2022, 'Rojo',   52300, 'DISPONIBLE'),
  (25, 5, 'XYZ505', 'Mitsubishi', 'L200',        2023, 'Gris',   38900, 'DISPONIBLE');

-- ---------------------------------------------------------------------
-- Mantenimientos
-- ---------------------------------------------------------------------
INSERT INTO mantenimiento (id_mantenimiento, id_vehiculo, fecha_inicio, fecha_fin, descripcion, estado) VALUES
  (1, 1,  pg_temp.dia(-80), pg_temp.dia(-78), 'Cambio de aceite y filtros (15.000 km)',      'FINALIZADO'),
  (2, 5,  pg_temp.dia(-1),  pg_temp.dia(4), 'Revisión de frenos y cambio de pastillas',    'EN_CURSO'),
  (3, 18, pg_temp.dia(14),  pg_temp.dia(16), 'Alineación, balanceo y rotación de llantas',  'PROGRAMADO');

-- ---------------------------------------------------------------------
-- Reservas
-- Costo = días (fecha_fin - fecha_inicio) x tarifa diaria vigente.
-- Retraso (RN-04): 50 % de la tarifa diaria por cada día tarde.
-- ---------------------------------------------------------------------
INSERT INTO reserva (id_reserva, id_cliente, id_vehiculo, id_tarifa, fecha_inicio, fecha_fin, fecha_solicitud, estado) VALUES
  -- Historial cerrado
  (1,  1, 1,  6,  pg_temp.dia(-70), pg_temp.dia(-67), pg_temp.momento(-74, '10:12'), 'CERRADA'),
  (2,  2, 6,  7,  pg_temp.dia(-66), pg_temp.dia(-61), pg_temp.momento(-72, '15:40'), 'CERRADA'),
  (3,  3, 11, 8,  pg_temp.dia(-59), pg_temp.dia(-56), pg_temp.momento(-63, '09:05'), 'CERRADA'),
  (4,  4, 16, 9,  pg_temp.dia(-51), pg_temp.dia(-44), pg_temp.momento(-57, '18:22'), 'CERRADA'),
  (5,  6, 2,  6,  pg_temp.dia(-40), pg_temp.dia(-38), pg_temp.momento(-42, '11:00'), 'CERRADA'),
  (6,  7, 21, 10, pg_temp.dia(-36), pg_temp.dia(-31), pg_temp.momento(-41, '08:45'), 'CERRADA'),
  (7,  5, 7,  7,  pg_temp.dia(-29), pg_temp.dia(-27), pg_temp.momento(-32, '17:30'), 'CERRADA'),
  (8,  8, 12, 8,  pg_temp.dia(-26), pg_temp.dia(-21), pg_temp.momento(-31, '12:10'), 'CERRADA'),
  -- Cancelada (no bloquea el vehículo)
  (9,  9, 3,  6,  pg_temp.dia(-19), pg_temp.dia(-17), pg_temp.momento(-23, '14:00'), 'CANCELADA'),
  -- En curso
  (10, 1, 17, 9,  pg_temp.dia(-2), pg_temp.dia(3), pg_temp.momento(-6, '09:30'), 'ACTIVA'),
  -- Futuras
  (11, 2, 8,  7,  pg_temp.dia(2), pg_temp.dia(4), pg_temp.momento(-3, '16:15'), 'CONFIRMADA'),
  (12, 10,13, 8,  pg_temp.dia(9), pg_temp.dia(14), pg_temp.momento(-1, '19:50'), 'SOLICITADA'),
  (13, 3, 22, 10, pg_temp.dia(20), pg_temp.dia(24), pg_temp.momento(0, '08:20'), 'CONFIRMADA');

-- ---------------------------------------------------------------------
-- Alquileres (1:1 con la reserva)
-- ---------------------------------------------------------------------
INSERT INTO alquiler (id_alquiler, id_reserva, fecha_entrega, fecha_devolucion, km_salida, km_entrada,
                      combustible_salida, combustible_entrada, estado) VALUES
  (1,  1,  pg_temp.momento(-70, '09:00'), pg_temp.momento(-67, '17:00'), 15000, 15420, 100, 95,  'CERRADO'),
  (2,  2,  pg_temp.momento(-66, '08:30'), pg_temp.momento(-61, '18:10'), 12100, 12880, 100, 100, 'CERRADO'),
  (3,  3,  pg_temp.momento(-59, '10:00'), pg_temp.momento(-54, '12:30'), 18300, 18900, 100, 90,  'CERRADO'),  -- 2 días tarde
  (4,  4,  pg_temp.momento(-51, '07:45'), pg_temp.momento(-44, '19:00'), 20800, 21950, 100, 40,  'CERRADO'),  -- poco combustible
  (5,  5,  pg_temp.momento(-40, '09:15'), pg_temp.momento(-38, '16:40'), 28000, 28310, 100, 85,  'CERRADO'),
  (6,  6,  pg_temp.momento(-36, '08:00'), pg_temp.momento(-31, '17:20'), 25900, 26750, 100, 100, 'CERRADO'),  -- daño
  (7,  7,  pg_temp.momento(-29, '11:00'), pg_temp.momento(-27, '15:30'), 23900, 24150, 100, 90,  'CERRADO'),
  (8,  8,  pg_temp.momento(-26, '09:00'), pg_temp.momento(-21, '18:00'), 26900, 27560, 100, 100, 'CERRADO'),
  (9,  10, pg_temp.momento(-2, '08:40'),  NULL,                          22000, NULL,  100, NULL, 'ACTIVO');

-- ---------------------------------------------------------------------
-- Cargos adicionales
-- ---------------------------------------------------------------------
INSERT INTO cargo_adicional (id_cargo, id_alquiler, concepto, descripcion, monto, fecha_registro) VALUES
  (1, 3, 'RETRASO',     'Devolución 2 días tarde: 2 x 50 % de 170.000', 170000, pg_temp.momento(-54, '12:45')),
  (2, 4, 'COMBUSTIBLE', 'Entregado con 40 % de tanque',                  60000, pg_temp.momento(-44, '19:15')),
  (3, 6, 'DANO',        'Rayón en puerta trasera izquierda',            250000, pg_temp.momento(-31, '17:40'));

-- ---------------------------------------------------------------------
-- Pagos de demostración (alquiler + cargos)
-- ---------------------------------------------------------------------
INSERT INTO pago (id_pago, id_alquiler, fecha_pago, monto, tipo, estado) VALUES
  (1, 1, pg_temp.momento(-67, '17:10'),  330000, 'TARJETA',       'APROBADO'),  -- 3 x 110.000
  (2, 2, pg_temp.momento(-61, '18:20'),  700000, 'TRANSFERENCIA', 'APROBADO'),  -- 5 x 140.000
  (3, 3, pg_temp.momento(-54, '12:50'),  680000, 'TARJETA',       'APROBADO'),  -- 3 x 170.000 + 170.000
  (4, 4, pg_temp.momento(-44, '19:20'), 1670000, 'TARJETA',       'APROBADO'),  -- 7 x 230.000 + 60.000
  (5, 5, pg_temp.momento(-38, '16:50'),  220000, 'EFECTIVO',      'APROBADO'),  -- 2 x 110.000
  (6, 6, pg_temp.momento(-31, '17:45'), 1650000, 'TRANSFERENCIA', 'APROBADO'),  -- 5 x 280.000 + 250.000
  (7, 7, pg_temp.momento(-27, '15:40'),  280000, 'PRUEBA',        'APROBADO'),  -- 2 x 140.000
  (8, 8, pg_temp.momento(-21, '18:10'),  850000, 'PRUEBA',        'APROBADO');  -- 5 x 170.000

-- ---------------------------------------------------------------------
-- Auditoría inicial del historial (los triggers de 05_triggers.sql
-- registran los cambios posteriores automáticamente)
-- ---------------------------------------------------------------------
INSERT INTO auditoria_reserva (id_reserva, id_usuario, estado_anterior, estado_nuevo, fecha_evento, observacion)
SELECT r.id_reserva, 2, NULL, r.estado, r.fecha_solicitud, 'Carga inicial de datos de prueba'
FROM reserva r;

-- ---------------------------------------------------------------------
-- Ajuste de secuencias IDENTITY (por los IDs explícitos)
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('sirav.rol',                'id_rol'),           (SELECT max(id_rol)           FROM rol));
SELECT setval(pg_get_serial_sequence('sirav.usuario',            'id_usuario'),       (SELECT max(id_usuario)       FROM usuario));
SELECT setval(pg_get_serial_sequence('sirav.cliente',            'id_cliente'),       (SELECT max(id_cliente)       FROM cliente));
SELECT setval(pg_get_serial_sequence('sirav.categoria_vehiculo', 'id_categoria'),     (SELECT max(id_categoria)     FROM categoria_vehiculo));
SELECT setval(pg_get_serial_sequence('sirav.tarifa',             'id_tarifa'),        (SELECT max(id_tarifa)        FROM tarifa));
SELECT setval(pg_get_serial_sequence('sirav.vehiculo',           'id_vehiculo'),      (SELECT max(id_vehiculo)      FROM vehiculo));
SELECT setval(pg_get_serial_sequence('sirav.mantenimiento',      'id_mantenimiento'), (SELECT max(id_mantenimiento) FROM mantenimiento));
SELECT setval(pg_get_serial_sequence('sirav.reserva',            'id_reserva'),       (SELECT max(id_reserva)       FROM reserva));
SELECT setval(pg_get_serial_sequence('sirav.alquiler',           'id_alquiler'),      (SELECT max(id_alquiler)      FROM alquiler));
SELECT setval(pg_get_serial_sequence('sirav.cargo_adicional',    'id_cargo'),         (SELECT max(id_cargo)         FROM cargo_adicional));
SELECT setval(pg_get_serial_sequence('sirav.pago',               'id_pago'),          (SELECT max(id_pago)          FROM pago));

COMMIT;

-- Resumen de la carga
SELECT 'usuario' AS tabla, count(*) FROM usuario UNION ALL
SELECT 'cliente', count(*) FROM cliente UNION ALL
SELECT 'categoria_vehiculo', count(*) FROM categoria_vehiculo UNION ALL
SELECT 'tarifa', count(*) FROM tarifa UNION ALL
SELECT 'vehiculo', count(*) FROM vehiculo UNION ALL
SELECT 'reserva', count(*) FROM reserva UNION ALL
SELECT 'alquiler', count(*) FROM alquiler UNION ALL
SELECT 'pago', count(*) FROM pago UNION ALL
SELECT 'cargo_adicional', count(*) FROM cargo_adicional UNION ALL
SELECT 'mantenimiento', count(*) FROM mantenimiento UNION ALL
SELECT 'auditoria_reserva', count(*) FROM auditoria_reserva;
