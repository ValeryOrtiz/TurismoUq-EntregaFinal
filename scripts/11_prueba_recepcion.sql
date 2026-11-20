-- ============================================================================
-- TurismoUQ - 11_prueba_recepcion.sql            (Entrega 3 - prueba de seguridad)
-- Usuario que lo ejecuta: U_RECEPCION / Recepcion2026 (crear la conexion en
-- SQL Developer con el mismo host, puerto y nombre de servicio).
-- Demuestra que recepcion NO llega a las tablas y SI trabaja por vistas.
-- ============================================================================
SET SERVEROUTPUT ON;
SELECT USER AS conectado_como FROM dual;

PROMPT ===== 1. Intento de consultar una TABLA directamente: debe fallar =====
-- Oracle responde ORA-00942 ("la tabla o vista no existe"): para un usuario
-- sin ningun privilegio sobre el objeto, Oracle ni siquiera confirma que la
-- tabla existe. Esa es la proteccion: recepcion no ve las tablas.
SELECT * FROM TURISMOUQ.RESERVA FETCH FIRST 5 ROWS ONLY;

PROMPT ===== 2. Intento de escribir en una tabla directamente: debe fallar =====
INSERT INTO TURISMOUQ.PAGO (reserva_id, monto, metodo, estado) VALUES (1, 1000, 'PSE', 'EXITOSO');

PROMPT ===== 3. Las vistas SI funcionan =====
SELECT * FROM TURISMOUQ.V_RECEPCION_HABITACIONES WHERE municipio = 'Salento' FETCH FIRST 5 ROWS ONLY;
SELECT * FROM TURISMOUQ.V_RECEPCION_CLIENTES WHERE cliente_id <= 5;
SELECT * FROM TURISMOUQ.V_RECEPCION_RESERVAS ORDER BY fecha_checkin FETCH FIRST 5 ROWS ONLY;

PROMPT ===== 4. Recepcion registra reserva y pago con el procedimiento (sin tocar tablas) =====
-- Se usa el cliente de pruebas que crea 09_seguridad.sql (documento
-- PRUEBA-RECEPCION); 15_prueba_perfil.sql borra al final lo que se cree aqui.
VARIABLE res    NUMBER
VARIABLE estado VARCHAR2(15)
DECLARE
    v_hab NUMBER;
    v_cli NUMBER;
BEGIN
    SELECT cliente_id INTO v_cli FROM TURISMOUQ.V_RECEPCION_CLIENTES
     WHERE documento_identidad = 'PRUEBA-RECEPCION';
    -- primera habitacion libre del 7 al 9 de diciembre de 2026, segun la vista de ocupacion
    SELECT MIN(h.habitacion_id) INTO v_hab
      FROM TURISMOUQ.V_RECEPCION_HABITACIONES h
     WHERE NOT EXISTS (SELECT 1 FROM TURISMOUQ.V_RECEPCION_OCUPACION o
                        WHERE o.habitacion_id = h.habitacion_id
                          AND o.fecha_checkin < DATE '2026-12-09'
                          AND o.fecha_checkout > DATE '2026-12-07');
    TURISMOUQ.SP_RESERVAR_Y_PAGAR(v_cli, v_hab, DATE '2026-12-07', DATE '2026-12-09', 1,
                                  50000, 'EFECTIVO', :res, :estado);
    DBMS_OUTPUT.PUT_LINE('Reserva ' || :res || ' registrada en la habitacion ' || v_hab ||
                         ' -> ' || :estado || ' (abono parcial de 50.000)');
END;
/
SELECT * FROM TURISMOUQ.V_RECEPCION_RESERVAS WHERE reserva_id = :res;

PROMPT ===== 5. Recepcion no puede cancelar ni borrar: no tiene ese privilegio =====
DELETE FROM TURISMOUQ.V_RECEPCION_RESERVAS WHERE reserva_id = :res;
