-- ============================================================================
-- TurismoUQ - 07_transacciones.sql                (Entrega 3 - transacciones)
-- Usuario que lo ejecuta: TURISMOUQ. Ejecutar despues de 06 (F5).
-- ----------------------------------------------------------------------------
--   A) sp_reservar_y_pagar: registra reserva y pago en UNA transaccion, con
--      SAVEPOINT. Si falla la reserva se deshace todo; si falla solo el pago
--      se vuelve al SAVEPOINT: la reserva queda PENDIENTE y el intento de
--      pago queda registrado como FALLIDO.
--   B) Demostracion paso a paso de un ROLLBACK parcial (ROLLBACK TO SAVEPOINT)
--      con consultas que muestran que queda y que se deshace.
--   C) sp_reservar_sin_bloqueo: version INSEGURA que solo se usa en el
--      experimento de concurrencia (demo/concurrencia_*.sql) para mostrar el
--      problema que resuelve SELECT ... FOR UPDATE.
-- Al final se borran los datos de la demostracion: el script es repetible.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET DEFINE OFF;
ALTER SESSION SET NLS_DATE_FORMAT = 'DD/MM/YYYY';

-- ============================================================================
-- A) TRANSACCION ATOMICA RESERVA + PAGO
-- ----------------------------------------------------------------------------
-- Paso a paso dentro del procedimiento:
--   1. pkg_turismo.sp_crear_reserva: valida y crea RESERVA + RESERVA_HABITACION
--      (bloquea la habitacion con SELECT ... FOR UPDATE).
--   2. SAVEPOINT sp_reserva_creada.
--   3. Registra el pago EXITOSO. Si la pasarela lo rechaza (aqui se simula con
--      p_simular_rechazo) o el INSERT falla por una restriccion (por ejemplo
--      monto <= 0), se hace ROLLBACK TO sp_reserva_creada: se deshace SOLO el
--      pago, la reserva sigue en pie y se registra el intento como FALLIDO.
--   4. Si lo pagado cubre estadia + servicios (RN6) la reserva pasa a
--      CONFIRMADA; si no, queda PENDIENTE (abono parcial).
--   5. COMMIT. Si algo falla en el paso 1 o en el 5, ROLLBACK total: no
--      queda ni la reserva ni el pago (atomicidad).
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (
    p_cliente_id       IN  NUMBER,
    p_habitacion_id    IN  NUMBER,
    p_fecha_in         IN  DATE,
    p_fecha_out        IN  DATE,
    p_num_huespedes    IN  NUMBER,
    p_monto            IN  NUMBER,
    p_metodo           IN  VARCHAR2,
    p_reserva_id       OUT NUMBER,
    p_estado_final     OUT VARCHAR2,
    p_simular_rechazo  IN  BOOLEAN DEFAULT FALSE
)
IS
    v_valor NUMBER;
BEGIN
    -- 1. reserva (si falla, salta al manejador final y se deshace todo)
    pkg_turismo.sp_crear_reserva(p_cliente_id, p_habitacion_id, p_fecha_in, p_fecha_out,
                                 p_num_huespedes, p_reserva_id, v_valor, 'PENDIENTE');

    -- 2. punto de guardado: hasta aqui la reserva es valida
    SAVEPOINT sp_reserva_creada;

    -- 3. pago
    BEGIN
        IF p_simular_rechazo THEN
            RAISE_APPLICATION_ERROR(-20021, 'La pasarela de pagos rechazo la transaccion.');
        END IF;

        INSERT INTO PAGO (reserva_id, fecha_pago, monto, metodo, estado)
        VALUES (p_reserva_id, SYSDATE, p_monto, p_metodo, 'EXITOSO');

        -- 4. RN6: confirmada solo si lo pagado cubre el total
        IF pkg_turismo.fn_reserva_pagada(p_reserva_id) = 'S' THEN
            UPDATE RESERVA SET estado = 'CONFIRMADA' WHERE reserva_id = p_reserva_id;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            -- ROLLBACK PARCIAL: se deshace el pago, NO la reserva
            ROLLBACK TO sp_reserva_creada;
            DBMS_OUTPUT.PUT_LINE('Pago deshecho con ROLLBACK TO sp_reserva_creada: ' || SQLERRM);
            -- se deja constancia del intento fallido (si el monto es valido)
            IF p_monto > 0 THEN
                INSERT INTO PAGO (reserva_id, fecha_pago, monto, metodo, estado)
                VALUES (p_reserva_id, SYSDATE, p_monto, p_metodo, 'FALLIDO');
            END IF;
    END;

    SELECT estado INTO p_estado_final FROM RESERVA WHERE reserva_id = p_reserva_id;

    -- 5. confirmacion de todo lo que quedo en pie
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;            -- atomicidad: ni reserva ni pago
        p_reserva_id   := NULL;
        p_estado_final := NULL;
        RAISE;
