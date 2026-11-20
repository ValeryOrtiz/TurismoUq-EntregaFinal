-- ============================================================================
-- TurismoUQ - 09_seguridad.sql                       (Entrega 3 - seguridad)
-- Usuario que lo ejecuta: SYSTEM, conectado a la PDB (FREEPDB1 / XEPDB1).
-- Ejecutar despues de 08 (los objetos de TURISMOUQ ya deben existir).
-- ----------------------------------------------------------------------------
--   1. Perfil PERFIL_TURISMOUQ con limites de sesion y de contrasena.
--   2. Vistas en el esquema TURISMOUQ: son la UNICA puerta de recepcion,
--      del administrador de alojamiento y del auditor.
--   3. Cuatro roles con privilegios diferenciados:
--        R_RECEPCION          consulta disponibilidad, clientes y reservas por
--                             vistas y registra reservas con un procedimiento;
--                             nunca toca tablas.
--        R_ADMIN_ALOJAMIENTO  ve y cambia SOLO las tarifas y reservas de los
--                             alojamientos que tiene asignados (vistas
--                             filtradas por el usuario conectado).
--        R_GERENTE            solo lectura de indicadores: vista
--                             materializada, liquidacion, historico, ingresos.
--        R_AUDITOR            solo lectura de la auditoria de tarifas.
--   4. Un usuario de prueba por rol, todos con el perfil.
-- El script borra al inicio lo que crea: es repetible.
-- ----------------------------------------------------------------------------
-- Usuarios de prueba (contrasenas solo para el ambiente del curso):
--   U_RECEPCION / Recepcion2026      U_ADMIN_ALOJ / AdminAloj2026
--   U_GERENTE   / Gerente2026        U_AUDITOR    / Auditor2026
-- ============================================================================

SET SERVEROUTPUT ON;
SET DEFINE OFF;

-- ----------------------------------------------------------------------------
-- 0. Limpieza (idempotente)
-- ----------------------------------------------------------------------------
DECLARE
    PROCEDURE ejecutar(p_sql VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
BEGIN
    FOR s IN (SELECT sid, serial# AS ser FROM v$session
               WHERE username IN ('U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR')) LOOP
        ejecutar('ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.ser || ''' IMMEDIATE');
    END LOOP;
    FOR u IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
                'U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR'))) LOOP
        ejecutar('DROP USER ' || u.nombre || ' CASCADE');
    END LOOP;
    FOR r IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
                'R_RECEPCION','R_ADMIN_ALOJAMIENTO','R_GERENTE','R_AUDITOR'))) LOOP
        ejecutar('DROP ROLE ' || r.nombre);
    END LOOP;
    ejecutar('DROP PROFILE PERFIL_TURISMOUQ CASCADE');
END;
/

-- ============================================================================
-- 1. PERFIL CON LIMITES DE SESION
-- ----------------------------------------------------------------------------
--   SESSIONS_PER_USER 2      maximo dos sesiones abiertas a la vez por usuario
--                            (la tercera recibe ORA-02391)
--   IDLE_TIME 15             minutos de inactividad antes de cerrar la sesion
--                            (la siguiente instruccion recibe ORA-02396)
--   CONNECT_TIME 480         una sesion dura como maximo un turno (8 horas)
--   FAILED_LOGIN_ATTEMPTS 3  al tercer intento fallido se bloquea la cuenta
--                            (ORA-28000)
--   PASSWORD_LOCK_TIME 1/24  la cuenta queda bloqueada 1 hora
--   PASSWORD_LIFE_TIME 90    la contrasena vence a los 90 dias
-- Los limites de recursos (SESSIONS_PER_USER, IDLE_TIME, CONNECT_TIME) solo
-- se aplican si RESOURCE_LIMIT = TRUE (valor por defecto desde Oracle 12c).
-- ============================================================================
CREATE PROFILE PERFIL_TURISMOUQ LIMIT
    SESSIONS_PER_USER      2
    IDLE_TIME              15
    CONNECT_TIME           480
    FAILED_LOGIN_ATTEMPTS  3
    PASSWORD_LOCK_TIME     1/24
    PASSWORD_LIFE_TIME     90;

