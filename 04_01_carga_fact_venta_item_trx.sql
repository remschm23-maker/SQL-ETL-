-- ============================================================
-- Script 03.01T - Carga de fact_venta_item_trx
-- DW - Databricks SQL / Delta
-- Enfoque transaccional: sale_id en el grano
-- Patron incremental con watermark + tmp congelado + MERGE
-- ============================================================

USE CATALOG dw;
USE SCHEMA gold;

CREATE OR REPLACE TABLE dw.gold.tmp_fact_venta_item_trx AS
WITH watermark AS (
  SELECT COALESCE(MAX(Update_Date), TIMESTAMP '1900-01-01') AS last_ts
  FROM dw.gold.fact_venta_item_trx
),
changed_sales AS (
  SELECT DISTINCT s.sale_id
  FROM bronze_fuentes.verduleria_oltp.sale s
  CROSS JOIN watermark w
  WHERE s.update_date > w.last_ts

  UNION

  SELECT DISTINCT si.sale_id
  FROM bronze_fuentes.verduleria_oltp.sale_item si
  CROSS JOIN watermark w
  WHERE si.update_date > w.last_ts
),
base_rows AS (
  SELECT
    s.sale_id,
    CAST(date_format(s.sale_date, 'yyyyMMdd') AS INT) AS id_fecha_venta,
    CAST(date_format(s.posted_date, 'yyyyMMdd') AS INT) AS id_fecha_posteo,
    dc.id_fila_cliente,
    du.id_fila_ubicacion,
    dp.id_fila_producto,
    si.qty,
    si.unit_price,
    GREATEST(
      COALESCE(s.update_date,  TIMESTAMP '1900-01-01'),
      COALESCE(si.update_date, TIMESTAMP '1900-01-01')
    ) AS row_update_ts
  FROM changed_sales cs
  JOIN bronze_fuentes.verduleria_oltp.sale s
    ON s.sale_id = cs.sale_id
  JOIN bronze_fuentes.verduleria_oltp.sale_item si
    ON si.sale_id = s.sale_id
  JOIN dw.gold.dim_producto dp
    ON dp.prod_id = si.prod_id
  JOIN dw.gold.dim_cliente dc
    ON dc.cust_id = s.cust_id
   AND s.sale_date BETWEEN dc.fecha_inicio AND dc.fecha_fin
  JOIN dw.gold.dim_ubicacion du
    ON du.loc_id = s.loc_id
   AND s.sale_date BETWEEN du.fecha_inicio AND du.fecha_fin
)
SELECT
  b.sale_id,
  b.id_fecha_venta,
  b.id_fecha_posteo,
  b.id_fila_cliente,
  b.id_fila_ubicacion,
  b.id_fila_producto,
  CAST(SUM(b.qty) AS INT) AS qty,
  CAST(
    CASE WHEN SUM(b.qty) = 0 THEN 0
         ELSE SUM(CAST(b.qty AS DECIMAL(18,4)) * b.unit_price)
              / SUM(CAST(b.qty AS DECIMAL(18,4)))
    END AS DECIMAL(12,2)
  ) AS unit_price,
  CAST(SUM(CAST(b.qty AS DECIMAL(18,4)) * b.unit_price) AS DECIMAL(18,2)) AS importe_bruto,
  MAX(b.row_update_ts) AS row_update_ts,
  w.last_ts AS watermark_last_ts
FROM base_rows b
CROSS JOIN watermark w
GROUP BY
  b.sale_id,
  b.id_fecha_venta,
  b.id_fecha_posteo,
  b.id_fila_cliente,
  b.id_fila_ubicacion,
  b.id_fila_producto,
  w.last_ts;

MERGE INTO dw.gold.fact_venta_item_trx AS d
USING dw.gold.tmp_fact_venta_item_trx AS s
ON d.sale_id          = s.sale_id
AND d.id_fila_producto = s.id_fila_producto
WHEN MATCHED
  AND NOT (
    d.id_fecha_venta    <=> s.id_fecha_venta
    AND d.id_fecha_posteo  <=> s.id_fecha_posteo
    AND d.id_fila_cliente  <=> s.id_fila_cliente
    AND d.id_fila_ubicacion <=> s.id_fila_ubicacion
    AND d.qty             <=> s.qty
    AND d.unit_price      <=> s.unit_price
    AND d.importe_bruto   <=> s.importe_bruto
    AND d.Update_Date     <=> s.row_update_ts
  )
THEN UPDATE SET
  d.id_fecha_venta    = s.id_fecha_venta,
  d.id_fecha_posteo   = s.id_fecha_posteo,
  d.id_fila_cliente   = s.id_fila_cliente,
  d.id_fila_ubicacion = s.id_fila_ubicacion,
  d.qty               = s.qty,
  d.unit_price        = s.unit_price,
  d.importe_bruto     = s.importe_bruto,
  d.Update_Date       = s.row_update_ts
WHEN NOT MATCHED THEN INSERT (
  sale_id,
  id_fecha_venta,
  id_fecha_posteo,
  id_fila_cliente,
  id_fila_ubicacion,
  id_fila_producto,
  qty,
  unit_price,
  importe_bruto,
  Update_Date
)
VALUES (
  s.sale_id,
  s.id_fecha_venta,
  s.id_fecha_posteo,
  s.id_fila_cliente,
  s.id_fila_ubicacion,
  s.id_fila_producto,
  s.qty,
  s.unit_price,
  s.importe_bruto,
  s.row_update_ts
);
