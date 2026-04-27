-- =========================================================================
-- PRÁCTICA 1 - ADMINISTRACIÓN DE BASES DE DATOS (PostgreSQL)
-- Script completo optimizado: Cuestión 1 a 11
-- =========================================================================

-- =========================================================================
-- CUESTIÓN 1: Creación de la tabla base y carga masiva de datos
-- =========================================================================
-- Limpiamos ejecuciones anteriores para evitar errores
DROP TABLE IF EXISTS estudiantes CASCADE;

-- Creamos la estructura lógica de la tabla heap (montón)
CREATE TABLE estudiantes (
    estudiante_id INT,
    nombre VARCHAR(50),
    codigo_carrera INT,
    edad INT,
    indice INT
);

-- [!] IMPORTANTE: Cambia esta ruta por la ruta real de tu archivo de 30 millones de registros.
-- Si estás en psql en Windows, usa una ruta absoluta como 'C:\ruta\datos.csv'
\copy estudiantes FROM 'C:/temp/datos_estudiantes.csv' DELIMITER ',' CSV HEADER

-- Actualizamos las estadísticas internas para que el optimizador conozca los datos recién cargados
ANALYZE estudiantes;

-- =========================================================================
-- CUESTIÓN 2: Análisis del tamaño físico inicial
-- =========================================================================
-- Comprobamos cuántas tuplas tiene y cuántos bloques (páginas de 8KB) ocupa en disco
SELECT relname AS tabla, reltuples AS tuplas, relpages AS bloques 
FROM pg_class 
WHERE relname = 'estudiantes';

-- =========================================================================
-- CUESTIÓN 3 y 4: Rendimiento de búsqueda en tabla desordenada
-- =========================================================================
-- 1. Reiniciamos las estadísticas de la tabla para medir desde cero
SELECT pg_stat_reset_single_table_counters('estudiantes'::regclass);

-- 2. Ejecutamos la consulta (Sequential Scan obligado al no haber índice)
SELECT count(*) FROM estudiantes WHERE indice = 500;

-- 3. Verificamos que ha tenido que leer toda la tabla física del disco
SELECT relname AS tabla, heap_blks_read AS bloques_leidos_disco 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. Verificamos que la correlación (orden físico vs lógico) es cercana a 0
SELECT attname, n_distinct, correlation 
FROM pg_stats 
WHERE tablename = 'estudiantes' AND attname = 'indice';

-- =========================================================================
-- CUESTIÓN 5: Creación de tabla ordenada físicamente
-- =========================================================================
DROP TABLE IF EXISTS estudiantes2 CASCADE;

-- Creamos una copia de la tabla ordenando físicamente las filas por 'indice'
CREATE TABLE estudiantes2 AS 
SELECT * FROM estudiantes 
ORDER BY indice ASC;

ANALYZE estudiantes2;

-- Comparamos tamaños: Ambas ocupan lo mismo porque el orden no afecta al tamaño total
SELECT relname AS tabla, reltuples AS tuplas, relpages AS bloques 
FROM pg_class 
WHERE relname IN ('estudiantes', 'estudiantes2')
ORDER BY relname;

-- =========================================================================
-- CUESTIÓN 6: Rendimiento de búsqueda en tabla ordenada
-- =========================================================================
SELECT pg_stat_reset_single_table_counters('estudiantes2'::regclass);

-- Ejecutamos la misma consulta
SELECT count(*) FROM estudiantes2 WHERE indice = 500;

-- Observamos que SIGUE LEYENDO TODOS LOS BLOQUES (no hace búsqueda dicotómica en disco)
SELECT relname AS tabla, heap_blks_read AS bloques_leidos_disco 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes2';

-- Sin embargo, confirmamos que la correlación ahora es 1 (perfectamente ordenada)
SELECT attname, n_distinct, correlation 
FROM pg_stats 
WHERE tablename = 'estudiantes2' AND attname = 'indice';

-- =========================================================================
-- CUESTIÓN 7: Borrado masivo y MVCC (Tuplas Muertas)
-- =========================================================================
-- Borramos exactamente 5.000.000 de registros (1 de cada 6)
DELETE FROM estudiantes WHERE estudiante_id % 6 = 0;

