-- ============================================================
-- Script 02.02 - Carga de dimension producto (SCD1)
-- DW - Databricks SQL / Delta
-- Patron incremental con watermark + tmp congelado + MERGE
-- ============================================================

USE CATALOG dw;
USE SCHEMA gold;

CREATE OR REPLACE TABLE dw.gold.tmp_dim_producto AS
WITH watermark AS (
  SELECT COALESCE(MAX(Update_Date), TIMESTAMP '1900-01-01') AS last_ts
  FROM dw.gold.dim_producto
)
SELECT
  p.prod_id,
  p.prod_name,
  pt.prod_type_name,
  GREATEST(
    COALESCE(p.update_date,  TIMESTAMP '1900-01-01'),
    COALESCE(pt.update_date, TIMESTAMP '1900-01-01')
  ) AS row_update_ts,
  w.last_ts AS watermark_last_ts
FROM bronze_fuentes.verduleria_oltp.product p
JOIN bronze_fuentes.verduleria_oltp.product_type pt
  ON pt.prod_type_id = p.prod_type_id
CROSS JOIN watermark w
WHERE GREATEST(
        COALESCE(p.update_date,  TIMESTAMP '1900-01-01'),
        COALESCE(pt.update_date, TIMESTAMP '1900-01-01')
      ) > w.last_ts;

MERGE INTO dw.gold.dim_producto AS d
USING dw.gold.tmp_dim_producto AS s
ON d.prod_id = s.prod_id
WHEN MATCHED
  AND NOT (
    d.prod_name       <=> s.prod_name
    AND d.prod_type_name <=> s.prod_type_name
    AND d.Update_Date <=> s.row_update_ts
  )
THEN UPDATE SET
  d.prod_name       = s.prod_name,
  d.prod_type_name  = s.prod_type_name,
  d.Update_Date     = s.row_update_ts
WHEN NOT MATCHED THEN INSERT (
  prod_id,
  prod_name,
  prod_type_name,
  Update_Date
)
VALUES (
  s.prod_id,
  s.prod_name,
  s.prod_type_name,
  s.row_update_ts
);
