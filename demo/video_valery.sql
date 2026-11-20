-- ============================================================================
-- TurismoUQ - HOJA DE TRABAJO DEL VIDEO - VALERY
-- Conexion: TURISMOUQ. Letra de 16 puntos (Herramientas > Preferencias >
-- Editor de codigo > Fuentes). Ejecutar cada bloque con Ctrl+Enter, en orden.
-- Nada de esta hoja modifica la base.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- BLOQUE 2. MODELO: volumen cargado (diapositiva 3 antes de ejecutar)
-- ---------------------------------------------------------------------------
SELECT 'MUNICIPIO' tabla, COUNT(*) filas FROM MUNICIPIO
UNION ALL SELECT 'ALOJAMIENTO', COUNT(*) FROM ALOJAMIENTO
UNION ALL SELECT 'HABITACION', COUNT(*) FROM HABITACION
UNION ALL SELECT 'TEMPORADA', COUNT(*) FROM TEMPORADA
UNION ALL SELECT 'TARIFA', COUNT(*) FROM TARIFA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'RESERVA', COUNT(*) FROM RESERVA
UNION ALL SELECT 'RESERVA_HABITACION', COUNT(*) FROM RESERVA_HABITACION
UNION ALL SELECT 'PAGO', COUNT(*) FROM PAGO
UNION ALL SELECT 'SERVICIO', COUNT(*) FROM SERVICIO
UNION ALL SELECT 'RESERVA_SERVICIO', COUNT(*) FROM RESERVA_SERVICIO
UNION ALL SELECT 'RESENA', COUNT(*) FROM RESENA
UNION ALL SELECT 'USUARIO_SISTEMA', COUNT(*) FROM USUARIO_SISTEMA;

-- Decision 1: una reserva con varias habitaciones (lineas con fechas propias)
SELECT rh.reserva_id, rh.habitacion_id, rh.fecha_checkin, rh.fecha_checkout, rh.num_huespedes
FROM   RESERVA_HABITACION rh
WHERE  rh.reserva_id = (SELECT MIN(reserva_id) FROM RESERVA_HABITACION
                         GROUP BY reserva_id HAVING COUNT(DISTINCT fecha_checkin) > 1
                         FETCH FIRST 1 ROW ONLY);

-- Decision 2: las temporadas de un anio cubren todos los dias (ejemplo 2026)
SELECT nombre, categoria, fecha_inicio, fecha_fin
FROM   TEMPORADA WHERE anio = 2026 ORDER BY fecha_inicio;

-- ---------------------------------------------------------------------------
-- BLOQUE 3. CONSULTAS DE ANALISIS
-- ---------------------------------------------------------------------------
-- C1 (PIVOT): noches-habitacion vendidas por municipio y mes, 2025
SELECT municipio,
       NVL(ene,0) ene, NVL(feb,0) feb, NVL(mar,0) mar, NVL(abr,0) abr, NVL(may,0) may, NVL(jun,0) jun,
       NVL(jul,0) jul, NVL(ago,0) ago, NVL(sep,0) sep, NVL(oct,0) oct, NVL(nov,0) nov, NVL(dic,0) dic
FROM (
    SELECT mu.nombre AS municipio,
           EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
           rh.fecha_checkout - rh.fecha_checkin AS noches
    FROM   RESERVA_HABITACION rh
    JOIN   RESERVA     r  ON r.reserva_id     = rh.reserva_id
    JOIN   HABITACION  h  ON h.habitacion_id  = rh.habitacion_id
    JOIN   ALOJAMIENTO a  ON a.alojamiento_id = h.alojamiento_id
    JOIN   MUNICIPIO   mu ON mu.municipio_id  = a.municipio_id
    WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
    AND    EXTRACT(YEAR FROM rh.fecha_checkin) = 2025
)
PIVOT (SUM(noches) FOR mes IN (1 AS ene, 2 AS feb, 3 AS mar, 4 AS abr, 5 AS may, 6 AS jun,
                               7 AS jul, 8 AS ago, 9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic))
ORDER BY municipio;

-- C3 (RANK con PARTITION BY): top 3 alojamientos por ingreso neto en cada municipio
SELECT municipio, posicion, alojamiento, ingreso_total
FROM (
    SELECT mu.nombre AS municipio, a.nombre_comercial AS alojamiento,
           SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto ELSE -p.monto END) AS ingreso_total,
           RANK() OVER (PARTITION BY mu.nombre
                        ORDER BY SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto ELSE -p.monto END) DESC) AS posicion
    FROM   PAGO p
    JOIN   RESERVA r ON r.reserva_id = p.reserva_id
    JOIN   RESERVA_HABITACION rh ON rh.reserva_id = r.reserva_id
                                AND rh.reserva_habitacion_id = (SELECT MIN(x.reserva_habitacion_id)
                                                                  FROM RESERVA_HABITACION x
                                                                 WHERE x.reserva_id = r.reserva_id)
    JOIN   HABITACION  h  ON h.habitacion_id  = rh.habitacion_id
    JOIN   ALOJAMIENTO a  ON a.alojamiento_id = h.alojamiento_id
    JOIN   MUNICIPIO   mu ON mu.municipio_id  = a.municipio_id
    WHERE  p.estado IN ('EXITOSO', 'REEMBOLSADO')
    GROUP BY mu.nombre, a.alojamiento_id, a.nombre_comercial
)
WHERE posicion <= 3
ORDER BY municipio, posicion;

-- ---------------------------------------------------------------------------
-- BLOQUE 5 (parte de Valery). SEGURIDAD: el usuario de recepcion
-- Abrir la hoja demo/video_recepcion.sql con la conexion U_RECEPCION.
-- Aqui (como TURISMOUQ) solo se muestra que privilegios dio cada rol:
-- ---------------------------------------------------------------------------
SELECT grantee AS rol, table_name AS objeto, privilege
FROM   user_tab_privs_made
WHERE  grantee LIKE 'R\_%' ESCAPE '\'
ORDER BY grantee, table_name;


--RN7
SELECT nombre, categoria, fecha_inicio, fecha_fin
FROM   TEMPORADA WHERE anio = 2026 ORDER BY fecha_inicio;
 
INSERT INTO TEMPORADA (nombre, categoria, anio, fecha_inicio, fecha_fin)
VALUES ('Puente festivo prueba', 'ALTA', 2026, DATE '2026-11-14', DATE '2026-11-16');

--RN2
VARIABLE rres NUMBER
VARIABLE rcli NUMBER
VARIABLE raloj NUMBER
BEGIN
    SELECT r.reserva_id, r.cliente_id, h.alojamiento_id INTO :rres, :rcli, :raloj
      FROM RESERVA r
      JOIN RESERVA_HABITACION rh ON rh.reserva_id = r.reserva_id
      JOIN HABITACION h ON h.habitacion_id = rh.habitacion_id
     WHERE r.estado = 'CONFIRMADA'
       AND NOT EXISTS (SELECT 1 FROM RESENA x WHERE x.reserva_id = r.reserva_id)
     FETCH FIRST 1 ROW ONLY;
END;
/
SELECT reserva_id, estado FROM RESERVA WHERE reserva_id = :rres;
INSERT INTO RESENA (cliente_id, alojamiento_id, reserva_id, calificacion, comentario)
VALUES (:rcli, :raloj, :rres, 5, 'Resena antes de hospedarse');
ROLLBACK;