END sp_reservar_y_pagar;
/
SHOW ERRORS PROCEDURE sp_reservar_y_pagar;

-- ============================================================================
-- C) VERSION INSEGURA, SOLO PARA EL EXPERIMENTO DE CONCURRENCIA
-- ----------------------------------------------------------------------------
-- Valida la disponibilidad con un SELECT normal (sin FOR UPDATE) e inserta.
-- No hace COMMIT. Si dos sesiones la ejecutan al tiempo para la misma
-- habitacion, ninguna ve la fila sin confirmar de la otra (lectura
-- consistente de Oracle), las dos pasan la validacion y las dos insertan:
-- se produce una doble reserva. Ver demo/concurrencia_*.sql.
-- La version correcta es pkg_turismo.sp_crear_reserva, que bloquea la fila
-- de la habitacion con SELECT ... FOR UPDATE antes de validar.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_reservar_sin_bloqueo (
    p_cliente_id    IN  NUMBER,
    p_habitacion_id IN  NUMBER,
    p_fecha_in      IN  DATE,
    p_fecha_out     IN  DATE,
    p_reserva_id    OUT NUMBER
)
IS
    v_cruces NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_cruces                       -- sin FOR UPDATE
      FROM RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
     WHERE rh.habitacion_id = p_habitacion_id
       AND r.estado <> 'CANCELADA'
       AND rh.fecha_checkin < p_fecha_out
       AND rh.fecha_checkout > p_fecha_in;

    IF v_cruces > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Habitacion no disponible (version sin bloqueo).');
    END IF;

    INSERT INTO RESERVA (cliente_id, fecha_checkin, fecha_checkout, fecha_reserva, estado)
    VALUES (p_cliente_id, p_fecha_in, p_fecha_out, SYSDATE, 'CONFIRMADA')
    RETURNING reserva_id INTO p_reserva_id;
    INSERT INTO RESERVA_HABITACION (reserva_id, habitacion_id, fecha_checkin, fecha_checkout, num_huespedes)
    VALUES (p_reserva_id, p_habitacion_id, p_fecha_in, p_fecha_out, 1);
END sp_reservar_sin_bloqueo;
/
SHOW ERRORS PROCEDURE sp_reservar_sin_bloqueo;

-- ============================================================================
-- Datos de la demostracion: un cliente propio y una habitacion libre en
-- diciembre de 2026 (se borran al final del script).
-- ============================================================================
VARIABLE cli_demo NUMBER
VARIABLE hab_demo NUMBER
VARIABLE res_demo NUMBER
VARIABLE val_demo NUMBER
VARIABLE estado   VARCHAR2(15)

