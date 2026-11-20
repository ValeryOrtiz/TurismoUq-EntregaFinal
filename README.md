# TurismoUQ — Proyecto integrador Bases de Datos II (grupo 01N)

Valery Andrea Ortiz Mesa · Jhonatan David Vivas Arango
Docente: Carolina Londoño Idárraga — Universidad del Quindío, 2026-2

Base de datos Oracle de una plataforma de reservas de alojamiento para los 12 municipios del Quindío: el modelo, la lógica en PL/SQL y su administración (transacciones, índices y seguridad).

## Requisitos

- Oracle Database con una PDB (probado en Oracle AI Database 26ai Free en Docker, imagen `gvenzl/oracle-free`; sirve también Oracle XE 21c con `XEPDB1`).
- Oracle SQL Developer.
- Conexión como `SYSTEM` a la PDB con **nombre de servicio** (`FREEPDB1` o `XEPDB1`), no SID.

## Orden de ejecución

Cada script se ejecuta completo con **F5** (Ejecutar script).

| # | Script | Usuario | Qué hace |
|---|--------|---------|----------|
| 00 | `scripts/00_usuario_y_tablespaces.sql` | SYSTEM | Borra y crea el usuario `TURISMOUQ` y el tablespace `TS_TURISMO_HISTORICO` |
| 01 | `scripts/01_ddl.sql` | TURISMOUQ | Tablas, llaves y restricciones |
| 02 | `scripts/02_carga.sql` | TURISMOUQ | Datos con el volumen mínimo (2 a 5 minutos) |
| 03 | `scripts/03_consultas_analisis.sql` | TURISMOUQ | Las 7 consultas de la Entrega 1 |
| 04 | `scripts/04_paquete.sql` | TURISMOUQ | Paquete `PKG_TURISMO`: función, procedimientos y cursor |
| 05 | `scripts/05_disparadores.sql` | TURISMOUQ | Auditoría de TARIFA, solapes, reseñas y temporadas |
| 06 | `scripts/06_vista_materializada.sql` | TURISMOUQ | Histórico en su tablespace y vista materializada de ocupación |
| 07 | `scripts/07_transacciones.sql` | TURISMOUQ | Reserva y pago con SAVEPOINT; rollback parcial |
| 08 | `scripts/08_indices.sql` | TURISMOUQ | Índices y planes de ejecución antes y después |
| 09 | `scripts/09_seguridad.sql` | SYSTEM | Perfil, vistas, 4 roles y usuarios de prueba |
| 10 | `scripts/10_pruebas.sql` | TURISMOUQ | Pruebas de las Entregas 2 y 3 (repetibles) |
| 11 | `scripts/11_prueba_recepcion.sql` | U_RECEPCION | Recepción solo entra por vistas |
| 12 | `scripts/12_prueba_admin_alojamiento.sql` | U_ADMIN_ALOJ | Administrador ve y cambia solo lo suyo |
| 13 | `scripts/13_prueba_gerente.sql` | U_GERENTE | Gerente solo lee indicadores |
| 14 | `scripts/14_prueba_auditor.sql` | U_AUDITOR | Auditor solo lee la auditoría |
| 15 | `scripts/15_prueba_perfil.sql` | SYSTEM | Límites del perfil y limpieza de las pruebas de seguridad |

Contraseñas del ambiente del curso: `TURISMOUQ / TurismoUQ2026`, `U_RECEPCION / Recepcion2026`, `U_ADMIN_ALOJ / AdminAloj2026`, `U_GERENTE / Gerente2026`, `U_AUDITOR / Auditor2026`.

El experimento de concurrencia (dos sesiones) está en `demo/concurrencia_*.sql`. Las hojas de trabajo del video están en `demo/video_*.sql`, y `demo/datos_para_documento.sql` saca los números que usa el documento final.

## Otros archivos

- `docs/TurismoUQ_01N_Ortiz_Vivas.docx`: documento final, hecho sobre la plantilla.
- `docs/build_doc.py`: genera el documento a partir de la plantilla y de los resultados de la ejecución.
- `video/diapositivas_turismouq.html`: diapositivas de apoyo del video (sin resultados; todo se ejecuta en vivo).
- `video/guion_video_turismouq.docx`: guion del video por bloques, con el reparto entre los dos integrantes.

## Cómo comprobar que quedó bien

- Al final, `02_carga.sql` imprime los conteos de las tablas, `solapes_habitacion = 0` y el tiempo de la carga.
- `10_pruebas.sql` imprime OK o FALLO en cada prueba. Su último bloque compara la base con el estado inicial: la suma de tarifas y los conteos de reservas, líneas, pagos y clientes deben decir OK.

## Correcciones tras la retroalimentación

**Entrega 1**
- UNIQUE en el correo del cliente.
- Temporadas de 2024 a 2027 sin huecos ni cruces.
- RESERVA_SERVICIO con más de 40.000 filas.
- Pagos calculados desde TARIFA.
- 0 solapes.
- C2 agrupada con el año de la temporada.
- C5 con `VARIABLE` y `EXEC`.
- C6 con UNPIVOT sobre columnas reales.

**Entrega 2**
- El disparador de solapes ahora es compuesto: valida en AFTER STATEMENT, así que funciona con `INSERT ... SELECT` y `UPDATE` sin ORA-04091.
- La auditoría de tarifas compara de forma segura frente a NULL.
- Las pruebas son repetibles: trabajan con un cliente propio, restauran las tarifas y al final verifican que la base quedó igual.

**Además**
- Fecha de cancelación en RESERVA con la regla de reembolso del 80 % (`sp_cancelar_reserva`).
- Disparador que valida las reseñas.
- Disparador que impide temporadas cruzadas.
- Ingreso neto = pagos exitosos menos reembolsos.