BEGIN
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET RESOURCE_LIMIT = TRUE';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('RESOURCE_LIMIT no se pudo cambiar desde la PDB: ' || SQLERRM);
END;
/
SELECT name, value FROM v$parameter WHERE name = 'resource_limit';

-- ============================================================================
-- 2. VISTAS (se crean dentro del esquema TURISMOUQ)
-- ============================================================================
ALTER SESSION SET CURRENT_SCHEMA = TURISMOUQ;

-- ---------------- Recepcion ----------------
-- Habitaciones con su alojamiento, capacidad y la tarifa de la temporada de hoy
CREATE OR REPLACE VIEW V_RECEPCION_HABITACIONES AS
SELECT h.habitacion_id, a.alojamiento_id, a.nombre_comercial AS alojamiento,
       mu.nombre AS municipio, h.numero, h.tipo_habitacion, h.capacidad_maxima,
       t.nombre || ' ' || t.anio AS temporada_actual, ta.precio_noche AS tarifa_hoy
FROM   HABITACION h
JOIN   ALOJAMIENTO a  ON a.alojamiento_id = h.alojamiento_id
JOIN   MUNICIPIO   mu ON mu.municipio_id  = a.municipio_id
LEFT JOIN TEMPORADA t ON TRUNC(SYSDATE) BETWEEN t.fecha_inicio AND t.fecha_fin
LEFT JOIN TARIFA   ta ON ta.habitacion_id = h.habitacion_id AND ta.temporada_id = t.temporada_id;

-- Ocupacion futura: que noches ya estan tomadas (sin datos del cliente)
CREATE OR REPLACE VIEW V_RECEPCION_OCUPACION AS
SELECT rh.habitacion_id, rh.fecha_checkin, rh.fecha_checkout, r.estado
FROM   RESERVA_HABITACION rh
JOIN   RESERVA r ON r.reserva_id = rh.reserva_id
WHERE  r.estado IN ('PENDIENTE', 'CONFIRMADA')
AND    rh.fecha_checkout >= TRUNC(SYSDATE);

-- Clientes: datos de contacto, sin nada mas
CREATE OR REPLACE VIEW V_RECEPCION_CLIENTES AS
SELECT cliente_id, nombre, documento_identidad, correo, telefono, ciudad_origen
FROM   CLIENTE;

-- Reservas activas de hoy en adelante, con el cliente y el saldo
CREATE OR REPLACE VIEW V_RECEPCION_RESERVAS AS
SELECT r.reserva_id, c.nombre AS cliente, c.documento_identidad, r.fecha_checkin,
       r.fecha_checkout, r.estado,
       pkg_turismo.fn_valor_reserva(r.reserva_id) AS valor_total,
       pkg_turismo.fn_total_pagado(r.reserva_id)  AS pagado
FROM   RESERVA r
JOIN   CLIENTE c ON c.cliente_id = r.cliente_id
WHERE  r.estado IN ('PENDIENTE', 'CONFIRMADA')
AND    r.fecha_checkout >= TRUNC(SYSDATE);

-- ---------------- Administrador de alojamiento ----------------
-- Solo los alojamientos asignados al usuario conectado (USUARIO_SISTEMA.usuario_bd)
CREATE OR REPLACE VIEW V_ADMIN_MIS_TARIFAS AS
SELECT ta.habitacion_id, ta.temporada_id, ta.precio_noche
FROM   TARIFA ta
WHERE  ta.habitacion_id IN (
         SELECT h.habitacion_id
         FROM   HABITACION h
         JOIN   USUARIO_ALOJAMIENTO ua ON ua.alojamiento_id = h.alojamiento_id
         JOIN   USUARIO_SISTEMA     us ON us.usuario_id     = ua.usuario_id
         WHERE  us.usuario_bd = SYS_CONTEXT('USERENV', 'SESSION_USER'));
-- Es actualizable (una sola tabla en el FROM). El administrador solo recibe
-- UPDATE sobre precio_noche, asi que no puede mover una tarifa a una
-- habitacion ajena; y un UPDATE sobre la vista solo alcanza las filas que
-- ella muestra, es decir, las de sus propios alojamientos.

