-- Run after load_postgres.sql. These queries use only the supplied sample data.

-- 1. Recompute stock position and reorder recommendations for latest snapshot.
WITH latest AS (
  SELECT max(snapshot_date) AS as_of_date FROM inventory_snapshot
), demand_14 AS (
  SELECT d.sku, d.location_id, sum(d.units_sold)::numeric / 14 AS avg_daily_demand
  FROM daily_demand d CROSS JOIN latest l
  WHERE d.sale_date BETWEEN l.as_of_date - 13 AND l.as_of_date
  GROUP BY d.sku, d.location_id
)
SELECT i.snapshot_date AS as_of_date, i.sku, p.product_name, i.location_id,
       coalesce(d.avg_daily_demand, 0)::numeric(12,3) AS avg_daily_demand_14d,
       s.lead_time_days, i.safety_stock_qty,
       i.on_hand_qty - i.reserved_qty + i.incoming_qty AS available_qty,
       ceil(coalesce(d.avg_daily_demand, 0) * s.lead_time_days)::integer
          + i.safety_stock_qty AS reorder_point_qty,
       CASE WHEN i.on_hand_qty - i.reserved_qty + i.incoming_qty
                    < ceil(coalesce(d.avg_daily_demand, 0) * s.lead_time_days)::integer + i.safety_stock_qty
         THEN greatest(
           ceil(coalesce(d.avg_daily_demand, 0) * s.lead_time_days)::integer + i.safety_stock_qty
             - (i.on_hand_qty - i.reserved_qty + i.incoming_qty),
           s.minimum_order_qty)
         ELSE 0 END AS recommended_order_qty
FROM inventory_snapshot i
CROSS JOIN latest l
JOIN products p ON p.sku = i.sku
JOIN suppliers s ON s.supplier_id = p.supplier_id
LEFT JOIN demand_14 d ON (d.sku, d.location_id) = (i.sku, i.location_id)
WHERE i.snapshot_date = l.as_of_date
ORDER BY recommended_order_qty DESC, i.sku, i.location_id;

-- 2. Category summary using the supplied recommendation table.
SELECT p.category,
       count(*) FILTER (WHERE r.recommended_order_qty > 0) AS positions_to_reorder,
       sum(r.recommended_order_qty) AS recommended_units,
       round(sum(r.recommended_order_qty * p.unit_cost), 2) AS estimated_cost
FROM reorder_recommendations r
JOIN products p USING (sku)
GROUP BY p.category
ORDER BY estimated_cost DESC;

-- 3. Inventory value by location at unit cost.
SELECT l.location_name,
       sum(i.on_hand_qty) AS on_hand_units,
       round(sum(i.on_hand_qty * p.unit_cost), 2) AS on_hand_value
FROM inventory_snapshot i
JOIN products p USING (sku)
JOIN locations l USING (location_id)
WHERE i.snapshot_date = (SELECT max(snapshot_date) FROM inventory_snapshot)
GROUP BY l.location_name
ORDER BY on_hand_value DESC;

-- 4. Supplier exposure: open PO balances and product count.
SELECT s.supplier_name, count(DISTINCT p.sku) AS supplied_skus,
       coalesce(sum(po.ordered_qty - po.received_qty)
         FILTER (WHERE po.status = 'open'), 0) AS open_po_units
FROM suppliers s
LEFT JOIN products p USING (supplier_id)
LEFT JOIN purchase_orders po ON po.supplier_id = s.supplier_id
GROUP BY s.supplier_id, s.supplier_name
ORDER BY open_po_units DESC;

-- 5. Demand trend by month (units, revenue as recorded in demand file).
SELECT date_trunc('month', sale_date)::date AS month,
       sum(units_sold) AS units_sold,
       round(sum(units_sold * unit_price), 2) AS recorded_revenue
FROM daily_demand
GROUP BY 1
ORDER BY 1;
