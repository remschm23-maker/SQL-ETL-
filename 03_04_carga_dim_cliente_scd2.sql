-- ============================================================
-- Script 03.04 - Carga de dimension cliente (SCD2)
-- DW - Databricks SQL / Delta
-- Patron incremental con watermark + tmp congelado + MERGE
-- ============================================================

USE CATALOG dw;
USE SCHEMA gold;

CREATE OR REPLACE TABLE dw.gold.tmp_dim_cliente AS
WITH watermark AS (
  SELECT COALESCE(MAX(Update_Date), TIMESTAMP '1900-01-01') AS last_ts
  FROM dw.gold.dim_cliente
)
SELECT
  c.cust_id,
  c.cust_name,
  ct.cust_type_name,
  r.regn_name,
  st.state_name,
  GREATEST(
    COALESCE(c.update_date,  TIMESTAMP '1900-01-01'),
    COALESCE(ct.update_date, TIMESTAMP '1900-01-01'),
    COALESCE(r.update_date,  TIMESTAMP '1900-01-01'),
    COALESCE(st.update_date, TIMESTAMP '1900-01-01')
  ) AS row_update_ts,
  w.last_ts AS watermark_last_ts
FROM bronze_fuentes.verduleria_oltp.customer c
JOIN bronze_fuentes.verduleria_oltp.customer_type ct
  ON ct.cust_type_id = c.cust_type_id
JOIN bronze_fuentes.verduleria_oltp.region r
  ON r.regn_id = c.cust_regn_id
JOIN bronze_fuentes.verduleria_oltp.state st
  ON st.state_id = r.state_id
CROSS JOIN watermark w
WHERE GREATEST(
        COALESCE(c.update_date,  TIMESTAMP '1900-01-01'),
        COALESCE(ct.update_date, TIMESTAMP '1900-01-01'),
        COALESCE(r.update_date,  TIMESTAMP '1900-01-01'),
        COALESCE(st.update_date, TIMESTAMP '1900-01-01')
      ) > w.last_ts;

MERGE INTO dw.gold.dim_cliente AS d
USING dw.gold.tmp_dim_cliente AS s
ON d.cust_id = s.cust_id
AND d.es_actual = TRUE
WHEN MATCHED
  AND NOT (
    d.cust_name       <=> s.cust_name
    AND d.cust_type_name <=> s.cust_type_name
    AND d.regn_name   <=> s.regn_name
    AND d.state_name  <=> s.state_name
  )
THEN UPDATE SET
  d.fecha_fin   = date_sub(CAST(s.row_update_ts AS DATE), 1),
  d.es_actual   = FALSE,
  d.Update_Date = s.row_update_ts;

INSERT INTO dw.gold.dim_cliente (
  cust_id,
  cust_name,
  cust_type_name,
  regn_name,
  state_name,
  Update_Date,
  fecha_inicio,
  fecha_fin,
  es_actual
)
SELECT
  s.cust_id,
  s.cust_name,
  s.cust_type_name,
  s.regn_name,
  s.state_name,
  s.row_update_ts AS Update_Date,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM dw.gold.dim_cliente h
      WHERE h.cust_id = s.cust_id
    ) THEN CAST(s.row_update_ts AS DATE)
    ELSE DATE '2025-01-01'
  END AS fecha_inicio,
  DATE '9999-12-31' AS fecha_fin,
  TRUE AS es_actual
FROM dw.gold.tmp_dim_cliente s
LEFT JOIN dw.gold.dim_cliente d
  ON d.cust_id = s.cust_id
 AND d.es_actual = TRUE
WHERE d.cust_id IS NULL;
