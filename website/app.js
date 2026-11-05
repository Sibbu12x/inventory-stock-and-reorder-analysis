(() => {
  const data = window.INVENTORY_DATA;
  if (!data) return;
  const num = value => Number(value) || 0;
  const fmt = value => new Intl.NumberFormat('en-US').format(value);
  const money = value => new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(value);
  const rows = data.reorders.map(row => ({
    ...row,
    avg_daily_demand_14d: num(row.avg_daily_demand_14d),
    available_qty: num(row.available_qty),
    reorder_point_qty: num(row.reorder_point_qty),
    shortfall_qty: num(row.shortfall_qty),
    recommended_order_qty: num(row.recommended_order_qty),
    estimated_order_cost: num(row.estimated_order_cost)
  }));
  const flagged = rows.filter(row => row.recommended_order_qty > 0);
  const orderUnits = flagged.reduce((sum, row) => sum + row.recommended_order_qty, 0);
  const orderCost = flagged.reduce((sum, row) => sum + row.estimated_order_cost, 0);

  document.getElementById('kpi-positions').textContent = fmt(rows.length);
  document.getElementById('kpi-risk').textContent = fmt(flagged.length);
  document.getElementById('kpi-units').textContent = fmt(orderUnits);
  document.getElementById('kpi-cost').textContent = money(orderCost);
  document.getElementById('risk-rate').textContent = `${(flagged.length / rows.length * 100).toFixed(1)}%`;
  document.getElementById('nav-count').textContent = flagged.length;
  document.getElementById('data-products').textContent = fmt(data.products.length);
  document.getElementById('data-locations').textContent = fmt(new Set(data.stock.map(row => row.location_id)).size);
  document.getElementById('data-records').textContent = fmt(data.demandRecords);
  document.getElementById('data-demand').textContent = `${fmt(data.demandUnits)} units`;

  const topRows = [...flagged].sort((a, b) => b.shortfall_qty - a.shortfall_qty).slice(0, 5);
  document.getElementById('priority-body').innerHTML = topRows.map(row => `
    <tr>
      <td><div class="product-cell"><span class="product-mark">${escapeHtml(row.category.slice(0, 1))}</span><div><div class="product-name">${escapeHtml(row.product_name)}</div><div class="product-sku">${escapeHtml(row.sku)}</div></div></div></td>
      <td class="location-cell">${escapeHtml(row.location_name)}</td><td>${fmt(row.available_qty)} units</td>
      <td>${fmt(row.reorder_point_qty)} units</td><td class="qty-gap">−${fmt(row.shortfall_qty)}</td><td class="qty-order">${fmt(row.recommended_order_qty)} units</td>
    </tr>`).join('');

  renderDemandChart(data.monthly);
  renderCategoryChart(data.categories);
  setupTable(rows);
  setupNavigation();

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  }

  function renderDemandChart(months) {
    const el = document.getElementById('demand-chart');
    const width = 600, height = 190;
    const left = 42, right = 9, top = 9, bottom = 29;
    const max = Math.ceil(Math.max(...months.map(row => num(row.units))) / 5000) * 5000;
    const plotW = width - left - right, plotH = height - top - bottom;
    const ticks = 4;
    const grid = Array.from({ length: ticks + 1 }, (_, index) => {
      const value = max * index / ticks;
      const y = top + plotH - plotH * index / ticks;
      return `<line x1="${left}" y1="${y}" x2="${width - right}" y2="${y}" stroke="#edf0f2" stroke-width="1"/><text x="${left - 8}" y="${y + 3}" text-anchor="end" fill="#a2abb5" font-size="9">${Math.round(value / 1000)}k</text>`;
    }).join('');
    const gap = 12, barW = (plotW - gap * (months.length - 1)) / months.length;
    const bars = months.map((row, index) => {
      const value = num(row.units), barH = plotH * value / max;
      const x = left + index * (barW + gap), y = top + plotH - barH;
      const label = new Date(`${row.month}-01T00:00:00`).toLocaleDateString('en-US', { month: 'short' });
      return `<g><rect x="${x}" y="${y}" width="${barW}" height="${barH}" rx="3" fill="${index === months.length - 1 ? '#9dbb58' : '#78964a'}"><title>${label} 2026: ${fmt(value)} units</title></rect><text x="${x + barW / 2}" y="${height - 7}" text-anchor="middle" fill="#8f9aa6" font-size="9">${label}</text></g>`;
    }).join('');
    el.innerHTML = `<svg viewBox="0 0 ${width} ${height}" aria-hidden="true">${grid}${bars}</svg>`;
  }

  function renderCategoryChart(categories) {
    const el = document.getElementById('category-chart');
    const sorted = [...categories].sort((a, b) => num(b.recommended_units) - num(a.recommended_units));
    const max = Math.max(...sorted.map(row => num(row.recommended_units)));
    el.innerHTML = sorted.map(row => `<div class="category-row"><div class="category-name">${escapeHtml(row.category)}</div><div class="category-track"><div class="category-fill" style="width:${Math.max(2, num(row.recommended_units) / max * 100)}%"></div></div><div class="category-units">${fmt(num(row.recommended_units))}</div></div>`).join('');
  }

  function setupTable(allRows) {
    const categoryFilter = document.getElementById('category-filter');
    [...new Set(allRows.map(row => row.category))].sort().forEach(category => {
      const option = document.createElement('option'); option.value = category; option.textContent = category; categoryFilter.append(option);
    });
    let sortKey = 'recommended_order_qty', descending = true;
    const render = () => {
      const query = document.getElementById('search').value.trim().toLowerCase();
      const category = categoryFilter.value;
      const status = document.getElementById('status-filter').value;
      const filtered = allRows.filter(row => {
        const matchesSearch = !query || `${row.sku} ${row.product_name} ${row.location_name}`.toLowerCase().includes(query);
        const matchesStatus = status === 'all' || (status === 'reorder' ? row.recommended_order_qty > 0 : row.recommended_order_qty === 0);
        return matchesSearch && (!category || row.category === category) && matchesStatus;
      }).sort((a, b) => {
        const av = a[sortKey], bv = b[sortKey];
        const comparison = typeof av === 'number' ? av - bv : String(av).localeCompare(String(bv));
        return descending ? -comparison : comparison;
      });
      document.getElementById('result-count').textContent = `Showing ${filtered.length} of ${allRows.length} positions`;
      document.getElementById('reorder-body').innerHTML = filtered.length ? filtered.map(row => `
        <tr><td><b>${escapeHtml(row.sku)}</b></td><td><div class="product-name">${escapeHtml(row.product_name)}</div></td>
        <td>${escapeHtml(row.category)}</td><td>${escapeHtml(row.location_name)}</td><td>${row.avg_daily_demand_14d.toFixed(3)}</td>
        <td>${fmt(row.available_qty)}</td><td>${fmt(row.reorder_point_qty)}</td>
        <td>${row.recommended_order_qty > 0 ? `<span class="status need"><i></i>${fmt(row.recommended_order_qty)} order</span>` : '<span class="status ok"><i></i>Stock OK</span>'}</td></tr>`).join('') : '<tr><td colspan="8" class="empty-row">No inventory positions match these filters.</td></tr>';
    };
    document.getElementById('search').addEventListener('input', render);
    categoryFilter.addEventListener('change', render);
    document.getElementById('status-filter').addEventListener('change', render);
    document.querySelectorAll('.data-table th[data-sort]').forEach(th => th.addEventListener('click', () => {
      if (sortKey === th.dataset.sort) descending = !descending; else { sortKey = th.dataset.sort; descending = true; }
      render();
    }));
    render();
  }

  function setupNavigation() {
    const links = [...document.querySelectorAll('.nav-link')];
    links.forEach(link => link.addEventListener('click', () => {
      links.forEach(item => item.classList.remove('active'));
      link.classList.add('active');
    }));
  }
})();
