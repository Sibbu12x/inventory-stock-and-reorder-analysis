# Rebuild the inventory analysis outputs using built-in PowerShell only.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir = Join-Path $root 'data'
$outDir = Join-Path $root 'outputs'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$products = Import-Csv (Join-Path $dataDir 'products.csv')
$suppliers = Import-Csv (Join-Path $dataDir 'suppliers.csv')
$locations = Import-Csv (Join-Path $dataDir 'locations.csv')
$stock = Import-Csv (Join-Path $dataDir 'inventory_snapshot.csv')
$demand = Import-Csv (Join-Path $dataDir 'daily_demand.csv')
$purchaseOrders = Import-Csv (Join-Path $dataDir 'purchase_orders.csv')
$sampleRecommendations = Import-Csv (Join-Path $dataDir 'reorder_recommendations.csv')

$productBySku = @{}
foreach ($product in $products) { $productBySku[$product.sku] = $product }
$supplierById = @{}
foreach ($supplier in $suppliers) { $supplierById[$supplier.supplier_id] = $supplier }
$locationById = @{}
foreach ($location in $locations) { $locationById[$location.location_id] = $location }

$snapshotDates = @($stock | ForEach-Object { [datetime]::ParseExact($_.snapshot_date, 'yyyy-MM-dd', $null) } | Sort-Object -Unique)
if ($snapshotDates.Count -ne 1) { throw 'Expected a single inventory snapshot date.' }
$asOf = $snapshotDates[0]
$windowStart = $asOf.AddDays(-13)
$demand14 = @{}
$allDemandDates = @{}
$totalDemandUnits = 0
foreach ($row in $demand) {
    $d = [datetime]::ParseExact($row.sale_date, 'yyyy-MM-dd', $null)
    $key = "$($row.sku)|$($row.location_id)"
    $totalDemandUnits += [int]$row.units_sold
    if (-not $allDemandDates.ContainsKey($key)) { $allDemandDates[$key] = [System.Collections.Generic.HashSet[string]]::new() }
    [void]$allDemandDates[$key].Add($row.sale_date)
    if ($d -ge $windowStart -and $d -le $asOf) { $demand14[$key] = [int]$demand14[$key] + [int]$row.units_sold }
}
$poIncoming = @{}
foreach ($po in $purchaseOrders) {
    if ($po.status -eq 'open') {
        $key = "$($po.sku)|$($po.location_id)"
        $poIncoming[$key] = [int]$poIncoming[$key] + ([int]$po.ordered_qty - [int]$po.received_qty)
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$incomingMismatches = 0
foreach ($row in $stock) {
    $key = "$($row.sku)|$($row.location_id)"
    $product = $productBySku[$row.sku]
    $supplier = $supplierById[$product.supplier_id]
    $location = $locationById[$row.location_id]
    $units14 = [int]$demand14[$key]
    $avg = [decimal]$units14 / 14
    $lead = [int]$supplier.lead_time_days
    $safety = [int]$row.safety_stock_qty
    $available = [int]$row.on_hand_qty - [int]$row.reserved_qty + [int]$row.incoming_qty
    $reorderPoint = [int][math]::Ceiling($avg * $lead) + $safety
    $shortfall = [math]::Max(0, $reorderPoint - $available)
    $orderQty = if ($shortfall -gt 0) { [math]::Max($shortfall, [int]$supplier.minimum_order_qty) } else { 0 }
    $orderCost = [decimal]$orderQty * [decimal]$product.unit_cost
    if ([int]$row.incoming_qty -ne [int]$poIncoming[$key]) { $incomingMismatches++ }
    $results.Add([pscustomobject]@{
        as_of_date = $asOf.ToString('yyyy-MM-dd'); sku = $row.sku; product_name = $product.product_name
        category = $product.category; location_id = $row.location_id; location_name = $location.location_name
        supplier_id = $product.supplier_id; avg_daily_demand_14d = [math]::Round($avg, 3)
        lead_time_days = $lead; safety_stock_qty = $safety; on_hand_qty = [int]$row.on_hand_qty
        reserved_qty = [int]$row.reserved_qty; incoming_qty = [int]$row.incoming_qty
        available_qty = $available; reorder_point_qty = $reorderPoint; shortfall_qty = $shortfall
        minimum_order_qty = [int]$supplier.minimum_order_qty; recommended_order_qty = $orderQty
        estimated_order_cost = [math]::Round($orderCost, 2)
        reason = if ($shortfall -gt 0) { 'below_reorder_point' } else { 'stock_sufficient' }
    })
}

$results | Export-Csv (Join-Path $outDir 'reorder_analysis.csv') -NoTypeInformation -Encoding utf8
$categorySummary = foreach ($group in ($results | Group-Object category | Sort-Object Name)) {
    $ordered = @($group.Group | Where-Object { $_.recommended_order_qty -gt 0 })
    [pscustomobject]@{
        category = $group.Name
        unique_skus = @($group.Group.sku | Sort-Object -Unique).Count
        locations_below_rop = $ordered.Count
        recommended_units = ($ordered | Measure-Object -Property recommended_order_qty -Sum).Sum
        estimated_order_cost = [math]::Round((($ordered | Measure-Object -Property estimated_order_cost -Sum).Sum), 2)
    }
}
$categorySummary | Export-Csv (Join-Path $outDir 'category_summary.csv') -NoTypeInformation -Encoding utf8

$toOrder = @($results | Where-Object { $_.recommended_order_qty -gt 0 })
$orderUnits = ($toOrder | Measure-Object -Property recommended_order_qty -Sum).Sum
$orderCostTotal = [math]::Round((($toOrder | Measure-Object -Property estimated_order_cost -Sum).Sum), 2)
$stockValue = [decimal]0
foreach ($row in $stock) { $stockValue += [decimal]$row.on_hand_qty * [decimal]$productBySku[$row.sku].unit_cost }
$top = @($toOrder | Sort-Object @{Expression='shortfall_qty';Descending=$true}, sku, location_id | Select-Object -First 10)
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Inventory stock and reorder analysis')
$lines.Add('')
$lines.Add("**As of:** $($asOf.ToString('yyyy-MM-dd'))  |  **Data:** deterministic synthetic sample; all entities are fictional.")
$lines.Add('')
$lines.Add('## Executive summary')
$lines.Add('')
$activeProducts = @($products | Where-Object { $_.active -eq 'true' }).Count
$lines.Add("The sample contains **$($products.Count) products** ($activeProducts active), **$($locations.Count) locations**, **$($stock.Count) SKU-location stock positions**, and **$($demand.Count) daily demand records** covering 2026-05-08 to 2026-11-03.")
$lines.Add("Recorded demand totals **$('{0:N0}' -f $totalDemandUnits) units**. On-hand inventory is valued at **$('{0:N2}' -f $stockValue)** at unit cost (currency is unspecified). **$($toOrder.Count) of $($results.Count) positions** fall below the calculated reorder point; suggested orders total **$('{0:N0}' -f $orderUnits) units**, with estimated cost **$('{0:N2}' -f $orderCostTotal)**.")
$lines.Add('')
$lines.Add('## Method')
$lines.Add('')
$lines.Add("For each SKU and location, average daily demand is units sold in the 14 calendar days ending $($asOf.ToString('yyyy-MM-dd')) divided by 14. Reorder point = ceiling(average daily demand × supplier lead time) + safety stock. Available stock = on-hand − reserved + incoming. If available is below the reorder point, order the greater of the shortfall and supplier minimum order quantity; otherwise order zero.")
$lines.Add('')
$lines.Add('Incoming quantity is taken from the inventory snapshot and cross-checked against open purchase-order balances. Cost estimates use product master unit cost. Currency is unspecified. The calculation assumes incoming units arrive in time; it does not model seasonality, demand uncertainty, expiry, pack rounding, supplier capacity, or budget constraints.')
$lines.Add('')
$lines.Add('## Largest shortfalls')
$lines.Add('')
$lines.Add('| SKU | Product | Location | Available | Reorder point | Shortfall | Suggested order | Estimated cost |')
$lines.Add('|---|---|---|---:|---:|---:|---:|---:|')
foreach ($row in $top) { $lines.Add("| $($row.sku) | $($row.product_name) | $($row.location_name) | $($row.available_qty) | $($row.reorder_point_qty) | $($row.shortfall_qty) | $($row.recommended_order_qty) | $($row.estimated_order_cost) |") }
$lines.Add('')
$lines.Add('## Category summary')
$lines.Add('')
$lines.Add('| Category | Unique SKUs | Positions below reorder point | Recommended units | Estimated cost |')
$lines.Add('|---|---:|---:|---:|---:|')
foreach ($row in $categorySummary) { $lines.Add("| $($row.category) | $($row.unique_skus) | $($row.locations_below_rop) | $($row.recommended_units) | $($row.estimated_order_cost) |") }
$lines.Add('')
$lines.Add('## Data quality and limitations')
$lines.Add('')
$lines.Add("The open purchase-order balance check found $incomingMismatches incoming-quantity mismatches across $($stock.Count) stock rows. The supplied recommendation file has $($sampleRecommendations.Count) example rows; the analysis above recomputes all $($results.Count) SKU-location positions.")
$lines.Add('')
$lines.Add('This dataset is synthetic and intentionally small. It demonstrates a reproducible method, not operational purchasing advice. Recalculate with verified demand, supplier rules, and current stock before placing real orders.')
$lines.Add('')
$lines.Add('## Rebuild outputs')
$lines.Add('')
$lines.Add('Run `python analysis.py` or `./analysis.ps1` from the project folder. The outputs are `outputs/reorder_analysis.csv`, `outputs/category_summary.csv`, and this report.')
Set-Content -Path (Join-Path $outDir 'analysis_report.md') -Value $lines -Encoding utf8
Write-Output "Created analysis outputs: $($results.Count) stock positions; $($toOrder.Count) below reorder point; incoming mismatches: $incomingMismatches."
