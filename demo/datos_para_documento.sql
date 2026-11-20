-- ============================================================================
-- TurismoUQ - datos_para_documento.sql
-- Usuario: TURISMOUQ, despues de correr 00 a 10. Ejecutar con F5.
-- Saca en un solo archivo todos los numeros que pide el documento final
-- (secciones 4.2, 4.3, 5, 6.2 y 6.4). No modifica nada.
-- ============================================================================
SPOOL datos_para_documento.txt
SET LINESIZE 200;
SET PAGESIZE 200;
SET FEEDBACK OFF;
ALTER SESSION SET NLS_DATE_FORMAT = 'DD/MM/YYYY';

PROMPT ===== 4.2 Volumen de datos =====
SELECT 'MUNICIPIO' tabla, COUNT(*) filas FROM MUNICIPIO
UNION ALL SELECT 'TIPO_ALOJAMIENTO', COUNT(*) FROM TIPO_ALOJAMIENTO
UNION ALL SELECT 'ROL', COUNT(*) FROM ROL
UNION ALL SELECT 'ALOJAMIENTO', COUNT(*) FROM ALOJAMIENTO
UNION ALL SELECT 'HABITACION', COUNT(*) FROM HABITACION
UNION ALL SELECT 'TEMPORADA', COUNT(*) FROM TEMPORADA
UNION ALL SELECT 'TARIFA', COUNT(*) FROM TARIFA
UNION ALL SELECT 'HABITACION x TEMPORADA', (SELECT COUNT(*) FROM HABITACION) * (SELECT COUNT(*) FROM TEMPORADA) FROM dual
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'RESERVA', COUNT(*) FROM RESERVA
UNION ALL SELECT 'RESERVA_HABITACION', COUNT(*) FROM RESERVA_HABITACION
UNION ALL SELECT 'PAGO', COUNT(*) FROM PAGO
UNION ALL SELECT 'SERVICIO', COUNT(*) FROM SERVICIO
UNION ALL SELECT 'RESERVA_SERVICIO', COUNT(*) FROM RESERVA_SERVICIO
UNION ALL SELECT 'RESENA', COUNT(*) FROM RESENA
UNION ALL SELECT 'USUARIO_SISTEMA', COUNT(*) FROM USUARIO_SISTEMA
UNION ALL SELECT 'USUARIO_ALOJAMIENTO', COUNT(*) FROM USUARIO_ALOJAMIENTO
UNION ALL SELECT 'LIQUIDACION_MENSUAL', COUNT(*) FROM LIQUIDACION_MENSUAL
UNION ALL SELECT 'AUDITORIA_TARIFA', COUNT(*) FROM AUDITORIA_TARIFA
UNION ALL SELECT 'RESERVA_HISTORICO', COUNT(*) FROM RESERVA_HISTORICO
UNION ALL SELECT 'CALENDARIO', COUNT(*) FROM CALENDARIO
UNION ALL SELECT 'MV_OCUPACION_MENSUAL', COUNT(*) FROM MV_OCUPACION_MENSUAL;

SELECT MIN(fecha_checkin) AS primer_checkin, MAX(fecha_checkin) AS ultimo_checkin FROM RESERVA;
SELECT ROUND(100 * COUNT(rs.resena_id) / COUNT(*), 1) AS pct_completadas_con_resena
FROM RESERVA r LEFT JOIN RESENA rs ON rs.reserva_id = r.reserva_id WHERE r.estado = 'COMPLETADA';
SELECT estado, COUNT(*) AS reservas FROM RESERVA GROUP BY estado ORDER BY 2 DESC;

PROMPT ===== 4.3 Asimetria =====
SELECT 'Alojamientos por municipio' AS pregunta, MIN(n) AS minimo, MAX(n) AS maximo
FROM (SELECT municipio_id, COUNT(*) n FROM ALOJAMIENTO GROUP BY municipio_id)
UNION ALL
SELECT 'Habitaciones por alojamiento', MIN(n), MAX(n)
FROM (SELECT alojamiento_id, COUNT(*) n FROM HABITACION GROUP BY alojamiento_id)
UNION ALL
SELECT 'Reservas por mes (2025)', MIN(n), MAX(n)
FROM (SELECT EXTRACT(MONTH FROM fecha_checkin) m, COUNT(*) n FROM RESERVA
      WHERE EXTRACT(YEAR FROM fecha_checkin) = 2025 GROUP BY EXTRACT(MONTH FROM fecha_checkin))
