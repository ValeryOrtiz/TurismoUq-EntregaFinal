-- ============================================================================
-- TurismoUQ - Experimento de concurrencia - MONITOR (conexion SYSTEM)
-- Ejecutar en el momento T7, mientras la sesion B esta esperando.
-- Muestra que la sesion B esta bloqueada por la sesion A y por que.
-- ============================================================================
SELECT s.sid, s.serial#, s.username, s.status, s.event,
       s.blocking_session AS bloqueada_por, s.seconds_in_wait AS segundos_esperando
FROM   v$session s
WHERE  s.username = 'TURISMOUQ'
ORDER BY s.sid;

-- Bloqueos de fila (TX) y de tabla (TM) de las dos sesiones
SELECT l.sid, l.type, DECODE(l.lmode, 0,'ninguno', 2,'row-S', 3,'row-X', 6,'exclusivo', l.lmode) AS modo_tomado,
       DECODE(l.request, 0,'-', 6,'exclusivo', l.request) AS modo_pedido, l.block AS bloquea_a_otro
FROM   v$lock l JOIN v$session s ON s.sid = l.sid
WHERE  s.username = 'TURISMOUQ' AND l.type IN ('TX','TM')
ORDER BY l.sid, l.type;
