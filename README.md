# Inventory Stock and Reorder Analysis

## Project overview

This project demonstrates how an inventory analyst can combine stock snapshots, recent demand, supplier lead times, safety stock, and open purchase orders to identify SKU-location pairs that may need replenishment. The included data is deterministic and synthetic: the companies, products, contacts, and activity are fictional. It is suitable for demonstrating an analysis workflow, not for operational purchasing decisions.

## Dataset

| File | Contents |
|---|---|
| `data/products.csv` | 60 products with category, supplier, unit cost, and price |
| `data/suppliers.csv` | 8 suppliers with lead time and minimum order quantity |
| `data/locations.csv` | 3 inventory locations |
| `data/inventory_snapshot.csv` | Stock position per SKU and location on 2026-11-03 |
| `data/daily_demand.csv` | 32,400 SKU-location daily rows from 2026-05-08 to 2026-11-03 |
| `data/purchase_orders.csv` | Purchase orders, including open orders reflected in incoming stock |
| `data/reorder_recommendations.csv` | Example flagged recommendations for the snapshot date (not the full SKU-location grid) |

Recorded demand is 90,487 units over the dataset period. The sample has 180 inventory positions (60 products × 3 locations). The supplied recommendation file has 73 example rows; `analysis.py` calculates every inventory position, including those that do not need an order. Price and cost are numeric, but the currency is intentionally unspecified.

## Reorder method

For each SKU and location, using the 14 calendar days ending on the snapshot date:

1. Average daily demand = units sold in the 14-day window ÷ 14.
2. Reorder point = ceiling(average daily demand × supplier lead time) + safety stock.
3. Available quantity = on-hand − reserved + incoming.
4. If available quantity is below the reorder point, suggested order quantity = the larger of the shortfall and the supplier minimum order quantity. Otherwise, suggested quantity is zero.

The incoming stock field in the snapshot agrees with the outstanding balance on open purchase orders. Demand uncertainty, seasonality, expiry, pack sizes, supplier capacity, and purchase budgets are not modeled. All incoming units are treated as available for planning.

## Run the analysis

From this project folder, with Python 3 installed:

```sh
python analysis.py
```

The analysis writes `outputs/reorder_analysis.csv`, `outputs/category_summary.csv`, and `outputs/analysis_report.md`. These provide per-position calculations, category rollups, and a concise results report. A Python version is included for portability; on Windows, the PowerShell version runs without installing Python:

```powershell
.\analysis.ps1
```

## Load into PostgreSQL

Create an empty database, install the PostgreSQL command-line client, and run this command from the project folder (the loader's `\\copy` paths are relative to the current folder):

```sh
psql -h YOUR_HOST -U YOUR_USER -d YOUR_DATABASE -f load_postgres.sql
```

The account needs permission to create tables. `schema.sql` defines the relational model, foreign keys, validation checks, primary keys, and query indexes. `sql/analysis_queries.sql` includes SQL for recomputing recommendations and examining category risk, inventory value, supplier exposure, and demand trends.

## Suggested college presentation

Present the business question, dataset and synthetic-data caveat, the four-step reorder method, the highest-risk SKU-location pairs from `outputs/reorder_analysis.csv`, category differences from `outputs/category_summary.csv`, and the assumptions/limitations. Explain that a low-stock flag is a planning signal: a real purchasing decision also needs verified demand, arrival timing, and business constraints. A ready-to-use findings narrative is in `outputs/analysis_report.md`.

## Interactive website

Open `website/index.html` in a browser to present the project as an interactive dashboard. It includes summary metrics, demand and category charts, the highest-priority stock gaps, and a searchable/filterable table for all 180 SKU-location positions. It works as a local file without a web server. See `website/README.md` for details.
