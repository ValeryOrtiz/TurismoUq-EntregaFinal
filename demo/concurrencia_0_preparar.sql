-- ============================================================================
-- TurismoUQ - Experimento de concurrencia (Entrega 3) - PREPARACION
-- Ejecutar UNA vez como TURISMOUQ antes de las sesiones A y B (F5).
-- Crea un cliente de prueba y elige una habitacion libre del 20 al 23 de
-- diciembre de 2026. Imprime los dos numeros que se usan en A y B.
-- ============================================================================
SET SERVEROUTPUT ON;
DECLARE
    v_cli NUMBER;
    v_hab NUMBER;
BEGIN
    -- limpieza de una corrida anterior
    DELETE FROM PAGO WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM CLIENTE WHERE documento_identidad = 'DEMO-CONC'));
    DELETE FROM RESERVA_HABITACION WHERE reserva_id IN (SELECT reserva_id FROM RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM CLIENTE WHERE documento_identidad = 'DEMO-CONC'));
    DELETE FROM RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM CLIENTE WHERE documento_identidad = 'DEMO-CONC');
    DELETE FROM CLIENTE WHERE documento_identidad = 'DEMO-CONC';

    INSERT INTO CLIENTE (nombre, documento_identidad, correo, ciudad_origen)
    VALUES ('Cliente demo concurrencia', 'DEMO-CONC', 'democonc@turismouq.co', 'Armenia')
    RETURNING cliente_id INTO v_cli;

    SELECT MIN(h.habitacion_id) INTO v_hab
      FROM HABITACION h
     WHERE NOT EXISTS (SELECT 1 FROM RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
                        WHERE rh.habitacion_id = h.habitacion_id AND r.estado <> 'CANCELADA'
                          AND rh.fecha_checkin < DATE '2026-12-23' AND rh.fecha_checkout > DATE '2026-12-20');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('cliente = ' || v_cli || '    habitacion = ' || v_hab);
    DBMS_OUTPUT.PUT_LINE('Escriba esos dos numeros en las variables de los scripts A y B.');
END;
/
