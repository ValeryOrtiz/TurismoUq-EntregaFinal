-- ============================================================================
-- TurismoUQ - 13_prueba_gerente.sql              (Entrega 3 - prueba de seguridad)
-- Usuario que lo ejecuta: U_GERENTE / Gerente2026
-- El gerente lee indicadores; no puede modificar nada.
-- ============================================================================
SELECT USER AS conectado_como FROM dual;

PROMPT ===== 1. Ocupacion 2025 por municipio (vista materializada) =====
SELECT municipio, ROUND(100 * SUM(noches_vendidas) / SUM(noches_disponibles), 2) AS pct_ocupacion
FROM   TURISMOUQ.MV_OCUPACION_MENSUAL WHERE anio = 2025
GROUP BY municipio ORDER BY pct_ocupacion DESC;

PROMPT ===== 2. Ingresos netos por mes (vista) =====
SELECT mes, SUM(ingreso_neto) AS ingreso_neto
FROM   TURISMOUQ.V_GERENCIA_INGRESOS_MES WHERE mes LIKE '2025-%'
GROUP BY mes ORDER BY mes;

PROMPT ===== 3. Liquidacion guardada =====
SELECT anio, mes, COUNT(*) AS alojamientos, SUM(valor_neto) AS neto
FROM   TURISMOUQ.LIQUIDACION_MENSUAL GROUP BY anio, mes ORDER BY anio, mes;

PROMPT ===== 4. Intentar modificar: falla (solo tiene SELECT) =====
DELETE FROM TURISMOUQ.LIQUIDACION_MENSUAL;

PROMPT ===== 5. Intentar leer la tabla de reservas: falla =====
SELECT COUNT(*) FROM TURISMOUQ.RESERVA;
