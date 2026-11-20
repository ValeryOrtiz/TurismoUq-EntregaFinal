-- ============================================================================
-- TurismoUQ - 08_indices.sql                          (Entrega 3 - indices)
-- Usuario que lo ejecuta: TURISMOUQ. Ejecutar despues de 07 (F5).
-- ----------------------------------------------------------------------------
-- Tres consultas que hoy recorren tablas completas (TABLE ACCESS FULL),
-- cada una con su plan ANTES y DESPUES del indice:
--   Q1  Historial de un cliente           -> indice COMPUESTO
--         IX_RESERVA_CLIENTE_ESTADO (cliente_id, estado, fecha_checkin)
--   Q2  Llegadas de un mes por estado     -> indice BASADO EN FUNCION
--         IX_RESERVA_MES_CHECKIN (TRUNC(fecha_checkin,'MM'), estado)
--   Q3  Estado de cuenta de una reserva   -> indice COMPUESTO que cubre la consulta
--         IX_PAGO_RESERVA (reserva_id, estado, monto)
--   Q4  CASO DONDE EL INDICE NO AYUDA: IX_RESERVA_ESTADO (estado)
-- ----------------------------------------------------------------------------
-- Como se mide (dos fuentes para cada consulta):
--   * EXPLAIN PLAN + DBMS_XPLAN.DISPLAY: el plan y el COSTO que estima el
--     optimizador (lo que pide el documento: "costo antes / despues").
--   * Ejecucion real con /*+ GATHER_PLAN_STATISTICS */ + DBMS_XPLAN.DISPLAY_CURSOR
--     ('ALLSTATS LAST'): filas reales (A-Rows), bloques leidos (Buffers) y
--     tiempo real (A-Time). Los Buffers son la medida mas estable: con
--     25.000 reservas las consultas tardan milisegundos y el tiempo varia con
--     la cache, pero los bloques leidos no.
--   * SET TIMING ON muestra ademas el tiempo transcurrido de cada consulta.
--   * Al final, un resumen tomado de V$SQL compara costo, bloques y tiempo.
-- Cada consulta lleva una etiqueta ('Q1_ANTES', 'Q1_DESPUES', ...) como
-- primera columna para encontrarla en V$SQL.
-- El script borra al inicio los indices que crea: es repetible.
-- ============================================================================

SET SERVEROUTPUT ON;
SET DEFINE OFF;
SET LINESIZE 200;
SET PAGESIZE 200;
SET TIMING ON;

-- ----------------------------------------------------------------------------
-- 0. Punto de partida: sin los indices de este script y con estadisticas
-- ----------------------------------------------------------------------------
BEGIN
    FOR i IN (SELECT index_name FROM user_indexes
               WHERE index_name IN ('IX_RESERVA_CLIENTE_ESTADO','IX_RESERVA_MES_CHECKIN',
                                    'IX_PAGO_RESERVA','IX_RESERVA_ESTADO')) LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
    END LOOP;
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO');
END;
/

-- Valores fijos de prueba (literales, para que el plan sea el mismo en cada
-- corrida): el cliente 1500, julio de 2025 y la reserva 12345.
SELECT 'cliente 1500'  AS dato, COUNT(*) AS filas FROM RESERVA WHERE cliente_id = 1500
UNION ALL
SELECT 'julio 2025', COUNT(*) FROM RESERVA WHERE fecha_checkin >= DATE '2025-07-01' AND fecha_checkin < DATE '2025-08-01'
UNION ALL
SELECT 'reserva 12345', COUNT(*) FROM PAGO WHERE reserva_id = 12345
UNION ALL
SELECT 'total RESERVA', COUNT(*) FROM RESERVA
UNION ALL
SELECT 'total PAGO', COUNT(*) FROM PAGO;

-- ============================================================================
-- Q1. HISTORIAL DE UN CLIENTE (indice compuesto)
-- Pregunta: "que estadias completadas tiene este cliente, de la mas reciente
-- a la mas antigua?" (la usa recepcion al atender a un cliente).
-- Problema: RESERVA no tiene indice por cliente_id (una FK sin indice), asi
-- que Oracle lee las 25.000 reservas para devolver unas pocas.
-- ============================================================================
PROMPT ===== Q1 ANTES: plan estimado =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q1_ANTES' FOR
SELECT 'Q1_ANTES' AS prueba, r.reserva_id, r.fecha_checkin, r.fecha_checkout, r.estado
FROM   RESERVA r
WHERE  r.cliente_id = 1500
AND    r.estado = 'COMPLETADA'
ORDER BY r.fecha_checkin DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q1_ANTES', 'TYPICAL'));

