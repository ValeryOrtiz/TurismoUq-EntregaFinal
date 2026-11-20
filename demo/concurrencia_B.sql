-- ============================================================================
-- TurismoUQ - Experimento de concurrencia - SESION B
-- Conexion: TURISMOUQ en una hoja NO COMPARTIDA (Ctrl+Shift+N en SQL
-- Developer): es otra sesion de Oracle, distinta de la sesion A.
-- Ejecutar CADA BLOQUE por separado, en el orden T1..T8 del script A.
-- Use el mismo cliente y la misma habitacion que en A.
-- ============================================================================
SET SERVEROUTPUT ON;
VARIABLE cli NUMBER
VARIABLE hab NUMBER
VARIABLE res NUMBER
VARIABLE val NUMBER
EXEC :cli := 1;
EXEC :hab := 2;

-- ============================================================================
-- PARTE 1: SIN BLOQUEO
-- ============================================================================
-- T2 (B): A ya inserto pero NO ha confirmado. Por lectura consistente, B no
--         ve la fila de A: la habitacion "parece" libre, B tambien inserta.
--         El disparador de solapes tampoco lo detecta, porque la fila de A
--         todavia no es visible para B.
EXEC sp_reservar_sin_bloqueo(:cli, :hab, DATE '2026-12-20', DATE '2026-12-23', :res);
PRINT res

-- T4 (B): confirma -> quedan dos reservas cruzadas (A lo muestra en T5)
COMMIT;

-- ============================================================================
-- PARTE 2: CON SELECT ... FOR UPDATE
-- ============================================================================
-- T7 (B): A tiene bloqueada la fila de la habitacion (T6). Este llamado se
--         queda ESPERANDO en el FOR UPDATE (el icono de ejecucion no termina).
--         Cuando A hace COMMIT (T8), B continua, ahora SI ve la reserva de A
--         y recibe:
--         ORA-20001: Habitacion no disponible: la habitacion ... ya esta reservada ...
EXEC pkg_turismo.sp_crear_reserva(:cli, :hab, DATE '2026-12-20', DATE '2026-12-23', 1, :res, :val, 'CONFIRMADA');

ROLLBACK;
