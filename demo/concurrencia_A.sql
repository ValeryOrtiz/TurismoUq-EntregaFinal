-- ============================================================================
-- TurismoUQ - Experimento de concurrencia - SESION A
-- Conexion: TURISMOUQ, hoja de trabajo normal.
-- Ejecutar CADA BLOQUE por separado (seleccionarlo y Ctrl+Enter / F5),
-- en el orden de tiempos T1..T8 indicado. La sesion B va en otra hoja NO
-- COMPARTIDA (Ctrl+Shift+N en SQL Developer), que es otra sesion de Oracle.
-- Cambie 1 y 2 por el cliente y la habitacion que imprimio la preparacion.
-- ============================================================================
SET SERVEROUTPUT ON;
VARIABLE cli NUMBER
VARIABLE hab NUMBER
VARIABLE res NUMBER
VARIABLE val NUMBER
EXEC :cli := 1;
EXEC :hab := 2;

-- ============================================================================
-- PARTE 1: SIN BLOQUEO (sp_reservar_sin_bloqueo)  -> doble reserva
-- ============================================================================
-- T1 (A): valida que la habitacion este libre (SELECT normal) e inserta la
--         reserva del 20 al 23 de diciembre. NO confirma todavia.
EXEC sp_reservar_sin_bloqueo(:cli, :hab, DATE '2026-12-20', DATE '2026-12-23', :res);
PRINT res

-- T2 (B): ... (B ejecuta lo mismo y TAMBIEN lo logra, ver script B)

-- T3 (A): confirma
COMMIT;

-- T5 (A): despues del COMMIT de B, la habitacion quedo con DOS reservas
--         activas que se cruzan: la validacion sin bloqueo no sirvio.
SELECT rh.reserva_id, r.estado, rh.habitacion_id, rh.fecha_checkin, rh.fecha_checkout
FROM   RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
WHERE  rh.habitacion_id = :hab AND rh.fecha_checkin >= DATE '2026-12-01'
ORDER BY rh.reserva_id;

-- Se deshace la doble reserva para la parte 2
DELETE FROM RESERVA_HABITACION WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id = :cli);
DELETE FROM RESERVA WHERE cliente_id = :cli;
COMMIT;

-- ============================================================================
-- PARTE 2: CON SELECT ... FOR UPDATE (pkg_turismo.sp_crear_reserva)
-- ============================================================================
-- T6 (A): sp_crear_reserva hace SELECT ... FROM HABITACION ... FOR UPDATE:
--         bloquea la fila de la habitacion y despues valida e inserta.
--         NO confirma todavia: el bloqueo sigue tomado.
EXEC pkg_turismo.sp_crear_reserva(:cli, :hab, DATE '2026-12-20', DATE '2026-12-23', 1, :res, :val, 'CONFIRMADA');
PRINT res

-- T7 (B): intenta lo mismo y se queda ESPERANDO (bloqueado por A).
--         En la hoja del monitor (SYSTEM) se ve quien bloquea a quien.

-- T8 (A): confirma; en ese instante B se desbloquea, ve la reserva de A y
--         recibe ORA-20001 (habitacion no disponible).
COMMIT;

-- Comprobacion final: una sola reserva activa para esas fechas
SELECT rh.reserva_id, r.estado, rh.habitacion_id, rh.fecha_checkin, rh.fecha_checkout
FROM   RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
WHERE  rh.habitacion_id = :hab AND rh.fecha_checkin >= DATE '2026-12-01'
ORDER BY rh.reserva_id;

-- Limpieza final del experimento
DELETE FROM RESERVA_HABITACION WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id = :cli);
DELETE FROM RESERVA WHERE cliente_id = :cli;
DELETE FROM CLIENTE WHERE cliente_id = :cli;
COMMIT;