UNION ALL
SELECT 'Servicios por alojamiento', MIN(n), MAX(n)
FROM (SELECT a.alojamiento_id, COUNT(s.servicio_id) n FROM ALOJAMIENTO a
      LEFT JOIN SERVICIO s ON s.alojamiento_id = a.alojamiento_id GROUP BY a.alojamiento_id);

SELECT (SELECT COUNT(*) FROM (SELECT reserva_id FROM RESERVA_HABITACION GROUP BY reserva_id HAVING COUNT(*) > 1)) AS reservas_varias_habitaciones,
       (SELECT COUNT(*) FROM (SELECT reserva_id FROM PAGO GROUP BY reserva_id HAVING COUNT(*) > 1)) AS reservas_varios_pagos
FROM dual;

SELECT mu.nombre AS municipio, COUNT(*) AS alojamientos FROM ALOJAMIENTO a
JOIN MUNICIPIO mu ON mu.municipio_id = a.municipio_id GROUP BY mu.nombre ORDER BY 2 DESC;

SELECT EXTRACT(MONTH FROM fecha_checkin) AS mes, COUNT(*) AS reservas_2025 FROM RESERVA
WHERE EXTRACT(YEAR FROM fecha_checkin) = 2025 GROUP BY EXTRACT(MONTH FROM fecha_checkin) ORDER BY 1;

SELECT ta.nombre AS tipo, COUNT(DISTINCT a.alojamiento_id) AS alojamientos, COUNT(h.habitacion_id) AS habitaciones,
       MIN(c.n) AS min_hab, MAX(c.n) AS max_hab
FROM ALOJAMIENTO a JOIN TIPO_ALOJAMIENTO ta ON ta.tipo_alojamiento_id = a.tipo_alojamiento_id
JOIN HABITACION h ON h.alojamiento_id = a.alojamiento_id
JOIN (SELECT alojamiento_id, COUNT(*) n FROM HABITACION GROUP BY alojamiento_id) c ON c.alojamiento_id = a.alojamiento_id
GROUP BY ta.nombre;

PROMPT ===== 5. Filas que devuelve cada consulta =====
SELECT 'C1' AS consulta, COUNT(*) AS filas FROM (
  SELECT DISTINCT mu.nombre FROM RESERVA_HABITACION rh JOIN RESERVA r ON r.reserva_id = rh.reserva_id
  JOIN HABITACION h ON h.habitacion_id = rh.habitacion_id JOIN ALOJAMIENTO a ON a.alojamiento_id = h.alojamiento_id
  JOIN MUNICIPIO mu ON mu.municipio_id = a.municipio_id
  WHERE r.estado IN ('CONFIRMADA','COMPLETADA') AND EXTRACT(YEAR FROM rh.fecha_checkin) = 2025)
UNION ALL
SELECT 'C2', COUNT(*) FROM (
  SELECT 1 FROM PAGO p JOIN RESERVA r ON r.reserva_id = p.reserva_id
  JOIN RESERVA_HABITACION rh ON rh.reserva_id = r.reserva_id
   AND rh.reserva_habitacion_id = (SELECT MIN(x.reserva_habitacion_id) FROM RESERVA_HABITACION x WHERE x.reserva_id = r.reserva_id)
  JOIN HABITACION h ON h.habitacion_id = rh.habitacion_id JOIN ALOJAMIENTO a ON a.alojamiento_id = h.alojamiento_id
  JOIN MUNICIPIO mu ON mu.municipio_id = a.municipio_id JOIN TIPO_ALOJAMIENTO ta ON ta.tipo_alojamiento_id = a.tipo_alojamiento_id
  JOIN TEMPORADA t ON r.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
  WHERE p.estado IN ('EXITOSO','REEMBOLSADO')
  GROUP BY ROLLUP (mu.nombre, ta.nombre, (t.anio, t.nombre)))
UNION ALL
SELECT 'C3', COUNT(*) FROM (
  SELECT RANK() OVER (PARTITION BY mu.nombre ORDER BY SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto ELSE -p.monto END) DESC) pos
  FROM PAGO p JOIN RESERVA r ON r.reserva_id = p.reserva_id
  JOIN RESERVA_HABITACION rh ON rh.reserva_id = r.reserva_id
   AND rh.reserva_habitacion_id = (SELECT MIN(x.reserva_habitacion_id) FROM RESERVA_HABITACION x WHERE x.reserva_id = r.reserva_id)
  JOIN HABITACION h ON h.habitacion_id = rh.habitacion_id JOIN ALOJAMIENTO a ON a.alojamiento_id = h.alojamiento_id
  JOIN MUNICIPIO mu ON mu.municipio_id = a.municipio_id
  WHERE p.estado IN ('EXITOSO','REEMBOLSADO') GROUP BY mu.nombre, a.alojamiento_id) WHERE pos <= 3
