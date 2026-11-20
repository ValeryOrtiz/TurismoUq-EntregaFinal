-- ============================================================================
-- TurismoUQ - 00_usuario_y_tablespaces.sql
-- Usuario que lo ejecuta: SYSTEM, conectado a la PDB (FREEPDB1 o XEPDB1,
-- con "Nombre del servicio", no SID). NO ejecutar en CDB$ROOT.
-- ----------------------------------------------------------------------------
-- Que hace:
--   1. Borra (si existen) el usuario TURISMOUQ y todos sus objetos, para
--      empezar siempre en una base limpia.
--   2. Crea el tablespace TS_TURISMO_HISTORICO con su datafile (el historico
--      de reservas vive alli; la justificacion esta en el script 06).
--   3. Crea el usuario TURISMOUQ, dueno del esquema, con cuota en USERS y en
--      el tablespace del historico, y le da solo los privilegios que
--      necesitan los scripts 01 a 10.
-- Despues: crear en SQL Developer una conexion como TURISMOUQ / TurismoUQ2026
-- (mismo host, puerto y nombre de servicio) y ejecutar con ella 01 a 08 y 10.
-- ============================================================================

SET SERVEROUTPUT ON;
SET DEFINE OFF;

-- ----------------------------------------------------------------------------
-- 1. Limpieza: usuarios de seguridad (script 09) y el dueno del esquema.
--    Se cierran antes sus sesiones abiertas, si las hay.
-- ----------------------------------------------------------------------------
DECLARE
    PROCEDURE ejecutar(p_sql VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN NULL;   -- el objeto no existia
    END;
BEGIN
    FOR s IN (SELECT sid, serial# AS ser FROM v$session
               WHERE username IN ('TURISMOUQ','U_RECEPCION','U_ADMIN_ALOJ',
                                  'U_GERENTE','U_AUDITOR')) LOOP
        ejecutar('ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.ser || ''' IMMEDIATE');
    END LOOP;
    FOR u IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
                'U_RECEPCION','U_ADMIN_ALOJ','U_GERENTE','U_AUDITOR','TURISMOUQ'))) LOOP
        ejecutar('DROP USER ' || u.nombre || ' CASCADE');
    END LOOP;
    FOR r IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
                'R_RECEPCION','R_ADMIN_ALOJAMIENTO','R_GERENTE','R_AUDITOR'))) LOOP
        ejecutar('DROP ROLE ' || r.nombre);
    END LOOP;
    ejecutar('DROP PROFILE PERFIL_TURISMOUQ CASCADE');
    DBMS_OUTPUT.PUT_LINE('Limpieza terminada.');
END;
/

-- ----------------------------------------------------------------------------
-- 2. Tablespace del historico de reservas.
--    La ruta del datafile se calcula sola:
--      * si la base usa OMF (db_create_file_dest), Oracle nombra el archivo;
--      * si no, se usa la misma carpeta de los datafiles de la PDB
--        (en el contenedor gvenzl: /opt/oracle/oradata/FREE/FREEPDB1/).
--    Si el tablespace ya existe (ORA-01543) se reutiliza.
-- ----------------------------------------------------------------------------
DECLARE
    v_omf  VARCHAR2(512);
    v_ruta VARCHAR2(600);
    v_sql  VARCHAR2(1000);
BEGIN
    SELECT value INTO v_omf FROM v$parameter WHERE name = 'db_create_file_dest';

    IF v_omf IS NOT NULL THEN
        v_sql := 'CREATE TABLESPACE TS_TURISMO_HISTORICO ' ||
                 'DATAFILE SIZE 50M AUTOEXTEND ON NEXT 10M MAXSIZE 1G ' ||
                 'EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO';
    ELSE
        SELECT file_name INTO v_ruta
          FROM dba_data_files
         WHERE tablespace_name = 'SYSTEM' AND ROWNUM = 1;
        v_ruta := SUBSTR(v_ruta, 1, GREATEST(INSTR(v_ruta, '/', -1), INSTR(v_ruta, '\', -1)));
        v_sql := 'CREATE TABLESPACE TS_TURISMO_HISTORICO ' ||
                 'DATAFILE ''' || v_ruta || 'ts_turismo_historico01.dbf'' ' ||
                 'SIZE 50M REUSE AUTOEXTEND ON NEXT 10M MAXSIZE 1G ' ||
                 'EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO';
    END IF;

    EXECUTE IMMEDIATE v_sql;
    DBMS_OUTPUT.PUT_LINE('Tablespace creado: ' || v_sql);
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -1543 THEN
            DBMS_OUTPUT.PUT_LINE('El tablespace TS_TURISMO_HISTORICO ya existia; se reutiliza.');
        ELSE
            RAISE;
        END IF;
END;
/

-- ----------------------------------------------------------------------------
-- 3. Usuario dueno del esquema
-- ----------------------------------------------------------------------------
CREATE USER TURISMOUQ IDENTIFIED BY "TurismoUQ2026"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    QUOTA UNLIMITED ON USERS
    QUOTA UNLIMITED ON TS_TURISMO_HISTORICO;

-- Privilegios de sistema que necesitan los scripts 01 a 10 (nada de DBA)
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE MATERIALIZED VIEW,
      CREATE JOB
   TO TURISMOUQ;

-- Lectura del diccionario para los planes de ejecucion del script 08
-- (DBMS_XPLAN.DISPLAY_CURSOR lee V$SQL y V$SQL_PLAN_STATISTICS_ALL)
GRANT SELECT_CATALOG_ROLE TO TURISMOUQ;

-- Verificacion
SELECT username, default_tablespace, account_status, created
FROM   dba_users
WHERE  username = 'TURISMOUQ';

SELECT tablespace_name, file_name, ROUND(bytes / 1024 / 1024) AS mb, autoextensible,
       ROUND(maxbytes / 1024 / 1024) AS max_mb
FROM   dba_data_files
WHERE  tablespace_name = 'TS_TURISMO_HISTORICO';

SELECT tablespace_name,
       DECODE(max_bytes, -1, 'ILIMITADA', ROUND(max_bytes / 1024 / 1024) || ' MB') AS cuota
FROM   dba_ts_quotas
WHERE  username = 'TURISMOUQ';

PROMPT 00 terminado. Conectese como TURISMOUQ / TurismoUQ2026 y ejecute 01_ddl.sql.
