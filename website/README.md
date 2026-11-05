# Stockwise dashboard

This is a self-contained website for presenting the inventory analysis. It uses the bundled `data.js`, so it can be opened directly without a server or internet connection. The optional Google Fonts connection only changes the typeface; the page has local fallback fonts.

## Open the website

Double-click `index.html` or open it in a browser. Use the left navigation to move between the overview, reorder plan, demand trends, and method sections. In the full reorder plan, search by SKU/product, filter by category or status, and sort by a column heading. Use **Print report** to print or save a PDF.

## Refresh the embedded data

After rebuilding the project outputs with `..\analysis.ps1`, run `build_data.ps1` from this folder or the project root to refresh `data.js`.

All content is based on the fictional synthetic project dataset. Costs have no assigned currency.