-- Comprobamos que el tamaño de la tabla NO disminuye (para evitar bloqueos)
SELECT relname AS tabla, relpages AS bloques 
FROM pg_class 
WHERE relname = 'estudiantes';

-- Confirmamos que MVCC simplemente las ha marcado como tuplas "muertas"
SELECT relname AS tabla, n_live_tup AS vivas, n_dead_tup AS muertas 
FROM pg_stat_user_tables 
WHERE relname = 'estudiantes';

-- =========================================================================
-- CUESTIÓN 8: Inserción y CTID (Ubicación física)
-- =========================================================================
INSERT INTO estudiantes (estudiante_id, nombre, codigo_carrera, edad, indice) 
VALUES (99999999, 'Estudiante Nuevo', 10, 22, 500);

-- Buscamos sus coordenadas físicas: se inserta al final del archivo (último bloque)
SELECT ctid, estudiante_id, nombre 
FROM estudiantes 
WHERE estudiante_id = 99999999;

-- =========================================================================
-- CUESTIÓN 9: Mantenimiento y recuperación de espacio
-- =========================================================================
-- Reescribimos el archivo físico saltándonos las tuplas muertas
VACUUM FULL ANALYZE estudiantes;

-- Verificamos la reducción drástica de bloques (recuperación real de espacio en disco)
SELECT relname AS tabla, relpages AS bloques 
FROM pg_class 
WHERE relname = 'estudiantes';

-- Verificamos que las tuplas muertas ahora son 0
SELECT relname AS tabla, n_live_tup AS vivas, n_dead_tup AS muertas 
FROM pg_stat_user_tables 
WHERE relname = 'estudiantes';

-- =========================================================================
-- CUESTIÓN 10: Particionamiento Hash
-- =========================================================================
DROP TABLE IF EXISTS estudiantes3 CASCADE;

-- Creamos la tabla "padre" lógica que enrutará los datos
CREATE TABLE estudiantes3 (
    estudiante_id INT,
    nombre VARCHAR(50),
    codigo_carrera INT,
    edad INT,
    indice INT
) PARTITION BY HASH (codigo_carrera);

-- Automatizamos la creación de las 20 tablas físicas (hijas) usando PL/pgSQL
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 0..19 LOOP
        EXECUTE format('CREATE TABLE estudiantes3_p%s PARTITION OF estudiantes3 FOR VALUES WITH (MODULUS 20, REMAINDER %s)', i, i);
    END LOOP;
END $$;

-- Volcamos los 25 millones de registros vivos a la estructura particionada
INSERT INTO estudiantes3 SELECT * FROM estudiantes;

ANALYZE estudiantes3;

-- Vemos la distribución no uniforme de tuplas y bloques por partición
SELECT relname AS particion, reltuples AS tuplas, relpages AS bloques 
FROM pg_class 
WHERE relname LIKE 'estudiantes3_p%' 
ORDER BY relname;

-- =========================================================================
-- CUESTIÓN 11: Rendimiento en tabla particionada sin usar la clave
-- =========================================================================
-- Reiniciamos estadísticas a nivel global para limpiar las métricas de las 20 particiones
SELECT pg_stat_reset();

-- Hacemos una consulta por un campo que NO es la clave de partición
SELECT count(*) FROM estudiantes3 WHERE indice = 500;

-- Comprobamos que, al no poder hacer "Partition Pruning", lee el 100% de los bloques sumados
SELECT sum(heap_blks_read) AS total_bloques_leidos_disco
FROM pg_statio_user_tables 
WHERE relname LIKE 'estudiantes3_p%';

-- =========================================================================
-- CUESTIÓN 12: Limpieza y preparación
-- =========================================================================
DROP TABLE IF EXISTS estudiantes, estudiantes2, estudiantes3 CASCADE;

CREATE TABLE estudiantes_temp (
    estudiante_id INT,
    nombre VARCHAR(50),
    codigo_carrera INT,
    edad INT,
    indice INT
);

-- [!] OJO: Esta es la ruta que funcionaba, asegúrate de que es correcta
\copy estudiantes_temp FROM 'C:/temp/datos_estudiantes.csv' DELIMITER ',' CSV HEADER

