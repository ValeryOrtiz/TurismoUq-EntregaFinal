-- ============================================================================
-- TurismoUQ - HOJA DE TRABAJO DEL VIDEO - JHONATAN DAVID
-- Conexion: TURISMOUQ. Letra de 16 puntos. Ejecutar cada bloque con
-- Ctrl+Enter (los bloques PL/SQL se seleccionan completos, hasta la /).
-- Lo que se modifica se deshace con ROLLBACK o se restaura al final.
-- ============================================================================
SET SERVEROUTPUT ON;
VARIABLE res NUMBER
VARIABLE val NUMBER

-- ---------------------------------------------------------------------------
-- BLOQUE 4. CAPA PL/SQL
-- ---------------------------------------------------------------------------
-- 4.1 Calculo a mano: tarifas de la habitacion 1 en las dos temporadas que cruza
--     una estadia del 28/11/2026 al 03/12/2026 (5 noches)
SELECT t.nombre || ' ' || t.anio AS temporada, t.categoria, t.fecha_inicio, t.fecha_fin, ta.precio_noche
FROM   TARIFA ta JOIN TEMPORADA t ON t.temporada_id = ta.temporada_id
WHERE  ta.habitacion_id = 1
AND    t.anio = 2026 AND t.nombre IN ('Temporada media III', 'Fin de ano')
ORDER BY t.fecha_inicio;

-- Noche por noche (28, 29, 30 de noviembre y 1, 2 de diciembre; el 3 no se cobra)
SELECT n.noche, t.nombre || ' ' || t.anio AS temporada, ta.precio_noche
FROM  (SELECT DATE '2026-11-28' + LEVEL - 1 AS noche FROM dual CONNECT BY LEVEL <= 5) n
JOIN   TEMPORADA t ON n.noche BETWEEN t.fecha_inicio AND t.fecha_fin
JOIN   TARIFA ta   ON ta.temporada_id = t.temporada_id AND ta.habitacion_id = 1
ORDER BY n.noche;

-- Resultado de la funcion (comparar con 3 x media + 2 x alta)
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2026-11-28', DATE '2026-12-03') AS valor_funcion FROM dual;

-- 4.2 Error propio de sp_crear_reserva: mas huespedes que la capacidad -> ORA-20003
SELECT habitacion_id, capacidad_maxima FROM HABITACION WHERE habitacion_id = 1;
BEGIN
    pkg_turismo.sp_crear_reserva(1, 1, DATE '2026-12-28', DATE '2026-12-30', 10, :res, :val);
END;
/

-- 4.3 El disparador rechaza una reserva que se solapa con otra confirmada.
--     Se busca una linea CONFIRMADA futura y se inserta OTRA linea para la misma
--     habitacion y fechas, directamente en la tabla (sin pasar por el paquete).
VARIABLE hab NUMBER
VARIABLE ci  VARCHAR2(10)
VARIABLE co  VARCHAR2(10)
BEGIN
    SELECT rh.habitacion_id, TO_CHAR(rh.fecha_checkin, 'YYYY-MM-DD'), TO_CHAR(rh.fecha_checkout, 'YYYY-MM-DD')
      INTO :hab, :ci, :co
      FROM RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
     WHERE r.estado = 'CONFIRMADA' AND rh.fecha_checkin > SYSDATE
     FETCH FIRST 1 ROW ONLY;
    INSERT INTO RESERVA (cliente_id, fecha_checkin, fecha_checkout, estado)
    VALUES (1, TO_DATE(:ci, 'YYYY-MM-DD'), TO_DATE(:co, 'YYYY-MM-DD'), 'CONFIRMADA')
    RETURNING reserva_id INTO :res;
    DBMS_OUTPUT.PUT_LINE('Habitacion ' || :hab || ' ocupada del ' || :ci || ' al ' || :co);
END;
/
INSERT INTO RESERVA_HABITACION (reserva_id, habitacion_id, fecha_checkin, fecha_checkout, num_huespedes)
VALUES (:res, :hab, TO_DATE(:ci, 'YYYY-MM-DD'), TO_DATE(:co, 'YYYY-MM-DD'), 1);
ROLLBACK;

-- 4.4 La auditoria de TARIFA: un UPDATE de varias filas y lo que registra
UPDATE TARIFA SET precio_noche = precio_noche + 1000
WHERE  habitacion_id IN (1, 2)
AND    temporada_id IN (SELECT temporada_id FROM TEMPORADA WHERE anio = 2027 AND nombre = 'Temporada media III');
COMMIT;