PROMPT ===== Q1 ANTES: ejecucion real =====
SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q1_ANTES' AS prueba, r.reserva_id, r.fecha_checkin, r.fecha_checkout, r.estado
FROM   RESERVA r
WHERE  r.cliente_id = 1500
AND    r.estado = 'COMPLETADA'
ORDER BY r.fecha_checkin DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q1_ANTES''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

-- Indice compuesto: igualdad en cliente_id y estado (las dos primeras
-- columnas) y fecha_checkin como tercera, que ademas entrega las filas ya
-- ordenadas (Oracle puede evitar el SORT ORDER BY recorriendo el indice al reves).
CREATE INDEX IX_RESERVA_CLIENTE_ESTADO ON RESERVA (cliente_id, estado, fecha_checkin);

PROMPT ===== Q1 DESPUES: plan estimado =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q1_DESPUES' FOR
SELECT 'Q1_DESPUES' AS prueba, r.reserva_id, r.fecha_checkin, r.fecha_checkout, r.estado
FROM   RESERVA r
WHERE  r.cliente_id = 1500
AND    r.estado = 'COMPLETADA'
ORDER BY r.fecha_checkin DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q1_DESPUES', 'TYPICAL'));

PROMPT ===== Q1 DESPUES: ejecucion real =====
SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q1_DESPUES' AS prueba, r.reserva_id, r.fecha_checkin, r.fecha_checkout, r.estado
FROM   RESERVA r
WHERE  r.cliente_id = 1500
AND    r.estado = 'COMPLETADA'
ORDER BY r.fecha_checkin DESC;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q1_DESPUES''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

-- ============================================================================
-- Q2. LLEGADAS DE UN MES POR ESTADO (indice basado en funcion)
-- Pregunta: "cuantas reservas llegan en julio de 2025 y en que estado
-- estan?" (planeacion de recepcion; la C4 agrupa por mes de la misma forma).
-- Problema: el filtro aplica una funcion a la columna,
--     TRUNC(fecha_checkin, 'MM') = DATE '2025-07-01'
-- y un indice normal sobre fecha_checkin NO serviria: el indice guarda
-- fechas, no el resultado de TRUNC. Se indexa la expresion misma.
-- ============================================================================
PROMPT ===== Q2 ANTES: plan estimado =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q2_ANTES' FOR
SELECT 'Q2_ANTES' AS prueba, r.estado, COUNT(*) AS reservas
FROM   RESERVA r
WHERE  TRUNC(r.fecha_checkin, 'MM') = DATE '2025-07-01'
GROUP BY r.estado;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q2_ANTES', 'TYPICAL'));

PROMPT ===== Q2 ANTES: ejecucion real =====
SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q2_ANTES' AS prueba, r.estado, COUNT(*) AS reservas
FROM   RESERVA r
WHERE  TRUNC(r.fecha_checkin, 'MM') = DATE '2025-07-01'
GROUP BY r.estado;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q2_ANTES''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

-- Indice basado en funcion: guarda TRUNC(fecha_checkin,'MM') ya calculado.
-- Se agrega estado como segunda columna para que la consulta se resuelva
-- solo con el indice (sin ir a la tabla).
CREATE INDEX IX_RESERVA_MES_CHECKIN ON RESERVA (TRUNC(fecha_checkin, 'MM'), estado);

-- Un indice basado en funcion crea una columna virtual oculta: sin
-- estadisticas sobre ella el optimizador estima mal cuantas filas devuelve.
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA', method_opt => 'FOR ALL HIDDEN COLUMNS SIZE AUTO');

PROMPT ===== Q2 DESPUES: plan estimado =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q2_DESPUES' FOR
SELECT 'Q2_DESPUES' AS prueba, r.estado, COUNT(*) AS reservas
FROM   RESERVA r
WHERE  TRUNC(r.fecha_checkin, 'MM') = DATE '2025-07-01'
GROUP BY r.estado;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q2_DESPUES', 'TYPICAL'));