CREATE TABLE estudiantes2 AS 
SELECT * FROM estudiantes_temp 
ORDER BY indice ASC;

DROP TABLE estudiantes_temp;

ANALYZE estudiantes2;

-- =========================================================================
-- CUESTIÓN 13: Creación y análisis del Índice B-Tree
-- =========================================================================
-- Activar las extensiones necesarias
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- Crear el índice B-Tree sobre estudiante_id (puede tardar un ratito)
CREATE INDEX idx_estid_btree ON estudiantes2 USING btree(estudiante_id);

-- 1. ¿Dónde se almacena y qué tamaño tiene?
SELECT 
    pg_relation_filepath('idx_estid_btree') AS ubicacion_fisica,
    pg_size_pretty(pg_relation_size('idx_estid_btree')) AS tamaño_legible,
    relpages AS total_bloques
FROM pg_class 
WHERE relname = 'idx_estid_btree';

-- 2. Analizar la cabecera (metapage) para ver niveles
SELECT level AS nivel_raiz, fastlevel 
FROM bt_metap('idx_estid_btree');

-- 3. Analizar bloques internos y hoja
SELECT 
    version,
    tree_level,
    internal_pages AS bloques_internos,
    leaf_pages AS bloques_hoja
FROM pgstatindex('idx_estid_btree');

--CUESTIÓN 15

-- 1. Aseguramos que la extensión necesaria esté activa (por si acaso)
CREATE EXTENSION IF NOT EXISTS pageinspect;

-- 2. Si ya existe, lo borramos para que la creación sea limpia y no dé error
DROP INDEX IF EXISTS idx_estid_hash;

-- 3. Creamos el índice Hash sobre la columna estudiante_id
-- Nota: En tablas de 30M de filas, esto puede tardar un par de minutos
CREATE INDEX idx_estid_hash ON estudiantes2 USING hash(estudiante_id);

-- 4. CONSULTA DE TAMAÑO Y UBICACIÓN FÍSICA
-- Aquí veremos tus 1022 MB y los 130.774 bloques
SELECT 
    pg_relation_filepath('idx_estid_hash') AS ruta_fisica,
    pg_size_pretty(pg_relation_size('idx_estid_hash')) AS tamaño_legible,
    relpages AS total_bloques
FROM pg_class 
WHERE relname = 'idx_estid_hash';

-- 5. CONSULTA DE ESTADÍSTICAS INTERNAS (Sin errores de tipo)
-- Al poner 'idx_estid_hash'::regclass, PostgreSQL lo identifica perfectamente
SELECT 
    magic, 
    version, 
    ntuples AS registros_indexados, 
    ffactor AS factor_relleno, 
    bsize AS tamaño_bucket_bytes
FROM hash_metap('idx_estid_hash');
SELECT * FROM hash_metap('idx_estid_hash'::text);

--CUESTIÓN 17

--Para crear el índice de tipo árbol
CREATE INDEX idx_indice_btree ON estudiantes2(indice);

--Para consultar ruta, tamaño y bloques totales
SELECT 
    pg_relation_filepath('idx_indice_btree') AS ruta,
    pg_size_pretty(pg_relation_size('idx_indice_btree')) AS tamaño,
    relpages AS bloques
FROM pg_class WHERE relname = 'idx_indice_btree';

--Y para consultar niveles y bloque raíz
SELECT magic, version, root, level FROM bt_metap('idx_indice_btree');


--CUESTIÓN 19

-- 1. Crear el índice hash (si ya existe por pruebas anteriores, lo borramos primero)
DROP INDEX IF EXISTS idx_indice_hash;
CREATE INDEX idx_indice_hash ON estudiantes2 USING hash(indice);

-- 2. Obtener ruta física, tamaño y número de bloques
SELECT 
    pg_relation_filepath('idx_indice_hash') AS ruta,
    pg_size_pretty(pg_relation_size('idx_indice_hash')) AS tamaño,
    relpages AS bloques
FROM pg_class 
WHERE relname = 'idx_indice_hash';