SELECT id_sentencia, operacion, habitacion_id, temporada_id, precio_anterior, precio_nuevo,
       usuario_bd, usuario_so, equipo, TO_CHAR(fecha_hora, 'DD/MM/YYYY HH24:MI:SS') AS cuando
FROM   AUDITORIA_TARIFA
WHERE  id_sentencia = (SELECT MAX(id_sentencia) FROM AUDITORIA_TARIFA);

-- (se devuelven las tarifas a su valor; tambien queda auditado)
UPDATE TARIFA SET precio_noche = precio_noche - 1000
WHERE  habitacion_id IN (1, 2)
AND    temporada_id IN (SELECT temporada_id FROM TEMPORADA WHERE anio = 2027 AND nombre = 'Temporada media III');
COMMIT;

-- ---------------------------------------------------------------------------
-- BLOQUE 5. TRANSACCIONES E INDICES
-- ---------------------------------------------------------------------------
-- 5.1 Rollback parcial con SAVEPOINT (en una habitacion libre del 28 al 30 de diciembre)
VARIABLE libre NUMBER
EXEC SELECT MIN(h.habitacion_id) INTO :libre FROM HABITACION h WHERE NOT EXISTS (SELECT 1 FROM RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id WHERE rh.habitacion_id = h.habitacion_id AND r.estado <> 'CANCELADA' AND rh.fecha_checkin < DATE '2026-12-30' AND rh.fecha_checkout > DATE '2026-12-28');
BEGIN
    pkg_turismo.sp_crear_reserva(1, :libre, DATE '2026-12-28', DATE '2026-12-30', 1, :res, :val);
    DBMS_OUTPUT.PUT_LINE('Reserva ' || :res || ' por ' || :val);
END;
/
SAVEPOINT sp_reserva_creada;

INSERT INTO PAGO (reserva_id, fecha_pago, monto, metodo, estado)
VALUES (:res, SYSDATE, :val, 'TARJETA_CREDITO', 'EXITOSO');

SELECT r.reserva_id, r.estado, p.monto, p.estado AS estado_pago
FROM   RESERVA r LEFT JOIN PAGO p ON p.reserva_id = r.reserva_id WHERE r.reserva_id = :res;

-- la tarjeta fue rechazada: se deshace SOLO el pago
ROLLBACK TO sp_reserva_creada;

SELECT r.reserva_id, r.estado, p.monto, p.estado AS estado_pago
FROM   RESERVA r LEFT JOIN PAGO p ON p.reserva_id = r.reserva_id WHERE r.reserva_id = :res;

ROLLBACK;   -- fin de la demostracion: no se deja la reserva

-- 5.2 Indice compuesto: plan ANTES (se quita el indice para mostrarlo)
DROP INDEX IX_RESERVA_CLIENTE_ESTADO;
EXPLAIN PLAN FOR
SELECT reserva_id, fecha_checkin, fecha_checkout, estado
FROM   RESERVA WHERE cliente_id = 1500 AND estado = 'COMPLETADA' ORDER BY fecha_checkin DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

CREATE INDEX IX_RESERVA_CLIENTE_ESTADO ON RESERVA (cliente_id, estado, fecha_checkin);

-- plan DESPUES
EXPLAIN PLAN FOR
SELECT reserva_id, fecha_checkin, fecha_checkout, estado
FROM   RESERVA WHERE cliente_id = 1500 AND estado = 'COMPLETADA' ORDER BY fecha_checkin DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

-- 5.3 El caso donde el indice NO ayuda: estado tiene 4 valores
CREATE INDEX IX_RESERVA_ESTADO ON RESERVA (estado);
SELECT estado, COUNT(*) FROM RESERVA GROUP BY estado;

EXPLAIN PLAN FOR
SELECT COUNT(*), SUM(fecha_checkout - fecha_checkin) FROM RESERVA WHERE estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

-- forzando el indice: el costo sube
EXPLAIN PLAN FOR
SELECT /*+ INDEX(r IX_RESERVA_ESTADO) */ COUNT(*), SUM(fecha_checkout - fecha_checkin)
FROM   RESERVA r WHERE estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

DROP INDEX IX_RESERVA_ESTADO;