PROMPT ===== Q2 DESPUES: ejecucion real =====
SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q2_DESPUES' AS prueba, r.estado, COUNT(*) AS reservas
FROM   RESERVA r
WHERE  TRUNC(r.fecha_checkin, 'MM') = DATE '2025-07-01'
GROUP BY r.estado;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q2_DESPUES''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

-- ============================================================================
-- Q3. ESTADO DE CUENTA DE UNA RESERVA (indice compuesto que cubre la consulta)
-- Pregunta: "cuanto ha pagado esta reserva?" (es la consulta que ejecuta
-- pkg_turismo.fn_total_pagado en cada reserva y en cada pago).
-- Problema: PAGO no tiene indice por reserva_id (otra FK sin indice): cada
-- consulta de saldo recorre todos los pagos.
-- ============================================================================
PROMPT ===== Q3 ANTES: plan estimado =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_ANTES' FOR
SELECT 'Q3_ANTES' AS prueba,
       SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto WHEN 'REEMBOLSADO' THEN -p.monto ELSE 0 END) AS pagado
FROM   PAGO p
WHERE  p.reserva_id = 12345;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q3_ANTES', 'TYPICAL'));

PROMPT ===== Q3 ANTES: ejecucion real =====
SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q3_ANTES' AS prueba,
       SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto WHEN 'REEMBOLSADO' THEN -p.monto ELSE 0 END) AS pagado
FROM   PAGO p
WHERE  p.reserva_id = 12345;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q3_ANTES''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

-- Indice compuesto que CUBRE la consulta: reserva_id para encontrar los
-- pagos y estado y monto para calcular la suma sin leer la tabla
-- (INDEX RANGE SCAN sin TABLE ACCESS BY INDEX ROWID).
CREATE INDEX IX_PAGO_RESERVA ON PAGO (reserva_id, estado, monto);

PROMPT ===== Q3 DESPUES: plan estimado =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_DESPUES' FOR
SELECT 'Q3_DESPUES' AS prueba,
       SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto WHEN 'REEMBOLSADO' THEN -p.monto ELSE 0 END) AS pagado
FROM   PAGO p
WHERE  p.reserva_id = 12345;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q3_DESPUES', 'TYPICAL'));

PROMPT ===== Q3 DESPUES: ejecucion real =====
SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q3_DESPUES' AS prueba,
       SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto WHEN 'REEMBOLSADO' THEN -p.monto ELSE 0 END) AS pagado
FROM   PAGO p
WHERE  p.reserva_id = 12345;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q3_DESPUES''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

-- ============================================================================
-- Q4. CASO DONDE EL INDICE NO AYUDA: indice sobre RESERVA(estado)
-- Pregunta: "cuantas noches suman las reservas completadas?"
-- ----------------------------------------------------------------------------
-- Por que no ayuda (explicacion tecnica):
--   1. Baja selectividad: estado solo tiene 4 valores y COMPLETADA es mas o
--      menos la mitad de las 25.000 reservas. Un indice sirve para encontrar
--      POCAS filas; para traer la mitad de la tabla es mas barato leerla
--      completa.
--   2. Lectura multibloque vs. un bloque a la vez: el TABLE ACCESS FULL lee
--      la tabla en bloques contiguos, varios por cada lectura (multiblock
--      read). El acceso por indice salta de la hoja del indice a un bloque de
--      la tabla por cada ROWID (lecturas de un solo bloque).
--   3. Factor de agrupamiento (clustering factor) alto: las reservas
--      COMPLETADA estan repartidas por toda la tabla, no juntas, asi que por
--      el indice casi cada fila obliga a visitar un bloque distinto y el mismo
--      bloque se visita muchas veces. Se ve en USER_INDEXES.CLUSTERING_FACTOR,
--      cercano al numero de filas y no al de bloques.
-- Resultado esperado: con el indice creado el optimizador SIGUE eligiendo
-- TABLE ACCESS FULL. Si se le obliga con el hint INDEX, la consulta lee MAS
-- bloques que sin el. Y el indice no es gratis: cada INSERT y UPDATE de
-- estado lo debe mantener. Conclusion: se elimina.
-- ============================================================================
CREATE INDEX IX_RESERVA_ESTADO ON RESERVA (estado);

