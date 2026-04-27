<img src="https://capsule-render.vercel.app/api?type=waving&color=316192&height=160&section=header&text=bda-postgresql-storage&fontSize=30&fontColor=FFFFFF&fontAlignY=40&desc=Bases%20de%20Datos%20Avanzadas%20%7C%20UAH%202025-26&descAlignY=60&descColor=9FE1CB" width="100%"/>

<div align="center">

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-1D9E75?style=for-the-badge&logoColor=white)
![UAH](https://img.shields.io/badge/UAH-GII-085041?style=for-the-badge)

</div>

---

## About

**Practica 1 — Arquitectura PostgreSQL y Almacenamiento Fisico**
Asignatura: Bases de Datos Avanzadas · UAH · Curso 2025-26

Deep dive into PostgreSQL internal architecture: physical file organization, block factor analysis, indexing structures (B-Tree and Hash), table partitioning and I/O monitoring. All work done over a table of **30 million records**.

---

## Content overview

### Part 1 — File organization

| Question | Topic |
|----------|-------|
| Q0 | PostgreSQL logging configuration (DDL + DML + line prefix with DNI) |
| Q1 | DB creation · table `estudiantes` · 30M record generator in Python |
| Q2 | Theoretical vs real block factor · SQL query to obtain real factor |
| Q3 | Sequential scan with `indice = 500` · blocks read · pg_statio monitoring |
| Q4 | Repeat Q3 · buffer cache effect · blocks read comparison |
| Q5 | Physically ordered table `estudiantes2` (ORDER BY indice) · block count |
| Q6 | Repeat Q3 on `estudiantes2` · clustered vs unclustered comparison |
| Q7 | Delete 5M random tuples · physical effect · dead tuples · table size |
| Q8 | Insert new tuple · physical location · system columns (ctid) |
| Q9 | VACUUM FULL + ANALYZE · space recovery · physical result |
| Q10 | Hash partitioning `estudiantes3` by `codigo_carrera mod 20` · block count per partition |
| Q11 | Repeat Q3 on `estudiantes3` · partitioning vs sequential scan comparison |

### Part 2 — Indexing

| Question | Topic |
|----------|-------|
| Q12 | Rebuild `estudiantes2` (ordered by indice) with 30M records |
| Q13 | B-Tree index on `estudiante_id` · physical location · size · levels · tuples per block |
| Q14 | Theoretical B-Tree size and levels · comparison with Q13 |
| Q15 | Hash index on `estudiante_id` · size · buckets · tuples per bucket |
| Q16 | Theoretical Hash size and buckets · comparison with Q15 |
| Q17 | B-Tree index on `indice` · size · levels · tuples per block |
| Q18 | Theoretical B-Tree for `indice` · comparison with Q17 |
| Q19 | Hash index on `indice` · size · buckets · distribution |
| Q20 | Theoretical Hash for `indice` · comparison with Q19 |
| Q21 | Conclusions: B-Tree vs Hash · theory vs practice |

### Part 3 — I/O Monitoring

| Question | Topic |
|----------|-------|
| Q22 | B-Tree indexes on `indice` and `codigo_carrera` · Hash indexes on `estudiante_id` and `indice` |
| Q23 | 7 queries monitored with `pg_statio_*` — filters, aggregations, range scans, insert |
| Q24 | Multi-key B-Tree index on `(codigo_carrera, indice)` |
| Q25 | 4 queries with multi-key index · AND vs OR · prefix vs non-prefix access |
| Q26 | Partition by `edad` · 4 queries · partition pruning analysis |
| Q27 | Final conclusions on PostgreSQL data access patterns |

---

## Key concepts applied

```
Physical storage     Block factor (theoretical vs real) · heap files · OIDs · pg_relation_filepath
Dead tuples          DELETE behavior · VACUUM FULL · ANALYZE · pg_statio
B-Tree index         Levels · pages per level · tuples per block · pgstatindex
Hash index           Buckets · fill factor · pgstatindex
Partitioning         Hash mod N · range by field · partition pruning
I/O monitoring       pg_statio_user_tables · pg_statio_user_indexes · heap_blks_read/hit
```

---

## Tools used

```sql
-- Physical inspection
SELECT pg_relation_filepath('estudiantes');
SELECT pg_size_pretty(pg_total_relation_size('estudiantes'));

-- Index analysis
SELECT * FROM pgstatindex('idx_btree_estudiante_id');
SELECT * FROM pgstatindex('idx_hash_estudiante_id');

-- I/O monitoring (Cumulative Statistics System)
SELECT heap_blks_read, heap_blks_hit
FROM pg_statio_user_tables WHERE relname = 'estudiantes';

SELECT idx_blks_read, idx_blks_hit
FROM pg_statio_user_indexes WHERE indexrelname = 'idx_name';

-- Reset stats before each query
SELECT pg_stat_reset();
```

---

## Data generator

```python
# Python — generates 30M records
# codigo_carrera: random [0, 100]
# edad:           random [18, 40]
# indice:         random [0, 10000]
python generar_datos.py --rows 30000000 --output estudiantes.csv
```

Load into PostgreSQL:
```sql
COPY estudiantes(nombre, codigo_carrera, edad, indice)
FROM '/path/to/estudiantes.csv'
WITH (FORMAT csv, DELIMITER ',');
```

---

## Deliverables

```
DNI1DNI2_PL1.zip
├── PL1-BDA_2025-26.pdf     ← original PDF with answers filled in
├── postgresql.log           ← log file with DDL/DML queries
└── generar_datos.py         ← data generator script
```

---

<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=316192&height=100&section=footer" width="100%"/>

*Bases de Datos Avanzadas · UAH GII · 2025-26*

</div>