-- 3. Obtener el número de cajones (buckets) corregido
-- Usamos maxbucket + 1 porque el conteo empieza en 0
SELECT maxbucket + 1 AS nbuckets 
FROM hash_metapage_info(get_raw_page('idx_indice_hash', 0));

-- 4. Cálculo de la media de tuplas por cajón
-- (Asumiendo los 30 millones de registros de la tabla)
SELECT (30000000 / (maxbucket + 1)) AS media_tuplas_cajon
FROM hash_metapage_info(get_raw_page('idx_indice_hash', 0));

---------------------------------------------------
--Datos
---------------------------------------------------

DROP TABLE IF EXISTS estudiantes CASCADE;

CREATE TABLE estudiantes (
    estudiante_id SERIAL,
    nombre VARCHAR(50),
    codigo_carrera INT,
    edad INT,
    indice INT
);

TRUNCATE TABLE estudiantes;

COPY estudiantes(estudiante_id, nombre, codigo_carrera, edad, indice) 
FROM 'C:/temp/datos_estudiantes.csv' WITH (FORMAT csv, DELIMITER ',');

-- Índices tipo Árbol (B-Tree)
CREATE INDEX idx_tree_indice ON estudiantes USING btree (indice);
CREATE INDEX idx_tree_carrera ON estudiantes USING btree (codigo_carrera);

-- Índices tipo Hash
CREATE INDEX idx_hash_est_id ON estudiantes USING hash (estudiante_id);
CREATE INDEX idx_hash_indice ON estudiantes USING hash (indice);

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
SELECT COUNT(*) FROM estudiantes WHERE codigo_carrera = 50;
SELECT * FROM estudiantes WHERE codigo_carrera = 50;

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
SELECT COUNT(*) FROM estudiantes WHERE estudiante_id = 80000;
SELECT * FROM estudiantes WHERE estudiante_id = 80000;

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
SELECT COUNT(*) FROM estudiantes WHERE indice BETWEEN 100 AND 200;
SELECT * FROM estudiantes WHERE indice BETWEEN 100 AND 200;

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
SELECT COUNT(*) FROM estudiantes WHERE edad = 20;

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
SELECT indice, COUNT(*) FROM estudiantes GROUP BY indice;

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
SELECT codigo_carrera, AVG(edad) FROM estudiantes GROUP BY codigo_carrera;

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';

-- 1. REINICIAR ESTADÍSTICAS (Ejecutar SIEMPRE antes de cada select)
SELECT pg_stat_reset();

-- 2. EJECUTAR LA CONSULTA (Ver las 7 consultas abajo)
INSERT INTO estudiantes (nombre, codigo_carrera, edad, indice) 
VALUES ('Juan Perez', 10, 20, 100);

-- 3. VER BLOQUES LEÍDOS DE LA TABLA (Heap)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname = 'estudiantes';

-- 4. VER BLOQUES LEÍDOS DE LOS ÍNDICES
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes 
WHERE relname = 'estudiantes';


-- 1. Borrar los índices individuales creados en el apartado anterior
DROP INDEX IF EXISTS idx_tree_indice;
DROP INDEX IF EXISTS idx_tree_carrera;
DROP INDEX IF EXISTS idx_hash_est_id;
DROP INDEX IF EXISTS idx_hash_indice;

-- 2. Crear el índice multiclave tipo árbol (B-Tree)
CREATE INDEX idx_multiclave_carrera_indice 
ON estudiantes USING btree (codigo_carrera, indice);

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar Consulta 1
SELECT * FROM estudiantes WHERE codigo_carrera = 20 AND indice = 500;

-- 2. Ejecutar Consulta 2
--SELECT * FROM estudiantes WHERE codigo_carrera = 50 OR indice = 900;

-- 2. Ejecutar Consulta 3
--SELECT * FROM estudiantes WHERE indice = 300;

-- 2. Ejecutar Consulta 4
--SELECT * FROM estudiantes WHERE codigo_carrera = 80;

-- 3. Ver bloques de la tabla
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables WHERE relname = 'estudiantes';

-- 4. Ver bloques del índice
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes WHERE relname = 'estudiantes';

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar Consulta 2
SELECT * FROM estudiantes WHERE codigo_carrera = 50 OR indice = 900;