CREATE OR REPLACE VIEW V_ADMIN_MIS_RESERVAS AS
SELECT r.reserva_id, a.nombre_comercial AS alojamiento, h.numero AS habitacion,
       rh.fecha_checkin, rh.fecha_checkout, rh.num_huespedes, r.estado
FROM   RESERVA r
JOIN   RESERVA_HABITACION  rh ON rh.reserva_id     = r.reserva_id
JOIN   HABITACION          h  ON h.habitacion_id   = rh.habitacion_id
JOIN   ALOJAMIENTO         a  ON a.alojamiento_id  = h.alojamiento_id
JOIN   USUARIO_ALOJAMIENTO ua ON ua.alojamiento_id = a.alojamiento_id
JOIN   USUARIO_SISTEMA     us ON us.usuario_id     = ua.usuario_id
WHERE  us.usuario_bd = SYS_CONTEXT('USERENV', 'SESSION_USER');

-- ---------------- Gerente ----------------
CREATE OR REPLACE VIEW V_GERENCIA_INGRESOS_MES AS
SELECT TO_CHAR(r.fecha_checkin, 'YYYY-MM') AS mes,
       mu.nombre AS municipio,
       SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto ELSE -p.monto END) AS ingreso_neto
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
GROUP BY TO_CHAR(r.fecha_checkin, 'YYYY-MM'), mu.nombre;

-- ---------------- Auditor ----------------
CREATE OR REPLACE VIEW V_AUDITORIA_TARIFAS AS
SELECT au.id_sentencia, au.operacion, au.fecha_hora, au.usuario_bd, au.usuario_so,
       au.equipo, a.nombre_comercial AS alojamiento, h.numero AS habitacion,
       t.nombre || ' ' || t.anio AS temporada, au.precio_anterior, au.precio_nuevo
FROM   AUDITORIA_TARIFA au
LEFT JOIN HABITACION  h ON h.habitacion_id  = au.habitacion_id
LEFT JOIN ALOJAMIENTO a ON a.alojamiento_id = h.alojamiento_id
LEFT JOIN TEMPORADA   t ON t.temporada_id   = au.temporada_id;

ALTER SESSION SET CURRENT_SCHEMA = SYSTEM;

-- ============================================================================
-- 3. ROLES Y PRIVILEGIOS
-- ============================================================================
CREATE ROLE R_RECEPCION;
CREATE ROLE R_ADMIN_ALOJAMIENTO;
CREATE ROLE R_GERENTE;
CREATE ROLE R_AUDITOR;

GRANT CREATE SESSION TO R_RECEPCION, R_ADMIN_ALOJAMIENTO, R_GERENTE, R_AUDITOR;

-- Recepcion: solo vistas de lectura + el procedimiento que registra reserva
-- y pago. EXECUTE sobre el procedimiento NO da acceso a las tablas: el
-- procedimiento corre con los permisos de su dueno (definer rights).
GRANT SELECT ON TURISMOUQ.V_RECEPCION_HABITACIONES TO R_RECEPCION;
GRANT SELECT ON TURISMOUQ.V_RECEPCION_OCUPACION    TO R_RECEPCION;
GRANT SELECT ON TURISMOUQ.V_RECEPCION_CLIENTES     TO R_RECEPCION;
GRANT SELECT ON TURISMOUQ.V_RECEPCION_RESERVAS     TO R_RECEPCION;
GRANT EXECUTE ON TURISMOUQ.SP_RESERVAR_Y_PAGAR     TO R_RECEPCION;

-- Administrador de alojamiento: lee sus tarifas y cambia SOLO el precio
-- (UPDATE de una columna); sus reservas en solo lectura.
GRANT SELECT, UPDATE (precio_noche) ON TURISMOUQ.V_ADMIN_MIS_TARIFAS TO R_ADMIN_ALOJAMIENTO;
GRANT SELECT ON TURISMOUQ.V_ADMIN_MIS_RESERVAS TO R_ADMIN_ALOJAMIENTO;

-- Gerente: indicadores en solo lectura
GRANT SELECT ON TURISMOUQ.MV_OCUPACION_MENSUAL    TO R_GERENTE;
GRANT SELECT ON TURISMOUQ.LIQUIDACION_MENSUAL     TO R_GERENTE;
GRANT SELECT ON TURISMOUQ.RESERVA_HISTORICO       TO R_GERENTE;
GRANT SELECT ON TURISMOUQ.V_GERENCIA_INGRESOS_MES TO R_GERENTE;

