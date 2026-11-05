-- =====================================================================
-- SIRAV - Sistema Integral de Reservas y Alquiler de Vehículos
-- Script 05_triggers.sql  (SIRAV-21)
-- Motor: PostgreSQL 16 (PL/pgSQL) | Ejecutar después de 04_procedimientos.sql
-- Autores: David Bejarano, Jose David Rodriguez
--
-- Triggers de la propuesta:
--   trg_validar_transicion_reserva  RN-03  orden de estados de la reserva
--   trg_validar_mantenimiento       RN-02  reservas y mantenimientos no se cruzan
--   trg_auditar_reserva                    historial en auditoria_reserva
--   trg_actualizar_estado_vehiculo         sincroniza vehiculo.estado_operativo
--
-- Los triggers protegen las reglas aunque alguien escriba directamente en
-- las tablas sin pasar por los sp_. Las funciones de trigger llevan el
-- prefijo fn_trg_.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_min_messages = warning;
SET search_path TO sirav, public;

-- =====================================================================
-- 1. RN-03: transiciones válidas de la reserva
--    SOLICITADA -> CONFIRMADA -> ACTIVA -> CERRADA
--    SOLICITADA | CONFIRMADA -> CANCELADA
--    Toda reserva nueva nace SOLICITADA.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_trg_validar_transicion_reserva()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vb_valida BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'SOLICITADA' THEN
      RAISE EXCEPTION 'e_transicion_invalida: una reserva nueva debe crearse SOLICITADA, no %', NEW.estado
        USING ERRCODE = 'SR003';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.estado = OLD.estado THEN
    RETURN NEW;
  END IF;

  vb_valida := (OLD.estado, NEW.estado) IN (
    ('SOLICITADA', 'CONFIRMADA'),
    ('CONFIRMADA', 'ACTIVA'),
    ('ACTIVA',     'CERRADA'),
    ('SOLICITADA', 'CANCELADA'),
    ('CONFIRMADA', 'CANCELADA')
  );

  IF NOT vb_valida THEN
    RAISE EXCEPTION 'e_transicion_invalida: la reserva % no puede pasar de % a %',
      OLD.id_reserva, OLD.estado, NEW.estado
      USING ERRCODE = 'SR003';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_transicion_reserva
  BEFORE INSERT OR UPDATE OF estado ON reserva
  FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_transicion_reserva();

-- =====================================================================
-- 2. RN-02: una reserva vigente y un mantenimiento activo del mismo
--    vehículo no pueden coincidir en fechas. Se valida desde ambos lados.
-- =====================================================================

-- 2a. Al crear o reprogramar una reserva vigente
CREATE OR REPLACE FUNCTION fn_trg_validar_mantenimiento_reserva()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.estado NOT IN ('SOLICITADA', 'CONFIRMADA', 'ACTIVA') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM mantenimiento m
     WHERE m.id_vehiculo = NEW.id_vehiculo
       AND m.estado IN ('PROGRAMADO', 'EN_CURSO')
       AND daterange(m.fecha_inicio, m.fecha_fin, '[]') && daterange(NEW.fecha_inicio, NEW.fecha_fin, '[]')
  ) THEN
    RAISE EXCEPTION 'e_mantenimiento_solapado: el vehículo % tiene mantenimiento entre % y %',
      NEW.id_vehiculo, NEW.fecha_inicio, NEW.fecha_fin
      USING ERRCODE = 'SR002';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_mantenimiento
  BEFORE INSERT OR UPDATE OF id_vehiculo, fecha_inicio, fecha_fin ON reserva
  FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_mantenimiento_reserva();

-- 2b. Al programar o mover un mantenimiento
CREATE OR REPLACE FUNCTION fn_trg_validar_mantenimiento()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vn_id_reserva reserva.id_reserva%TYPE;
BEGIN
  IF NEW.estado NOT IN ('PROGRAMADO', 'EN_CURSO') THEN
    RETURN NEW;
  END IF;

  SELECT r.id_reserva INTO vn_id_reserva
    FROM reserva r
   WHERE r.id_vehiculo = NEW.id_vehiculo
     AND r.estado IN ('SOLICITADA', 'CONFIRMADA', 'ACTIVA')
     AND daterange(r.fecha_inicio, r.fecha_fin, '[]') && daterange(NEW.fecha_inicio, NEW.fecha_fin, '[]')
   LIMIT 1;

  IF vn_id_reserva IS NOT NULL THEN
    RAISE EXCEPTION 'e_mantenimiento_solapado: el vehículo % tiene la reserva % en esas fechas; reprograme el mantenimiento',
      NEW.id_vehiculo, vn_id_reserva
      USING ERRCODE = 'SR002';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_mantenimiento
  BEFORE INSERT OR UPDATE OF id_vehiculo, fecha_inicio, fecha_fin, estado ON mantenimiento
  FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_mantenimiento();