UNION ALL
SELECT 'C4', COUNT(DISTINCT TO_CHAR(r.fecha_checkin, 'YYYY-MM')) FROM PAGO p JOIN RESERVA r ON r.reserva_id = p.reserva_id
  WHERE p.estado IN ('EXITOSO','REEMBOLSADO')
UNION ALL
SELECT 'C5', COUNT(DISTINCT mu.nombre) FROM PAGO p JOIN RESERVA r ON r.reserva_id = p.reserva_id
  JOIN RESERVA_HABITACION rh ON rh.reserva_id = r.reserva_id JOIN HABITACION h ON h.habitacion_id = rh.habitacion_id
  JOIN ALOJAMIENTO a ON a.alojamiento_id = h.alojamiento_id JOIN MUNICIPIO mu ON mu.municipio_id = a.municipio_id
  WHERE p.estado IN ('EXITOSO','REEMBOLSADO') AND r.fecha_checkin BETWEEN DATE '2025-06-01' AND DATE '2025-07-31'
UNION ALL
SELECT 'C6', COUNT(*) FROM (
  SELECT TO_CHAR(fecha_evento, 'YYYY-MM'), tipo_evento FROM RESERVA
  UNPIVOT (fecha_evento FOR tipo_evento IN (fecha_reserva AS 'R', fecha_checkin AS 'I', fecha_checkout AS 'O'))
  WHERE estado <> 'CANCELADA' AND EXTRACT(YEAR FROM fecha_evento) = 2025
  GROUP BY TO_CHAR(fecha_evento, 'YYYY-MM'), tipo_evento)
UNION ALL
SELECT 'C7', COUNT(*) FROM TIPO_ALOJAMIENTO;

PROMPT ===== 6.2 fn_valor_estadia sobre la habitacion 1 =====
SELECT h.habitacion_id, h.numero, a.nombre_comercial, h.tipo_habitacion
FROM HABITACION h JOIN ALOJAMIENTO a ON a.alojamiento_id = h.alojamiento_id WHERE h.habitacion_id = 1;
SELECT t.nombre || ' ' || t.anio AS temporada, t.categoria, t.fecha_inicio, t.fecha_fin, ta.precio_noche
FROM TARIFA ta JOIN TEMPORADA t ON t.temporada_id = ta.temporada_id
WHERE ta.habitacion_id = 1
AND   t.fecha_inicio <= DATE '2027-01-12' AND t.fecha_fin >= DATE '2026-10-01'
ORDER BY t.fecha_inicio;
SELECT 'Una temporada 05/10/2026-08/10/2026' AS caso, pkg_turismo.fn_valor_estadia(1, DATE '2026-10-05', DATE '2026-10-08') AS valor FROM dual
UNION ALL SELECT 'Dos temporadas 28/11/2026-03/12/2026', pkg_turismo.fn_valor_estadia(1, DATE '2026-11-28', DATE '2026-12-03') FROM dual
UNION ALL SELECT 'Cambio de anio 29/12/2026-03/01/2027', pkg_turismo.fn_valor_estadia(1, DATE '2026-12-29', DATE '2027-01-03') FROM dual;

PROMPT ===== 6.4 Liquidacion guardada =====
SELECT anio, mes, COUNT(*) AS alojamientos, SUM(num_reservas) AS reservas, SUM(noches_vendidas) AS noches,
       SUM(valor_bruto) AS bruto, SUM(valor_comision) AS comision, SUM(valor_neto) AS neto
FROM LIQUIDACION_MENSUAL GROUP BY anio, mes ORDER BY anio, mes;

PROMPT ===== Ocupacion 2025 por municipio (vista materializada) =====
SELECT municipio, ROUND(100 * SUM(noches_vendidas) / SUM(noches_disponibles), 2) AS pct
FROM MV_OCUPACION_MENSUAL WHERE anio = 2025 GROUP BY municipio ORDER BY pct DESC;

SPOOL OFF
