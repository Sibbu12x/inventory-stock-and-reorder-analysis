$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$reorders = Import-Csv (Join-Path $root 'outputs/reorder_analysis.csv')
$categories = Import-Csv (Join-Path $root 'outputs/category_summary.csv')
$products = Import-Csv (Join-Path $root 'data/products.csv')
$demand = Import-Csv (Join-Path $root 'data/daily_demand.csv')
$stock = Import-Csv (Join-Path $root 'data/inventory_snapshot.csv')
$suppliers = Import-Csv (Join-Path $root 'data/suppliers.csv')
$monthly = foreach ($group in ($demand | Group-Object { $_.sale_date.Substring(0,7) } | Sort-Object Name)) {
  [pscustomobject]@{
    month = $group.Name
    units = [int](($group.Group | Measure-Object -Property units_sold -Sum).Sum)
    revenue = [math]::Round((($group.Group | ForEach-Object { [double]$_.units_sold * [double]$_.unit_price } | Measure-Object -Sum).Sum),2)
  }
}
$dataset = [ordered]@{
  asOf = '2026-11-03'
  products = @($products)
  suppliers = @($suppliers)
  stock = @($stock)
  reorders = @($reorders)
  categories = @($categories)
  monthly = @($monthly)
  demandRecords = $demand.Count
  demandUnits = [int](($demand | Measure-Object -Property units_sold -Sum).Sum)
}
$json = $dataset | ConvertTo-Json -Depth 8 -Compress
Set-Content -Path (Join-Path $PSScriptRoot 'data.js') -Value "window.INVENTORY_DATA = $json;" -Encoding utf8
Write-Output "Built website data: $($reorders.Count) stock positions, $($monthly.Count) demand months."