-- 2. Ejecutar Consulta 3
--SELECT * FROM estudiantes WHERE indice = 300;

-- 2. Ejecutar Consulta 4
--SELECT * FROM estudiantes WHERE codigo_carrera = 80;

-- 3. Ver bloques de la tabla
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables WHERE relname = 'estudiantes';

-- 4. Ver bloques del índice
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes WHERE relname = 'estudiantes';

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar Consulta 3
SELECT * FROM estudiantes WHERE indice = 300;

-- 2. Ejecutar Consulta 4
--SELECT * FROM estudiantes WHERE codigo_carrera = 80;

-- 3. Ver bloques de la tabla
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables WHERE relname = 'estudiantes';

-- 4. Ver bloques del índice
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes WHERE relname = 'estudiantes';

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar Consulta 4
SELECT * FROM estudiantes WHERE codigo_carrera = 80;

-- 3. Ver bloques de la tabla
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables WHERE relname = 'estudiantes';

-- 4. Ver bloques del índice
SELECT indexrelname, idx_blks_read, idx_blks_hit 
FROM pg_statio_user_indexes WHERE relname = 'estudiantes';

-- 1. Borrar la tabla antigua si existía para limpiar el entorno
DROP TABLE IF EXISTS estudiantes3 CASCADE;

-- 2. Crear la estructura de la tabla padre particionada por lista según la edad
CREATE TABLE estudiantes3 (
    estudiante_id integer,
    nombre character varying(50),
    codigo_carrera integer,
    edad integer,
    indice integer
) PARTITION BY LIST (edad);

-- 3. Crear automáticamente las particiones (edades del 15 al 100)
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 15..100 LOOP
        EXECUTE format('CREATE TABLE estudiantes3_edad_%s PARTITION OF estudiantes3 FOR VALUES IN (%s)', i, i);
    END LOOP;
END $$;

-- 4. Volcar todos los datos a la nueva estructura limpia
INSERT INTO estudiantes3 SELECT * FROM estudiantes;

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar la Consulta 1
SELECT COUNT(*) FROM estudiantes3 WHERE edad = 25;

-- 2. Ejecutar la Consulta 2
--SELECT * FROM estudiantes3 WHERE edad IN (20, 25, 30);

-- 2. Ejecutar la Consulta 3
--SELECT * FROM estudiantes3 WHERE edad BETWEEN 25 AND 30;

-- 2. Ejecutar la Consulta 4
--SELECT * FROM estudiantes3 WHERE edad > 50;

-- 3. Ver bloques de la tabla (solo las particiones que se han leído)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname LIKE 'estudiantes3%' 
  AND (heap_blks_read > 0 OR heap_blks_hit > 0);

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar la Consulta 2
SELECT * FROM estudiantes3 WHERE edad IN (20, 25, 30);

-- 2. Ejecutar la Consulta 3
--SELECT * FROM estudiantes3 WHERE edad BETWEEN 25 AND 30;

-- 2. Ejecutar la Consulta 4
--SELECT * FROM estudiantes3 WHERE edad > 50;

-- 3. Ver bloques de la tabla (solo las particiones que se han leído)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname LIKE 'estudiantes3%' 
  AND (heap_blks_read > 0 OR heap_blks_hit > 0);

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar la Consulta 3
SELECT * FROM estudiantes3 WHERE edad BETWEEN 25 AND 30;

-- 2. Ejecutar la Consulta 4
--SELECT * FROM estudiantes3 WHERE edad > 50;

-- 3. Ver bloques de la tabla (solo las particiones que se han leído)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname LIKE 'estudiantes3%' 
  AND (heap_blks_read > 0 OR heap_blks_hit > 0);

-- 1. Reiniciar estadísticas
SELECT pg_stat_reset();

-- 2. Ejecutar la Consulta 4
SELECT * FROM estudiantes3 WHERE edad > 50;

-- 3. Ver bloques de la tabla (solo las particiones que se han leído)
SELECT relname, heap_blks_read, heap_blks_hit 
FROM pg_statio_user_tables 
WHERE relname LIKE 'estudiantes3%' 
  AND (heap_blks_read > 0 OR heap_blks_hit > 0);