PROMPT ===== Q4: el optimizador decide (ignora el indice) =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q4_OPTIMIZADOR' FOR
SELECT 'Q4_OPTIMIZADOR' AS prueba, COUNT(*) AS reservas, SUM(r.fecha_checkout - r.fecha_checkin) AS noches
FROM   RESERVA r
WHERE  r.estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q4_OPTIMIZADOR', 'TYPICAL'));

SELECT /*+ GATHER_PLAN_STATISTICS */ 'Q4_OPTIMIZADOR' AS prueba, COUNT(*) AS reservas,
       SUM(r.fecha_checkout - r.fecha_checkin) AS noches
FROM   RESERVA r
WHERE  r.estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS */ ''Q4_OPTIMIZADOR''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

PROMPT ===== Q4: forzando el indice con un hint (lee mas bloques) =====
EXPLAIN PLAN SET STATEMENT_ID = 'Q4_FORZADO' FOR
SELECT /*+ INDEX(r IX_RESERVA_ESTADO) */ 'Q4_FORZADO' AS prueba, COUNT(*) AS reservas,
       SUM(r.fecha_checkout - r.fecha_checkin) AS noches
FROM   RESERVA r
WHERE  r.estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'Q4_FORZADO', 'TYPICAL'));

SELECT /*+ GATHER_PLAN_STATISTICS INDEX(r IX_RESERVA_ESTADO) */ 'Q4_FORZADO' AS prueba, COUNT(*) AS reservas,
       SUM(r.fecha_checkout - r.fecha_checkin) AS noches
FROM   RESERVA r
WHERE  r.estado = 'COMPLETADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    (SELECT sql_id FROM v$sql WHERE sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS INDEX(r IX_RESERVA_ESTADO) */ ''Q4_FORZADO''%'
      ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY), NULL, 'ALLSTATS LAST +COST'));

PROMPT ===== Q4: por que (selectividad y factor de agrupamiento) =====
SELECT estado, COUNT(*) AS filas, ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
FROM   RESERVA GROUP BY estado ORDER BY filas DESC;

SELECT i.index_name, i.distinct_keys, i.clustering_factor,
       t.num_rows AS filas_tabla, t.blocks AS bloques_tabla
FROM   user_indexes i JOIN user_tables t ON t.table_name = i.table_name
WHERE  i.index_name IN ('IX_RESERVA_ESTADO', 'IX_RESERVA_CLIENTE_ESTADO');

-- No sirve y cuesta mantenerlo: se elimina
DROP INDEX IX_RESERVA_ESTADO;

-- ============================================================================
-- RESUMEN (seccion 7.3 del documento): costo estimado, bloques leidos y
-- tiempo por ejecucion de cada consulta, tomados de V$SQL.
-- ============================================================================
PROMPT ===== Resumen antes / despues =====
SELECT SUBSTR(sql_text, INSTR(sql_text, '''Q') + 1,
              INSTR(sql_text, '''', INSTR(sql_text, '''Q') + 1) - INSTR(sql_text, '''Q') - 1) AS prueba,
       optimizer_cost                                         AS costo,
       ROUND(buffer_gets / GREATEST(executions, 1))           AS bloques_leidos,
       ROUND(elapsed_time / GREATEST(executions, 1) / 1000, 3) AS tiempo_ms
FROM   v$sql
WHERE  sql_text LIKE 'SELECT /*+ GATHER_PLAN_STATISTICS%''Q%'
AND    parsing_schema_name = USER
AND    last_active_time > SYSDATE - 1/24
ORDER BY 1;

-- Indices que quedan creados
SELECT index_name, index_type, table_name, uniqueness, status
FROM   user_indexes
WHERE  index_name IN ('IX_RESERVA_CLIENTE_ESTADO','IX_RESERVA_MES_CHECKIN','IX_PAGO_RESERVA')
ORDER BY index_name;

SELECT index_name, column_expression
FROM   user_ind_expressions
WHERE  index_name = 'IX_RESERVA_MES_CHECKIN';

SET TIMING OFF;
PROMPT 08_indices.sql terminado.
