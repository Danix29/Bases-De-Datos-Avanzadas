DROP TABLE IF EXISTS estudiantes CASCADE;

CREATE TABLE estudiantes (
    estudiante_id INT,
    nombre VARCHAR(50),
    codigo_carrera INT,
    edad INT,
    indice INT
);

\copy estudiantes FROM 'C:/temp/datos_estudiantes.csv' DELIMITER ',' CSV HEADER

ANALYZE estudiantes;