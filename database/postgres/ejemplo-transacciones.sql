-- Ejemplo educativo: ejecutar en una base de demostración ya inicializada.
-- Sustituir los IDs por datos válidos. Las fechas se calculan desde hoy.
BEGIN;
DO $$
DECLARE v_actor BIGINT; v_cliente BIGINT; v_vehiculo BIGINT;
BEGIN
 SELECT id_usuario INTO v_actor FROM usuario WHERE email='admin@sirav.local';
 SELECT id_cliente INTO v_cliente FROM cliente WHERE documento='DEMO-001';
 SELECT id_vehiculo INTO v_vehiculo FROM vehiculo WHERE placa='SIR301';
 CALL sp_crear_reserva(v_actor,v_cliente,v_vehiculo,current_date+200,current_date+202,gen_random_uuid());
END $$;
-- Demuestra que la reserva y su auditoría pertenecen a la misma transacción.
ROLLBACK;

BEGIN;
-- Ejemplo sin efectos: lectura coherente y confirmación explícita.
SELECT count(*) FROM reserva;
COMMIT;

-- La API aplica COMMIT/ROLLBACK a través de Spring @Transactional.
-- Un procedimiento invocado dentro de esa transacción no debe confirmar internamente.
