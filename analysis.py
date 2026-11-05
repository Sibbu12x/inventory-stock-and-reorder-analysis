"""Reproducible inventory and reorder analysis for the included sample data."""
from __future__ import annotations

import csv
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal, ROUND_CEILING
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
OUT = ROOT / "outputs"


def read_csv(name: str) -> list[dict[str, str]]:
    with (DATA / name).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(name: str, rows: list[dict], fields: list[str]) -> None:
    OUT.mkdir(exist_ok=True)
    with (OUT / name).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def ceil_decimal(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_CEILING))


def main() -> None:
    products = {r["sku"]: r for r in read_csv("products.csv")}
    suppliers = {r["supplier_id"]: r for r in read_csv("suppliers.csv")}
    locations = {r["location_id"]: r for r in read_csv("locations.csv")}
    stock = read_csv("inventory_snapshot.csv")
    demand = read_csv("daily_demand.csv")
    pos = read_csv("purchase_orders.csv")
    sample_recs = read_csv("reorder_recommendations.csv")
    snapshot_dates = {date.fromisoformat(r["snapshot_date"]) for r in stock}
    if len(snapshot_dates) != 1:
        raise ValueError("Expected one common inventory snapshot date")
    as_of = next(iter(snapshot_dates))
    start = as_of - timedelta(days=13)
    demand_14: dict[tuple[str, str], int] = defaultdict(int)
    dates_by_key: dict[tuple[str, str], set[date]] = defaultdict(set)
    for r in demand:
        d = date.fromisoformat(r["sale_date"])
        key = (r["sku"], r["location_id"])
        units = int(r["units_sold"])
        dates_by_key[key].add(d)
        if start <= d <= as_of:
            demand_14[key] += units
    incoming_po: dict[tuple[str, str], int] = defaultdict(int)
    for po in pos:
        if po["status"].lower() in {"open", "in_transit", "in transit"}:
            incoming_po[(po["sku"], po["location_id"])] += int(po["ordered_qty"]) - int(po["received_qty"])

    recs = []
    stock_keys = set()
    issues = []
    for r in stock:
        sku, loc = r["sku"], r["location_id"]
        key = (sku, loc)
        stock_keys.add(key)
        if sku not in products or loc not in locations:
            issues.append(f"Unknown SKU/location in inventory: {sku}/{loc}")
            continue
        product = products[sku]
        supplier = suppliers[product["supplier_id"]]
        on_hand, reserved, incoming = int(r["on_hand_qty"]), int(r["reserved_qty"]), int(r["incoming_qty"])
        safety = int(r["safety_stock_qty"])
        if min(on_hand, reserved, incoming, safety) < 0 or reserved > on_hand:
            issues.append(f"Invalid stock quantities for {sku}/{loc}")
        po_incoming = incoming_po[key]
        if po_incoming != incoming:
            issues.append(f"Incoming quantity differs from open PO balance for {sku}/{loc}: snapshot={incoming}, POs={po_incoming}")
        avg = Decimal(demand_14[key]) / Decimal(14)
        lead = int(supplier["lead_time_days"])
        available = on_hand - reserved + incoming
        rop = ceil_decimal(avg * lead) + safety
        shortfall = max(0, rop - available)
        order_qty = max(shortfall, int(supplier["minimum_order_qty"])) if shortfall else 0
        reason = "below_reorder_point" if shortfall else "stock_sufficient"
        recs.append({
            "as_of_date": as_of.isoformat(), "sku": sku, "product_name": product["product_name"],
            "category": product["category"], "location_id": loc, "location_name": locations[loc]["location_name"],
            "supplier_id": product["supplier_id"], "avg_daily_demand_14d": f"{avg:.3f}",
            "lead_time_days": lead, "safety_stock_qty": safety, "on_hand_qty": on_hand,
            "reserved_qty": reserved, "incoming_qty": incoming, "available_qty": available,
            "reorder_point_qty": rop, "shortfall_qty": shortfall,
            "minimum_order_qty": int(supplier["minimum_order_qty"]), "recommended_order_qty": order_qty,
            "estimated_order_cost": f"{Decimal(order_qty) * Decimal(product['unit_cost']):.2f}", "reason": reason,
        })

    # Validate referential integrity, file keys, and the supplied sample policy output.
    duplicates = {"products": len(products) != len(read_csv("products.csv")),
                  "inventory": len(stock_keys) != len(stock),
                  "demand": len({(r['sale_date'], r['sku'], r['location_id']) for r in demand}) != len(demand)}
    if any(duplicates.values()):
        issues.append("Duplicate primary key detected in one or more source files")
    by_key = {(r["sku"], r["location_id"]): r for r in recs}
    sample_mismatches = []
    for s in sample_recs:
        actual = by_key.get((s["sku"], s["location_id"]))
        if not actual or int(s["available_qty"]) != actual["available_qty"] or int(s["recommended_order_qty"]) != actual["recommended_order_qty"] or int(s["reorder_point_qty"]) != actual["reorder_point_qty"]:
            sample_mismatches.append(s["sku"] + "/" + s["location_id"])
    write_csv("reorder_analysis.csv", recs, list(recs[0]))

    reorder = [r for r in recs if r["recommended_order_qty"]]
    categories: dict[str, dict] = defaultdict(lambda: {"skus": set(), "units": 0, "cost": Decimal(0), "risk": 0})
    for r in recs:
        c = categories[r["category"]]
        c["skus"].add(r["sku"])
        c["units"] += r["recommended_order_qty"]
        c["cost"] += Decimal(r["estimated_order_cost"])
        c["risk"] += r["recommended_order_qty"] > 0
    category_rows = [{"category": cat, "unique_skus": len(v["skus"]), "locations_below_rop": v["risk"],
                     "recommended_units": v["units"], "estimated_order_cost": f"{v['cost']:.2f}"}
                    for cat, v in sorted(categories.items())]
    write_csv("category_summary.csv", category_rows, list(category_rows[0]))
    total_value = sum((Decimal(r["on_hand_qty"]) * Decimal(products[r["sku"]]["unit_cost"]) for r in stock), Decimal(0))
    demand_units = sum(int(r["units_sold"]) for r in demand)
    total_order_cost = sum((Decimal(r["estimated_order_cost"]) for r in reorder), Decimal(0))
    worst = sorted(reorder, key=lambda r: (-r["shortfall_qty"], r["sku"], r["location_id"]))[:10]
    active = sum(r["active"].lower() == "true" for r in products.values())
    report = [
        "# Inventory stock and reorder analysis", "",
        f"**As of:** {as_of.isoformat()}  |  **Data:** deterministic synthetic sample; all entities are fictional.", "",
        "## Executive summary", "",
        f"The sample contains **{len(products)} products** ({active} active), **{len(locations)} locations**, **{len(stock)} SKU-location stock positions**, and **{len(demand):,} daily demand records** covering {min(date.fromisoformat(r['sale_date']) for r in demand)} to {max(date.fromisoformat(r['sale_date']) for r in demand)}.",
        f"Recorded demand totals **{demand_units:,} units**. On-hand inventory is valued at **{total_value:,.2f}** at unit cost (currency is unspecified). **{len(reorder)} of {len(recs)} positions** fall below the calculated reorder point; the recommended orders total **{sum(r['recommended_order_qty'] for r in reorder):,} units**, with estimated cost **{total_order_cost:,.2f}**.",
        "", "## Method", "",
        f"For each SKU and location, average daily demand is units sold in the 14 calendar days ending {as_of.isoformat()} divided by 14. Reorder point = ceiling(average daily demand × supplier lead time) + safety stock. Available stock = on-hand − reserved + incoming. If available is below the reorder point, order the greater of the shortfall and supplier minimum order quantity; otherwise order zero.",
        "", "Incoming quantity is taken from the inventory snapshot and cross-checked against open purchase-order balances. Unit cost estimates use product master cost. The calculation assumes all listed incoming units are usable and arrive in time; no seasonality, demand uncertainty, expiry, pack rounding, budget, or supplier capacity constraints are modeled.",
        "", "## Priorities", "", "Largest calculated shortfalls (units):", "",
        "| SKU | Product | Location | Available | Reorder point | Shortfall | Suggested order | Est. cost |", "|---|---|---|---:|---:|---:|---:|---:|",
    ]
    for r in worst:
        report.append(f"| {r['sku']} | {r['product_name']} | {r['location_name']} | {r['available_qty']} | {r['reorder_point_qty']} | {r['shortfall_qty']} | {r['recommended_order_qty']} | {r['estimated_order_cost']} |")
    report += ["", "## Category summary", "", "| Category | Unique SKUs | Positions below reorder point | Recommended units | Estimated cost |", "|---|---:|---:|---:|---:|"]
    report += [f"| {r['category']} | {r['unique_skus']} | {r['locations_below_rop']} | {r['recommended_units']} | {r['estimated_order_cost']} |" for r in category_rows]
    report += ["", "## Data quality and limitations", ""]
    report.append(f"Demand date coverage across SKU-location pairs: {len(dates_by_key)} pairs; {min((len(x) for x in dates_by_key.values()), default=0)}–{max((len(x) for x in dates_by_key.values()), default=0)} observed dates. This is a coverage check, not a guarantee of complete sales capture.")
    report.append(f"Supplied example recommendation rows: {len(sample_recs)}; discrepancies against recomputation: {len(sample_mismatches)}.")
    if sample_mismatches:
        report.append("Discrepancy keys: " + ", ".join(sample_mismatches[:20]))
    if issues:
        report.append("Issues found: " + "; ".join(issues))
    else:
        report.append("Source quantity checks and key checks passed; snapshot incoming balances agree with open purchase orders.")
    report += ["", "This dataset is synthetic and intentionally small. It demonstrates a reproducible method; it is not operational purchasing advice. Costs have no currency, and results should be recalculated using verified real demand, supplier rules, and current stock before real orders.",
               "", "## Deliverables", "", "- `outputs/reorder_analysis.csv`: one transparent calculation per SKU/location.", "- `outputs/category_summary.csv`: category-level rollup.", "- `sql/analysis_queries.sql`: PostgreSQL versions of core questions.", "- `analysis.py`: reproducible analysis script.", "", "Run `python analysis.py` from the project folder to rebuild the outputs."]
    OUT.mkdir(exist_ok=True)
    (OUT / "analysis_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(f"Wrote {len(recs)} reorder rows, {len(category_rows)} category rows; {len(reorder)} positions need orders; {len(sample_mismatches)} supplied recommendation discrepancies; {len(issues)} data issues.")
    for issue in issues:
        print("ISSUE:", issue)


if __name__ == "__main__":
    main()
