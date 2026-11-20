-- ============================================================================
-- TurismoUQ - 14_prueba_auditor.sql              (Entrega 3 - prueba de seguridad)
-- Usuario que lo ejecuta: U_AUDITOR / Auditor2026
-- El auditor solo lee la auditoria de tarifas.
-- ============================================================================
SELECT USER AS conectado_como FROM dual;

PROMPT ===== 1. Quien cambio tarifas y cuando (incluye los cambios de U_ADMIN_ALOJ) =====
SELECT id_sentencia, operacion, usuario_bd, equipo,
       TO_CHAR(fecha_hora, 'DD/MM/YYYY HH24:MI:SS') AS fecha_hora,
       alojamiento, habitacion, temporada, precio_anterior, precio_nuevo
FROM   TURISMOUQ.V_AUDITORIA_TARIFAS
ORDER BY id_sentencia DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT ===== 2. Intentar borrar la auditoria: falla =====
DELETE FROM TURISMOUQ.AUDITORIA_TARIFA;

PROMPT ===== 3. Intentar cambiar una tarifa: falla =====
UPDATE TURISMOUQ.TARIFA SET precio_noche = 1 WHERE ROWNUM = 1;
