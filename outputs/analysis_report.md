# Inventory stock and reorder analysis

**As of:** 2026-11-03  |  **Data:** deterministic synthetic sample; all entities are fictional.

## Executive summary

The sample contains **60 products** (60 active), **3 locations**, **180 SKU-location stock positions**, and **32400 daily demand records** covering 2026-05-08 to 2026-11-03.
Recorded demand totals **90,487 units**. On-hand inventory is valued at **4,90,567.22** at unit cost (currency is unspecified). **73 of 180 positions** fall below the calculated reorder point; suggested orders total **2,475 units**, with estimated cost **1,35,812.43**.

## Method

For each SKU and location, average daily demand is units sold in the 14 calendar days ending 2026-11-03 divided by 14. Reorder point = ceiling(average daily demand × supplier lead time) + safety stock. Available stock = on-hand − reserved + incoming. If available is below the reorder point, order the greater of the shortfall and supplier minimum order quantity; otherwise order zero.

Incoming quantity is taken from the inventory snapshot and cross-checked against open purchase-order balances. Cost estimates use product master unit cost. Currency is unspecified. The calculation assumes incoming units arrive in time; it does not model seasonality, demand uncertainty, expiry, pack rounding, supplier capacity, or budget constraints.

## Largest shortfalls

| SKU | Product | Location | Available | Reorder point | Shortfall | Suggested order | Estimated cost |
|---|---|---|---:|---:|---:|---:|---:|
| SKU0040 | Outdoor Item 040 | Central Warehouse | 1 | 154 | 153 | 153 | 8439.48 |
| SKU0008 | Electronics Item 008 | South Store | 22 | 159 | 137 | 137 | 8794.03 |
| SKU0028 | Home Item 028 | South Store | 8 | 127 | 119 | 119 | 1511.3 |
| SKU0024 | Office Supplies Item 024 | Central Warehouse | 37 | 141 | 104 | 104 | 9139.52 |
| SKU0044 | Outdoor Item 044 | South Store | 7 | 97 | 90 | 90 | 2889.0 |
| SKU0006 | Electronics Item 006 | South Store | 0 | 89 | 89 | 89 | 5376.49 |
| SKU0020 | Office Supplies Item 020 | South Store | 58 | 145 | 87 | 87 | 6498.03 |
| SKU0048 | Outdoor Item 048 | Central Warehouse | 7 | 85 | 78 | 78 | 4440.54 |
| SKU0026 | Home Item 026 | East Store | 23 | 96 | 73 | 73 | 4341.31 |
| SKU0060 | Apparel Item 060 | East Store | 21 | 93 | 72 | 72 | 5841.36 |

## Category summary

| Category | Unique SKUs | Positions below reorder point | Recommended units | Estimated cost |
|---|---:|---:|---:|---:|
| Apparel | 12 | 13 | 308 | 15868.54 |
| Electronics | 12 | 17 | 507 | 27959.41 |
| Home | 12 | 12 | 507 | 25598.12 |
| Office Supplies | 12 | 14 | 529 | 35393.73 |
| Outdoor | 12 | 17 | 624 | 30992.63 |

## Data quality and limitations

The open purchase-order balance check found 0 incoming-quantity mismatches across 180 stock rows. The supplied recommendation file has 73 example rows; the analysis above recomputes all 180 SKU-location positions.

This dataset is synthetic and intentionally small. It demonstrates a reproducible method, not operational purchasing advice. Recalculate with verified demand, supplier rules, and current stock before placing real orders.

## Rebuild outputs

Run `python analysis.py` or `./analysis.ps1` from the project folder. The outputs are `outputs/reorder_analysis.csv`, `outputs/category_summary.csv`, and this report.
