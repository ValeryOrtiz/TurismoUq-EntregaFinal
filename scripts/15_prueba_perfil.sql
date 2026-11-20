-- ============================================================================
-- TurismoUQ - 15_prueba_perfil.sql               (Entrega 3 - prueba del perfil)
-- Usuario que lo ejecuta: SYSTEM, al final de las pruebas 11 a 14.
-- Se usa junto con pruebas manuales:
--
-- A) SESSIONS_PER_USER = 2
--    Abra en SQL Developer tres hojas NO COMPARTIDAS (Ctrl+Shift+N) con la
--    conexion de U_GERENTE. Las dos primeras conectan; la tercera recibe
--    ORA-02391: exceeded simultaneous SESSIONS_PER_USER limit.
--    Durante la prueba, ejecute el bloque A de este script: muestra las 2 sesiones.
--
-- B) FAILED_LOGIN_ATTEMPTS = 3
--    Cree una conexion de U_AUDITOR con una contrasena equivocada e intente
--    conectar tres veces (ORA-01017). Al tercer intento la cuenta queda
--    bloqueada; el cuarto intento, aun con la contrasena correcta, recibe
--    ORA-28000: The account is locked. El bloque B lo muestra y la desbloquea.
--
-- C) IDLE_TIME = 15
--    Deje una sesion de U_GERENTE quieta mas de 15 minutos y ejecute algo:
--    ORA-02396: exceeded maximum idle time, please connect again.
-- ============================================================================

PROMPT ===== A. Sesiones abiertas por usuario =====
SELECT username, COUNT(*) AS sesiones
FROM   v$session
WHERE  username LIKE 'U\_%' ESCAPE '\'
GROUP BY username;

PROMPT ===== B. Estado de las cuentas (U_AUDITOR debe salir LOCKED(TIMED) tras 3 fallos) =====
SELECT username, account_status, lock_date, profile
FROM   dba_users
WHERE  username LIKE 'U\_%' ESCAPE '\'
ORDER BY username;

-- Desbloqueo manual (el administrador no tiene que esperar la hora)
ALTER USER U_AUDITOR ACCOUNT UNLOCK;

SELECT username, account_status FROM dba_users WHERE username = 'U_AUDITOR';

-- ============================================================================
-- Limpieza de las pruebas de seguridad: se borran las reservas que creo
-- U_RECEPCION en 11_prueba_recepcion.sql (cliente PRUEBA-RECEPCION).
-- Despues de esto la base queda igual que antes de las pruebas.
-- ============================================================================
DELETE FROM TURISMOUQ.PAGO WHERE reserva_id IN
    (SELECT reserva_id FROM TURISMOUQ.RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM TURISMOUQ.CLIENTE WHERE documento_identidad = 'PRUEBA-RECEPCION'));
DELETE FROM TURISMOUQ.RESERVA_HABITACION WHERE reserva_id IN
    (SELECT reserva_id FROM TURISMOUQ.RESERVA WHERE cliente_id IN
        (SELECT cliente_id FROM TURISMOUQ.CLIENTE WHERE documento_identidad = 'PRUEBA-RECEPCION'));
DELETE FROM TURISMOUQ.RESERVA WHERE cliente_id IN
    (SELECT cliente_id FROM TURISMOUQ.CLIENTE WHERE documento_identidad = 'PRUEBA-RECEPCION');
DELETE FROM TURISMOUQ.CLIENTE WHERE documento_identidad = 'PRUEBA-RECEPCION';
COMMIT;

SELECT COUNT(*) AS clientes_de_prueba_restantes
FROM   TURISMOUQ.CLIENTE
WHERE  documento_identidad = 'PRUEBA-RECEPCION';
