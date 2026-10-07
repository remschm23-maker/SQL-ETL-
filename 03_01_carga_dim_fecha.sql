-- ============================================================
-- Script 02.01 - Carga de dimension fecha
-- DW - Databricks SQL / Delta
-- No crea tablas; carga sobre dw.gold.dim_fecha
-- ============================================================

USE CATALOG dw;
USE SCHEMA gold;

-- Parametros del rango de fechas del laboratorio
CREATE OR REPLACE TEMP VIEW vw_parametros_dim_fecha AS
SELECT DATE '2025-01-01' AS fecha_inicio,
       DATE '2026-12-31' AS fecha_fin;

CREATE OR REPLACE TEMP VIEW vw_src_dim_fecha AS
SELECT
  CAST(date_format(f.fecha, 'yyyyMMdd') AS INT) AS id_fecha,
  f.fecha AS fecha,
  YEAR(f.fecha) AS anio,
  MONTH(f.fecha) AS mes,
  CASE MONTH(f.fecha)
    WHEN 1 THEN 'enero'
    WHEN 2 THEN 'febrero'
    WHEN 3 THEN 'marzo'
    WHEN 4 THEN 'abril'
    WHEN 5 THEN 'mayo'
    WHEN 6 THEN 'junio'
    WHEN 7 THEN 'julio'
    WHEN 8 THEN 'agosto'
    WHEN 9 THEN 'septiembre'
    WHEN 10 THEN 'octubre'
    WHEN 11 THEN 'noviembre'
    WHEN 12 THEN 'diciembre'
  END AS nombre_mes,
  QUARTER(f.fecha) AS trimestre,
  DAY(f.fecha) AS dia,
  CASE dayofweek(f.fecha)
    WHEN 1 THEN 'domingo'
    WHEN 2 THEN 'lunes'
    WHEN 3 THEN 'martes'
    WHEN 4 THEN 'miercoles'
    WHEN 5 THEN 'jueves'
    WHEN 6 THEN 'viernes'
    WHEN 7 THEN 'sabado'
  END AS nombre_dia,
  CASE WHEN dayofweek(f.fecha) IN (1,7) THEN TRUE ELSE FALSE END AS es_fin_semana
FROM (
  SELECT explode(sequence(p.fecha_inicio, p.fecha_fin, interval 1 day)) AS fecha
  FROM vw_parametros_dim_fecha p
) f;

INSERT INTO dw.gold.dim_fecha (
  id_fecha,
  fecha,
  anio,
  mes,
  nombre_mes,
  trimestre,
  dia,
  nombre_dia,
  es_fin_semana
)
SELECT
  s.id_fecha,
  s.fecha,
  s.anio,
  s.mes,
  s.nombre_mes,
  s.trimestre,
  s.dia,
  s.nombre_dia,
  s.es_fin_semana
FROM vw_src_dim_fecha s
WHERE NOT EXISTS (
  SELECT 1
  FROM dw.gold.dim_fecha t
  WHERE t.id_fecha = s.id_fecha
);