-- Auditor: solo lectura de la auditoria
GRANT SELECT ON TURISMOUQ.AUDITORIA_TARIFA    TO R_AUDITOR;
GRANT SELECT ON TURISMOUQ.V_AUDITORIA_TARIFAS TO R_AUDITOR;

-- ============================================================================
-- 4. USUARIOS DE PRUEBA (uno por rol, todos con el perfil)
-- ============================================================================
CREATE USER U_RECEPCION  IDENTIFIED BY "Recepcion2026" PROFILE PERFIL_TURISMOUQ;
CREATE USER U_ADMIN_ALOJ IDENTIFIED BY "AdminAloj2026" PROFILE PERFIL_TURISMOUQ;
CREATE USER U_GERENTE    IDENTIFIED BY "Gerente2026"   PROFILE PERFIL_TURISMOUQ;
CREATE USER U_AUDITOR    IDENTIFIED BY "Auditor2026"   PROFILE PERFIL_TURISMOUQ;

GRANT R_RECEPCION         TO U_RECEPCION;
GRANT R_ADMIN_ALOJAMIENTO TO U_ADMIN_ALOJ;
GRANT R_GERENTE           TO U_GERENTE;
GRANT R_AUDITOR           TO U_AUDITOR;

-- U_ADMIN_ALOJ es la cuenta del encargado 'encargado.hotel1@turismouq.co'
-- (02_carga.sql llena USUARIO_SISTEMA.usuario_bd); sus vistas muestran solo
-- los alojamientos asignados a ese encargado.
SELECT us.nombre, us.usuario_bd, a.alojamiento_id, a.nombre_comercial
FROM   TURISMOUQ.USUARIO_SISTEMA us
JOIN   TURISMOUQ.USUARIO_ALOJAMIENTO ua ON ua.usuario_id = us.usuario_id
JOIN   TURISMOUQ.ALOJAMIENTO a ON a.alojamiento_id = ua.alojamiento_id
WHERE  us.usuario_bd = 'U_ADMIN_ALOJ';

-- Cliente que usa 11_prueba_recepcion.sql; 15_prueba_perfil.sql borra sus
-- reservas al final, asi las pruebas no dejan datos.
MERGE INTO TURISMOUQ.CLIENTE c
USING (SELECT 'PRUEBA-RECEPCION' AS doc FROM dual) x
ON (c.documento_identidad = x.doc)
WHEN NOT MATCHED THEN
    INSERT (nombre, documento_identidad, correo, ciudad_origen)
    VALUES ('Cliente de pruebas de recepcion', 'PRUEBA-RECEPCION', 'prueba.recepcion@turismouq.co', 'Armenia');
COMMIT;

-- ============================================================================
-- 5. VERIFICACION
-- ============================================================================
SELECT grantee AS rol, privilege, table_name AS objeto
FROM   dba_tab_privs
WHERE  grantee LIKE 'R\_%' ESCAPE '\'
AND    owner = 'TURISMOUQ'
ORDER BY grantee, table_name, privilege;

SELECT grantee AS rol, privilege, table_name AS objeto, column_name
FROM   dba_col_privs
WHERE  grantee LIKE 'R\_%' ESCAPE '\';

SELECT grantee AS usuario, granted_role AS rol
FROM   dba_role_privs
WHERE  grantee LIKE 'U\_%' ESCAPE '\'
ORDER BY grantee;

SELECT username, profile, account_status
FROM   dba_users
WHERE  username LIKE 'U\_%' ESCAPE '\'
ORDER BY username;

SELECT resource_name, limit
FROM   dba_profiles
WHERE  profile = 'PERFIL_TURISMOUQ'
AND    resource_name IN ('SESSIONS_PER_USER','IDLE_TIME','CONNECT_TIME',
                         'FAILED_LOGIN_ATTEMPTS','PASSWORD_LOCK_TIME','PASSWORD_LIFE_TIME')
ORDER BY resource_name;

PROMPT 09_seguridad.sql terminado.
