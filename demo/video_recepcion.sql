-- ============================================================================
-- TurismoUQ - HOJA DE TRABAJO DEL VIDEO - RECEPCION (la presenta Valery)
-- Conexion: U_RECEPCION / Recepcion2026 (mismo host, puerto y servicio).
-- ============================================================================
SELECT USER AS conectado_como FROM dual;

-- 1. Recepcion intenta leer una TABLA directamente -> ORA-00942
SELECT * FROM TURISMOUQ.RESERVA FETCH FIRST 5 ROWS ONLY;

-- 2. Recepcion intenta registrar un pago en la tabla -> ORA-00942
INSERT INTO TURISMOUQ.PAGO (reserva_id, monto, metodo, estado) VALUES (1, 1000, 'PSE', 'EXITOSO');

-- 3. Por la vista SI puede trabajar
SELECT habitacion_id, alojamiento, municipio, tipo_habitacion, capacidad_maxima, temporada_actual, tarifa_hoy
FROM   TURISMOUQ.V_RECEPCION_HABITACIONES
WHERE  municipio = 'Salento'
FETCH FIRST 5 ROWS ONLY;