BEGIN
    DELETE FROM PAGO WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM CLIENTE WHERE documento_identidad = 'DEMO-07'));
    DELETE FROM RESERVA_HABITACION WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM CLIENTE WHERE documento_identidad = 'DEMO-07'));
    DELETE FROM RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM CLIENTE WHERE documento_identidad = 'DEMO-07');
    DELETE FROM CLIENTE WHERE documento_identidad = 'DEMO-07';

    INSERT INTO CLIENTE (nombre, documento_identidad, correo, ciudad_origen)
    VALUES ('Cliente demostracion transacciones', 'DEMO-07', 'demo07@turismouq.co', 'Armenia')
    RETURNING cliente_id INTO :cli_demo;

    SELECT MIN(h.habitacion_id) INTO :hab_demo
      FROM HABITACION h
     WHERE h.capacidad_maxima >= 2
       AND NOT EXISTS (SELECT 1 FROM RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
                        WHERE rh.habitacion_id = h.habitacion_id AND r.estado <> 'CANCELADA'
                          AND rh.fecha_checkin < DATE '2026-12-31' AND rh.fecha_checkout > DATE '2026-12-01');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Cliente demo: ' || :cli_demo || '   habitacion libre en diciembre 2026: ' || :hab_demo);
END;
/

-- ============================================================================
-- B) ROLLBACK PARCIAL PASO A PASO (tabla de la seccion 7.1 del documento)
-- ============================================================================
PROMPT ===== Paso 1: INSERT de la reserva (sp_crear_reserva: RESERVA + RESERVA_HABITACION) =====
BEGIN
    pkg_turismo.sp_crear_reserva(:cli_demo, :hab_demo, DATE '2026-12-01', DATE '2026-12-04',
                                 2, :res_demo, :val_demo, 'PENDIENTE');
    DBMS_OUTPUT.PUT_LINE('Reserva ' || :res_demo || ' creada; valor de la estadia: ' || :val_demo);
END;
/
SELECT r.reserva_id, r.estado, rh.habitacion_id, rh.fecha_checkin, rh.fecha_checkout,
       (SELECT COUNT(*) FROM PAGO p WHERE p.reserva_id = r.reserva_id) AS pagos
FROM   RESERVA r JOIN RESERVA_HABITACION rh ON rh.reserva_id = r.reserva_id
WHERE  r.reserva_id = :res_demo;

PROMPT ===== Paso 2: SAVEPOINT despues de la reserva =====
SAVEPOINT sp_reserva_creada;

PROMPT ===== Paso 3: INSERT del anticipo (40 %) y luego un segundo pago que se descarta =====
INSERT INTO PAGO (reserva_id, fecha_pago, monto, metodo, estado)
VALUES (:res_demo, SYSDATE, ROUND(:val_demo * 0.4), 'PSE', 'EXITOSO');

SAVEPOINT sp_anticipo_pagado;

INSERT INTO PAGO (reserva_id, fecha_pago, monto, metodo, estado)
VALUES (:res_demo, SYSDATE, :val_demo - ROUND(:val_demo * 0.4), 'TARJETA_CREDITO', 'EXITOSO');

UPDATE RESERVA SET estado = 'CONFIRMADA' WHERE reserva_id = :res_demo;

PROMPT Antes del ROLLBACK parcial: 2 pagos y reserva CONFIRMADA
SELECT r.reserva_id, r.estado, p.pago_id, p.monto, p.metodo, p.estado AS estado_pago
FROM   RESERVA r LEFT JOIN PAGO p ON p.reserva_id = r.reserva_id
WHERE  r.reserva_id = :res_demo
ORDER BY p.pago_id;

PROMPT ===== Paso 4: la tarjeta del saldo fue rechazada -> ROLLBACK TO sp_anticipo_pagado =====
ROLLBACK TO sp_anticipo_pagado;

PROMPT Despues del ROLLBACK parcial: sigue la reserva y el anticipo; se deshizo el saldo y la confirmacion
SELECT r.reserva_id, r.estado, p.pago_id, p.monto, p.metodo, p.estado AS estado_pago
FROM   RESERVA r LEFT JOIN PAGO p ON p.reserva_id = r.reserva_id
WHERE  r.reserva_id = :res_demo
ORDER BY p.pago_id;

