-- ============================================================================
-- TurismoUQ - 12_prueba_admin_alojamiento.sql    (Entrega 3 - prueba de seguridad)
-- Usuario que lo ejecuta: U_ADMIN_ALOJ / AdminAloj2026
-- El administrador de alojamiento solo ve y cambia lo de SUS alojamientos.
-- ============================================================================
SET SERVEROUTPUT ON;
SELECT USER AS conectado_como FROM dual;

PROMPT ===== 1. Sus reservas (solo de sus alojamientos) =====
SELECT alojamiento, COUNT(*) AS lineas FROM TURISMOUQ.V_ADMIN_MIS_RESERVAS GROUP BY alojamiento;

PROMPT ===== 2. Sus tarifas: cuantas habitaciones y temporadas ve =====
SELECT COUNT(DISTINCT habitacion_id) AS habitaciones, COUNT(*) AS tarifas
FROM   TURISMOUQ.V_ADMIN_MIS_TARIFAS;

PROMPT ===== 3. Sube 2.000 el precio de una de SUS tarifas (temporada 2027) =====
VARIABLE hab  NUMBER
VARIABLE temp NUMBER
EXEC SELECT MIN(habitacion_id), MAX(temporada_id) INTO :hab, :temp FROM TURISMOUQ.V_ADMIN_MIS_TARIFAS;
UPDATE TURISMOUQ.V_ADMIN_MIS_TARIFAS SET precio_noche = precio_noche + 2000
WHERE  habitacion_id = :hab AND temporada_id = :temp;
-- se deja como estaba (la auditoria registra las dos sentencias con su usuario)
UPDATE TURISMOUQ.V_ADMIN_MIS_TARIFAS SET precio_noche = precio_noche - 2000
WHERE  habitacion_id = :hab AND temporada_id = :temp;
COMMIT;

PROMPT ===== 4. Un UPDATE sin filtro solo alcanza SUS tarifas, no las de toda la plataforma =====
-- "N filas actualizadas" debe ser igual al conteo del paso 2, no a todas las
-- tarifas de TARIFA. El precio no cambia (se asigna el mismo valor), asi que
-- la auditoria no registra nada, y se deshace con ROLLBACK.
UPDATE TURISMOUQ.V_ADMIN_MIS_TARIFAS SET precio_noche = precio_noche;
ROLLBACK;

PROMPT ===== 5. Intentar cambiar otra columna: falla (solo tiene UPDATE de precio_noche) =====
UPDATE TURISMOUQ.V_ADMIN_MIS_TARIFAS SET temporada_id = temporada_id WHERE habitacion_id = :hab;

PROMPT ===== 6. Intentar leer la tabla TARIFA directamente: falla =====
SELECT COUNT(*) FROM TURISMOUQ.TARIFA;
ROLLBACK;