-- =====================================================================
-- 3. Auditoría de reservas
--    Registra la creación y cada cambio de estado. El usuario y la
--    observación llegan por las variables de sesión que publican los sp_
--    (sirav.id_usuario, sirav.observacion).
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_trg_auditar_reserva()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vn_id_usuario  BIGINT := NULLIF(current_setting('sirav.id_usuario', TRUE), '')::BIGINT;
  vv_observacion TEXT   := NULLIF(current_setting('sirav.observacion', TRUE), '');
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.estado = OLD.estado THEN
    RETURN NULL;
  END IF;

  INSERT INTO auditoria_reserva (id_reserva, id_usuario, estado_anterior, estado_nuevo, observacion)
  VALUES (NEW.id_reserva,
          vn_id_usuario,
          CASE WHEN TG_OP = 'UPDATE' THEN OLD.estado END,
          NEW.estado,
          COALESCE(vv_observacion, 'Cambio directo en la tabla (' || current_user || ')'));

  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_auditar_reserva
  AFTER INSERT OR UPDATE OF estado ON reserva
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar_reserva();

-- =====================================================================
-- 4. Estado operativo del vehículo
--    Se recalcula desde los datos, en este orden de prioridad:
--      INACTIVO (lo fija el administrador y no se toca)
--      ENTREGADO      si tiene una reserva ACTIVA
--      MANTENIMIENTO  si tiene un mantenimiento EN_CURSO
--      RESERVADO      si tiene una reserva CONFIRMADA que no ha terminado
--      DISPONIBLE     en otro caso
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_estado_vehiculo_calculado(param_id_vehiculo BIGINT)
RETURNS VARCHAR
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  vd_hoy    DATE := (now() AT TIME ZONE 'America/Bogota')::date;
  vv_actual vehiculo.estado_operativo%TYPE;
BEGIN
  SELECT estado_operativo INTO vv_actual FROM vehiculo WHERE id_vehiculo = param_id_vehiculo;

  IF vv_actual = 'INACTIVO' THEN
    RETURN 'INACTIVO';
  ELSIF EXISTS (SELECT 1 FROM reserva WHERE id_vehiculo = param_id_vehiculo AND estado = 'ACTIVA') THEN
    RETURN 'ENTREGADO';
  ELSIF EXISTS (SELECT 1 FROM mantenimiento WHERE id_vehiculo = param_id_vehiculo AND estado = 'EN_CURSO') THEN
    RETURN 'MANTENIMIENTO';
  ELSIF EXISTS (SELECT 1 FROM reserva WHERE id_vehiculo = param_id_vehiculo
                  AND estado = 'CONFIRMADA' AND fecha_fin >= vd_hoy) THEN
    RETURN 'RESERVADO';
  END IF;
  RETURN 'DISPONIBLE';
END;
$$;

COMMENT ON FUNCTION fn_estado_vehiculo_calculado(BIGINT)
  IS 'Estado operativo que le corresponde al vehículo según reservas y mantenimientos';

CREATE OR REPLACE FUNCTION fn_trg_actualizar_estado_vehiculo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vv_nuevo vehiculo.estado_operativo%TYPE;
BEGIN
  vv_nuevo := fn_estado_vehiculo_calculado(NEW.id_vehiculo);

  UPDATE vehiculo
     SET estado_operativo = vv_nuevo
   WHERE id_vehiculo = NEW.id_vehiculo
     AND estado_operativo IS DISTINCT FROM vv_nuevo;

  -- Si cambió el vehículo de la reserva o del mantenimiento, recalcular el anterior
  IF TG_OP = 'UPDATE' AND NEW.id_vehiculo <> OLD.id_vehiculo THEN
    vv_nuevo := fn_estado_vehiculo_calculado(OLD.id_vehiculo);
    UPDATE vehiculo SET estado_operativo = vv_nuevo
     WHERE id_vehiculo = OLD.id_vehiculo AND estado_operativo IS DISTINCT FROM vv_nuevo;
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_actualizar_estado_vehiculo
  AFTER INSERT OR UPDATE OF estado, id_vehiculo ON reserva
  FOR EACH ROW EXECUTE FUNCTION fn_trg_actualizar_estado_vehiculo();

CREATE TRIGGER trg_actualizar_estado_vehiculo
  AFTER INSERT OR UPDATE OF estado, id_vehiculo ON mantenimiento
  FOR EACH ROW EXECUTE FUNCTION fn_trg_actualizar_estado_vehiculo();