PROMPT ===== Paso 5: COMMIT de lo que quedo en pie =====
COMMIT;

SELECT r.reserva_id, r.estado,
       pkg_turismo.fn_valor_reserva(r.reserva_id) AS valor_total,
       pkg_turismo.fn_total_pagado(r.reserva_id)  AS pagado,
       pkg_turismo.fn_reserva_pagada(r.reserva_id) AS pagada
FROM   RESERVA r
WHERE  r.reserva_id = :res_demo;

-- ============================================================================
-- A) PRUEBAS DEL PROCEDIMIENTO ATOMICO
-- ============================================================================
PROMPT ===== A.1 Pago completo: reserva CONFIRMADA y un pago EXITOSO =====
DECLARE
    v_valor NUMBER;
BEGIN
    v_valor := pkg_turismo.fn_valor_estadia(:hab_demo, DATE '2026-12-10', DATE '2026-12-12');
    sp_reservar_y_pagar(:cli_demo, :hab_demo, DATE '2026-12-10', DATE '2026-12-12', 1,
                        v_valor, 'TARJETA_DEBITO', :res_demo, :estado);
    DBMS_OUTPUT.PUT_LINE('Reserva ' || :res_demo || ' -> ' || :estado);
END;
/
SELECT r.reserva_id, r.estado, p.monto, p.estado AS estado_pago
FROM   RESERVA r JOIN PAGO p ON p.reserva_id = r.reserva_id
WHERE  r.reserva_id = :res_demo;

PROMPT ===== A.2 Pago rechazado: ROLLBACK TO SAVEPOINT -> reserva PENDIENTE y pago FALLIDO =====
BEGIN
    sp_reservar_y_pagar(:cli_demo, :hab_demo, DATE '2026-12-15', DATE '2026-12-17', 1,
                        100000, 'PSE', :res_demo, :estado, p_simular_rechazo => TRUE);
    DBMS_OUTPUT.PUT_LINE('Reserva ' || :res_demo || ' -> ' || :estado);
END;
/
SELECT r.reserva_id, r.estado, p.monto, p.estado AS estado_pago
FROM   RESERVA r JOIN PAGO p ON p.reserva_id = r.reserva_id
WHERE  r.reserva_id = :res_demo;

PROMPT ===== A.3 Falla la reserva (habitacion ocupada): ROLLBACK total, no queda nada =====
VARIABLE reservas_antes NUMBER
EXEC SELECT COUNT(*) INTO :reservas_antes FROM RESERVA WHERE cliente_id = :cli_demo;
BEGIN
    sp_reservar_y_pagar(:cli_demo, :hab_demo, DATE '2026-12-11', DATE '2026-12-13', 1,
                        100000, 'PSE', :res_demo, :estado);
    DBMS_OUTPUT.PUT_LINE('FALLO: se acepto una reserva solapada');
EXCEPTION
    WHEN pkg_turismo.e_habitacion_no_disponible THEN
        DBMS_OUTPUT.PUT_LINE('OK  -> ' || SQLERRM);
END;
/
SELECT :reservas_antes AS reservas_antes,
       (SELECT COUNT(*) FROM RESERVA WHERE cliente_id = :cli_demo) AS reservas_despues,
       CASE WHEN :reservas_antes = (SELECT COUNT(*) FROM RESERVA WHERE cliente_id = :cli_demo)
            THEN 'OK: no quedo nada a medias' ELSE 'FALLO' END AS resultado
FROM dual;

-- ============================================================================
-- Limpieza: se borran los datos de la demostracion (script repetible)
-- ============================================================================
BEGIN
    DELETE FROM PAGO WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id = :cli_demo);
    DELETE FROM RESERVA_HABITACION WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id = :cli_demo);
    DELETE FROM RESERVA WHERE cliente_id = :cli_demo;
    DELETE FROM CLIENTE WHERE cliente_id = :cli_demo;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Datos de la demostracion eliminados.');
END;
/
PROMPT 07_transacciones.sql terminado.
