const COLORS = {
  executable: '#e74c3c', framework: '#e67e22', assetCatalog: '#f1c40f',
  storyboard: '#2ecc71', xib: '#27ae60', strings: '#1abc9c',
  font: '#3498db', plist: '#9b59b6', codeSignature: '#7f8c8d',
  image: '#e91e63', audio: '#00bcd4', video: '#ff5722',
  mlModel: '#8bc34a', metalLibrary: '#ff9800', appExtension: '#673ab7',
  localization: '#009688', header: '#607d8b', moduleMap: '#795548',
  other: '#555577'
};

function formatSize(bytes) {
  if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(2) + ' GB';
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return bytes + ' B';
}

function getColor(node) {
  if (node.category) return COLORS[node.category] || COLORS.other;
  if (node.children && node.children.length > 0) {
    return getColor(node.children[0]);
  }
  return COLORS.other;
}

function assignColors(node) {
  if (node.children) {
    node.children.forEach(assignColors);
    const cats = {};
    node.children.forEach(c => {
      const col = getColor(c);
      cats[col] = (cats[col] || 0) + c.size;
    });
    let maxSize = 0, dominant = COLORS.other;
    for (const [col, sz] of Object.entries(cats)) {
      if (sz > maxSize) { maxSize = sz; dominant = col; }
    }
    if (!node.category) node._color = dominant;
    if (!node.category) {
      const catSizes = {};
      node.children.forEach(c => {
        const cat = c.category || c._category || '';
        if (cat) catSizes[cat] = (catSizes[cat] || 0) + c.size;
      });
      let maxSz = 0, dom = '';
      for (const [c, sz] of Object.entries(catSizes)) {
        if (sz > maxSz) { maxSz = sz; dom = c; }
      }
      node._category = dom;
    }
  }
  if (!node._color) node._color = getColor(node);
}

// Squarified treemap layout
function squarify(items, x, y, w, h) {
  const rects = [];
  if (!items.length || w <= 0 || h <= 0) return rects;

  const total = items.reduce((s, d) => s + d.size, 0);
  if (total === 0) return rects;

  const sorted = [...items].sort((a, b) => b.size - a.size);
  layoutStrip(sorted, 0, x, y, w, h, total, rects);
  return rects;
}

function layoutStrip(items, idx, x, y, w, h, total, rects) {
  if (idx >= items.length) return;
  if (w <= 0 || h <= 0) return;

  const remaining = items.slice(idx).reduce((s, d) => s + d.size, 0);
  if (remaining <= 0) return;

  const vertical = h > w;
  const mainDim = vertical ? h : w;
  const crossDim = vertical ? w : h;

  let strip = [];
  let stripSum = 0;
  let bestRatio = Infinity;

  for (let i = idx; i < items.length; i++) {
    const testStrip = [...strip, items[i]];
    const testSum = stripSum + items[i].size;
    const stripFrac = testSum / remaining;
    const stripCross = crossDim * stripFrac;

    if (stripCross <= 0) break;

    let worstRatio = 0;
    for (const item of testStrip) {
      const itemFrac = item.size / testSum;
      const itemMain = mainDim * itemFrac;
      const ratio = Math.max(itemMain / stripCross, stripCross / itemMain);
      worstRatio = Math.max(worstRatio, ratio);
    }

    if (worstRatio > bestRatio && strip.length > 0) break;

    strip = testStrip;
    stripSum = testSum;
    bestRatio = worstRatio;
  }

  const stripFrac = stripSum / remaining;
  const stripCross = crossDim * stripFrac;
  let pos = 0;

  for (const item of strip) {
    const itemFrac = item.size / stripSum;
    const itemMain = mainDim * itemFrac;

    let rx, ry, rw, rh;
    if (vertical) {
      rx = x; ry = y + pos; rw = stripCross; rh = itemMain;
    } else {
      rx = x + pos; ry = y; rw = itemMain; rh = stripCross;
    }

    rects.push({ node: item, x: rx, y: ry, w: rw, h: rh });
    pos += itemMain;
  }

  const nextIdx = idx + strip.length;
  if (vertical) {
    layoutStrip(items, nextIdx, x + stripCross, y, w - stripCross, h, total, rects);
  } else {
    layoutStrip(items, nextIdx, x, y + stripCross, w, h - stripCross, total, rects);
  }
}

// State
let currentNode = DATA;
let pathStack = [];
const container = document.getElementById('treemap');
const breadcrumb = document.getElementById('breadcrumb');
const tooltip = document.getElementById('tooltip');
const searchResults = document.getElementById('search-results');
let viewMode = 'treemap';
let hoveredEl = null;
const MAX_DEPTH = 3;

assignColors(DATA);

function render(node) {
  container.innerHTML = '';
  if (viewMode === 'pie' || viewMode === 'donut') {
    renderPieOrDonut(node, viewMode === 'donut');
    return;
  }
  const rect = container.getBoundingClientRect();
  const children = node.children || [];
  if (!children.length) return;

  let rects = squarify(children, 0, 0, rect.width, rect.height);
  rects = applyOverflow(rects, rect.width, rect.height);

  for (const r of rects) {
    if (r.w < 1 || r.h < 1) continue;
    renderNode(r.node, container, r.x, r.y, r.w, r.h, 0, null);
  }
}

function applyOverflow(rects, w, h) {
  const visible = [], overflow = [];
  for (const r of rects) {
    if (r.w >= 16 && r.h >= 16) visible.push(r);
    else overflow.push(r);
  }
  if (overflow.length === 0) return rects;
  const overflowSize = overflow.reduce((s, r) => s + r.node.size, 0);
  const syntheticNode = {
    name: 'Other (' + overflow.length + ' items)',
    size: overflowSize,
    children: overflow.map(r => r.node),
    _isOverflow: true,
    _color: COLORS.other,
    _category: ''
  };
  return squarify([...visible.map(r => r.node), syntheticNode], 0, 0, w, h);
}

function renderNode(node, parentEl, x, y, w, h, depth, parentNode) {
  if (w < 1 || h < 1) return;

  const el = document.createElement('div');
  el.className = 'node';
  el.style.left = x + 'px';
  el.style.top = y + 'px';
  el.style.width = w + 'px';
  el.style.height = h + 'px';
  const baseColor = node._color || getColor(node);
  const darken = depth * 15;
  el.style.background = darken > 0 ? darkenColor(baseColor, darken) : baseColor;
  el.dataset.name = node.name;
  el.dataset.category = node.category || node._category || '';

  if (w > 40 && h > 18) {
    const label = document.createElement('div');
    label.className = 'node-label' + (depth > 0 ? ' depth-' + Math.min(depth, 2) : '');
    label.textContent = node.name;
    el.appendChild(label);
  }
  if (w > 60 && h > 32) {
    const sizeLabel = document.createElement('div');
    sizeLabel.className = 'node-size' + (depth > 0 ? ' depth-' + Math.min(depth, 2) : '');
    sizeLabel.textContent = formatSize(node.size);
    el.appendChild(sizeLabel);
  }

  el.addEventListener('click', (e) => {
    e.stopPropagation();
    if (node._isOverflow && parentNode) {
      // Overflow nodes: re-render the parent so all items are visible
      pathStack.push(currentNode);
      currentNode = parentNode;
      render(currentNode);
      renderBreadcrumb();
    } else if (node.children && node.children.length > 0) {
      pathStack.push(currentNode);
      currentNode = node;
      render(currentNode);
      renderBreadcrumb();
    } else if (parentNode) {
      pathStack.push(currentNode);
      currentNode = parentNode;
      render(currentNode);
      renderBreadcrumb();
    }
  });

  el.addEventListener('mouseenter', (e) => {
    e.stopPropagation();
    if (hoveredEl && hoveredEl !== el) hoveredEl.classList.remove('hovered');
    hoveredEl = el;
    el.classList.add('hovered');
    tooltip.style.display = 'block';
    let html = '<div class="tt-name">' + escapeHTML(node.name) + '</div>';
    html += '<div class="tt-size">' + formatSize(node.size) + '</div>';
    const cat = node.category || node._category;
    if (cat) html += '<div class="tt-cat">' + cat + '</div>';
    if (node.children) html += '<div class="tt-cat">' + node.children.length + ' items</div>';
    tooltip.innerHTML = html;
  });

  el.addEventListener('mousemove', (e) => {
    e.stopPropagation();
    const tx = e.clientX + 12, ty = e.clientY + 12;
    const tw = tooltip.offsetWidth, th = tooltip.offsetHeight;
    tooltip.style.left = (tx + tw > window.innerWidth ? e.clientX - tw - 12 : tx) + 'px';
    tooltip.style.top = (ty + th > window.innerHeight ? e.clientY - th - 12 : ty) + 'px';
  });

  el.addEventListener('mouseleave', (e) => {
    e.stopPropagation();
    el.classList.remove('hovered');
    tooltip.style.display = 'none';
  });

  parentEl.appendChild(el);

  if (node.children && node.children.length > 0 && depth < MAX_DEPTH) {
    const headerH = (h > 44 && w > 40) ? 32 : (h > 30 && w > 40) ? 18 : 0;
    const pad = 2;
    const innerW = w - 2 * pad;
    const innerH = h - headerH - 2 * pad;
    if (innerW > 8 && innerH > 8) {
      let childRects = squarify(node.children, 0, 0, innerW, innerH);
      if (!node._isOverflow) childRects = applyOverflow(childRects, innerW, innerH);
      for (const cr of childRects) {
        if (cr.w < 1 || cr.h < 1) continue;
        renderNode(cr.node, el, cr.x + pad, cr.y + headerH + pad, cr.w, cr.h, depth + 1, node);
      }
    }
  }
}

function darkenColor(hex, amount) {
  let r = parseInt(hex.slice(1, 3), 16);
  let g = parseInt(hex.slice(3, 5), 16);
  let b = parseInt(hex.slice(5, 7), 16);
  r = Math.max(0, r - amount);
  g = Math.max(0, g - amount);
  b = Math.max(0, b - amount);
  return '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('');
}

function renderBreadcrumb() {
  breadcrumb.innerHTML = '';
  const all = [...pathStack, currentNode].filter(n => !n._isOverflow);
  all.forEach((node, i) => {
    if (i > 0) {
      const sep = document.createElement('span');
      sep.className = 'sep';
      sep.textContent = ' / ';
      breadcrumb.appendChild(sep);
    }
    const span = document.createElement('span');
    span.textContent = node.name;
    if (i < all.length - 1) {
      span.addEventListener('click', () => {
        currentNode = all[i];
        pathStack = all.slice(0, i);
        render(currentNode);
        renderBreadcrumb();
      });
    }
    breadcrumb.appendChild(span);
  });
}

function escapeHTML(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// Deep search (Fix 5)
function deepSearch(node, query, path) {
  let results = [];
  if (node.name.toLowerCase().includes(query)) {
    results.push({ node, path: [...path, node] });
  }
  if (node.children) {
    for (const child of node.children) {
      results = results.concat(deepSearch(child, query, [...path, node]));
    }
  }
  return results;
}

function navigateTo(pathArray) {
  pathStack = pathArray.slice(0, -1);
  currentNode = pathArray[pathArray.length - 1];
  render(currentNode);
  renderBreadcrumb();
}

// Search
const searchInput = document.getElementById('search');
let searchTimer = null;
const dimmedCategories = new Set();

searchInput.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    const query = searchInput.value.trim().toLowerCase();
    if (!query) {
      searchResults.style.display = 'none';
      searchResults.innerHTML = '';
      container.querySelectorAll('.node').forEach(n => { n.classList.remove('search-match', 'search-dim'); });
      return;
    }

    const results = deepSearch(DATA, query, []).sort((a, b) => b.node.size - a.node.size).slice(0, 20);

    searchResults.innerHTML = '';
    if (results.length > 0) {
      searchResults.style.display = 'block';
      for (const result of results) {
        const row = document.createElement('div');
        row.className = 'search-result';
        const pathStr = result.path.map(n => n.name).join(' / ');
        row.innerHTML = '<span class="sr-name">' + escapeHTML(result.node.name) + '</span>' +
          '<span class="sr-path">' + escapeHTML(pathStr) + '</span>' +
          '<span class="sr-size">' + formatSize(result.node.size) + '</span>';
        row.addEventListener('click', () => {
          if (result.node.children && result.node.children.length > 0) {
            navigateTo(result.path);
          } else if (result.path.length > 1) {
            navigateTo(result.path.slice(0, -1));
          }
          searchResults.style.display = 'none';
          searchInput.value = '';
          container.querySelectorAll('.node').forEach(n => { n.classList.remove('search-match', 'search-dim'); });
        });
        searchResults.appendChild(row);
      }
    } else {
      searchResults.style.display = 'none';
    }

    container.querySelectorAll('.node').forEach(n => {
      const name = (n.dataset.name || '').toLowerCase();
      if (name.includes(query)) {
        n.classList.add('search-match');
        n.classList.remove('search-dim');
      } else {
        n.classList.add('search-dim');
        n.classList.remove('search-match');
      }
    });
  }, 150);
});

searchInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    const firstResult = searchResults.querySelector('.search-result');
    if (firstResult) firstResult.click();
  }
  if (e.key === 'Escape') {
    searchResults.style.display = 'none';
    searchInput.value = '';
    container.querySelectorAll('.node').forEach(n => { n.classList.remove('search-match', 'search-dim'); });
  }
});

document.addEventListener('click', (e) => {
  if (!e.target.closest('#search-container')) {
    searchResults.style.display = 'none';
  }
});

// Legend
const legendContainer = document.getElementById('legend');

function gatherCategories(node) {
  const cats = {};
  (function walk(n) {
    if (n.category) {
      cats[n.category] = (cats[n.category] || 0) + n.size;
    }
    if (n.children) n.children.forEach(walk);
  })(node);
  return cats;
}

function buildLegend() {
  legendContainer.innerHTML = '';
  const cats = gatherCategories(currentNode);
  const sorted = Object.entries(cats).sort((a, b) => b[1] - a[1]);
  for (const [cat, size] of sorted) {
    const chip = document.createElement('div');
    chip.className = 'legend-chip' + (dimmedCategories.has(cat) ? ' dimmed' : '');
    const swatch = document.createElement('span');
    swatch.className = 'swatch';
    swatch.style.background = COLORS[cat] || COLORS.other;
    chip.appendChild(swatch);
    chip.appendChild(document.createTextNode(cat + ' (' + formatSize(size) + ')'));
    chip.addEventListener('click', () => {
      if (dimmedCategories.has(cat)) {
        dimmedCategories.delete(cat);
        chip.classList.remove('dimmed');
      } else {
        dimmedCategories.add(cat);
        chip.classList.add('dimmed');
      }
      applyFilter();
    });
    legendContainer.appendChild(chip);
  }
}

function applyFilter() {
  if (dimmedCategories.size === 0) {
    container.querySelectorAll('.node').forEach(n => n.classList.remove('category-dim'));
    container.querySelectorAll('path[data-category]').forEach(p => { p.style.opacity = '1'; });
    return;
  }
  container.querySelectorAll('.node').forEach(n => {
    const cat = n.dataset.category;
    if (cat && dimmedCategories.has(cat)) {
      n.classList.add('category-dim');
    } else {
      n.classList.remove('category-dim');
    }
  });
  container.querySelectorAll('path[data-category]').forEach(p => {
    const cat = p.dataset.category;
    p.style.opacity = (cat && dimmedCategories.has(cat)) ? '0.15' : '1';
  });
}

// Patch render to rebuild legend after each render
const _origRender = render;
render = function(node) {
  _origRender(node);
  buildLegend();
  applyFilter();
};

// View mode switcher (Fix 6)
document.querySelectorAll('.mode-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.mode-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    viewMode = btn.dataset.mode;
    render(currentNode);
  });
});

// Pie/Donut rendering
function renderPieOrDonut(node, isDonut) {
  const rect = container.getBoundingClientRect();
  const cx = rect.width / 2, cy = rect.height / 2;
  const r = Math.min(cx, cy) - 40;
  const innerR = isDonut ? r * 0.45 : 0;

  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('width', rect.width);
  svg.setAttribute('height', rect.height);
  svg.style.width = '100%';
  svg.style.height = '100%';

  const children = (node.children || []).filter(c => c.size > 0);
  if (!children.length) {
    if (node.size > 0) {
      const sweep = 2 * Math.PI - 0.0001;
      const path = document.createElementNS(ns, 'path');
      path.setAttribute('d', arcPath(cx, cy, r, innerR, -Math.PI / 2, -Math.PI / 2 + sweep));
      path.setAttribute('fill', node._color || getColor(node));
      svg.appendChild(path);
      const nameText = document.createElementNS(ns, 'text');
      nameText.setAttribute('x', cx);
      nameText.setAttribute('y', cy - 8);
      nameText.setAttribute('class', 'pie-center-label');
      nameText.textContent = node.name.length > 20 ? node.name.slice(0, 19) + '\u2026' : node.name;
      svg.appendChild(nameText);
      const sizeText = document.createElementNS(ns, 'text');
      sizeText.setAttribute('x', cx);
      sizeText.setAttribute('y', cy + 12);
      sizeText.setAttribute('class', 'pie-center-size');
      sizeText.textContent = formatSize(node.size);
      svg.appendChild(sizeText);
      container.appendChild(svg);
    }
    return;
  }
  const total = children.reduce((s, c) => s + c.size, 0);

  const big = [], tiny = [];
  for (const c of children) {
    if ((c.size / total) * 2 * Math.PI < 0.05) tiny.push(c);
    else big.push(c);
  }
  let displayChildren = big;
  if (tiny.length > 1) {
    const tinySize = tiny.reduce((s, c) => s + c.size, 0);
    displayChildren.push({
      name: 'Other (' + tiny.length + ' items)',
      size: tinySize,
      children: tiny,
      _isOverflow: true,
      _color: COLORS.other,
      _category: ''
    });
  } else {
    displayChildren = displayChildren.concat(tiny);
  }

  let angle = -Math.PI / 2;

  for (const child of displayChildren) {
    const sweep = Math.min((child.size / total) * 2 * Math.PI, 2 * Math.PI - 0.0001);
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', arcPath(cx, cy, r, innerR, angle, angle + sweep));
    path.setAttribute('fill', child._color || getColor(child));
    path.style.cursor = 'pointer';
    path.style.transition = 'opacity 0.15s';
    path.dataset.name = child.name;
    path.dataset.category = child.category || child._category || '';

    const captured = child;
    path.addEventListener('click', () => {
      if (captured.children && captured.children.length > 0) {
        pathStack.push(currentNode);
        currentNode = captured;
        render(currentNode);
        renderBreadcrumb();
      }
    });

    path.addEventListener('mouseenter', () => {
      path.style.opacity = '0.8';
      tooltip.style.display = 'block';
      let html = '<div class="tt-name">' + escapeHTML(captured.name) + '</div>';
      html += '<div class="tt-size">' + formatSize(captured.size) + ' (' + ((captured.size / total) * 100).toFixed(1) + '%)</div>';
      const cat = captured.category || captured._category;
      if (cat) html += '<div class="tt-cat">' + cat + '</div>';
      if (captured.children) html += '<div class="tt-cat">' + captured.children.length + ' items</div>';
      tooltip.innerHTML = html;
    });

    path.addEventListener('mousemove', (e) => {
      const tx = e.clientX + 12, ty = e.clientY + 12;
      const tw = tooltip.offsetWidth, th = tooltip.offsetHeight;
      tooltip.style.left = (tx + tw > window.innerWidth ? e.clientX - tw - 12 : tx) + 'px';
      tooltip.style.top = (ty + th > window.innerHeight ? e.clientY - th - 12 : ty) + 'px';
    });

    path.addEventListener('mouseleave', () => {
      path.style.opacity = '1';
      tooltip.style.display = 'none';
    });

    svg.appendChild(path);

    if (sweep > 0.15) {
      const midAngle = angle + sweep / 2;
      const labelR = isDonut ? (r + innerR) / 2 : r * 0.65;
      const lx = cx + labelR * Math.cos(midAngle);
      const ly = cy + labelR * Math.sin(midAngle);
      const text = document.createElementNS(ns, 'text');
      text.setAttribute('x', lx);
      text.setAttribute('y', ly);
      text.setAttribute('class', 'pie-label');
      text.textContent = child.name.length > 15 ? child.name.slice(0, 14) + '\u2026' : child.name;
      svg.appendChild(text);
    }

    angle += sweep;
  }

  if (isDonut) {
    const nameText = document.createElementNS(ns, 'text');
    nameText.setAttribute('x', cx);
    nameText.setAttribute('y', cy - 8);
    nameText.setAttribute('class', 'pie-center-label');
    nameText.textContent = node.name.length > 20 ? node.name.slice(0, 19) + '\u2026' : node.name;
    svg.appendChild(nameText);

    const sizeText = document.createElementNS(ns, 'text');
    sizeText.setAttribute('x', cx);
    sizeText.setAttribute('y', cy + 12);
    sizeText.setAttribute('class', 'pie-center-size');
    sizeText.textContent = formatSize(total);
    svg.appendChild(sizeText);
  }

  container.appendChild(svg);
}

function arcPath(cx, cy, r, innerR, startAngle, endAngle) {
  const x1 = cx + r * Math.cos(startAngle);
  const y1 = cy + r * Math.sin(startAngle);
  const x2 = cx + r * Math.cos(endAngle);
  const y2 = cy + r * Math.sin(endAngle);
  const largeArc = endAngle - startAngle > Math.PI ? 1 : 0;

  if (innerR > 0) {
    const ix1 = cx + innerR * Math.cos(endAngle);
    const iy1 = cy + innerR * Math.sin(endAngle);
    const ix2 = cx + innerR * Math.cos(startAngle);
    const iy2 = cy + innerR * Math.sin(startAngle);
    return 'M ' + x1 + ' ' + y1 + ' A ' + r + ' ' + r + ' 0 ' + largeArc + ' 1 ' + x2 + ' ' + y2 + ' L ' + ix1 + ' ' + iy1 + ' A ' + innerR + ' ' + innerR + ' 0 ' + largeArc + ' 0 ' + ix2 + ' ' + iy2 + ' Z';
  }
  return 'M ' + cx + ' ' + cy + ' L ' + x1 + ' ' + y1 + ' A ' + r + ' ' + r + ' 0 ' + largeArc + ' 1 ' + x2 + ' ' + y2 + ' Z';
}

function renderInsights() {
  const el = document.getElementById('insights');
  if (!INSIGHTS || !INSIGHTS.length) return;

  const active = INSIGHTS.filter(i => i.severity !== 'passing');
  const totalSavings = active.reduce((s, i) => s + i.savingsBytes, 0);
  const totalSize = DATA.size;
  const pct = totalSize > 0 ? ((totalSavings / totalSize) * 100).toFixed(1) : '0.0';

  const header = document.createElement('div');
  header.id = 'insights-header';
  header.innerHTML =
    '<h2>Insights</h2>' +
    '<span class="insights-summary">' +
      active.length + ' suggestion' + (active.length !== 1 ? 's' : '') +
      ' \u00B7 ' + formatSize(totalSavings) + ' potential savings (' + pct + '%)' +
    '</span>';
  el.appendChild(header);

  const severityOrder = { critical: 0, warning: 1, info: 2, passing: 3 };
  const sorted = [...INSIGHTS].sort((a, b) => {
    const sa = severityOrder[a.severity] ?? 4;
    const sb = severityOrder[b.severity] ?? 4;
    if (sa !== sb) return sa - sb;
    return b.savingsBytes - a.savingsBytes;
  });
  for (const insight of sorted) {
    const card = document.createElement('div');
    card.className = 'insight-card ' + insight.severity;

    const savingsPct = totalSize > 0
      ? ((insight.savingsBytes / totalSize) * 100).toFixed(1) : '0.0';

    let html =
      '<div class="insight-title">' +
        '<span class="severity-dot ' + insight.severity + '"></span>' +
        escapeHTML(insight.title) +
      '</div>' +
      '<div class="insight-desc">' + escapeHTML(insight.description) + '</div>';

    if (insight.severity !== 'passing' && insight.savingsBytes > 0) {
      html += '<div class="insight-savings">Potential savings: <strong>' +
        formatSize(insight.savingsBytes) + '</strong> (' + savingsPct + '%)</div>';
    }

    if (insight.affectedFiles && insight.affectedFiles.length > 0) {
      const fid = 'files-' + insight.id;
      html += '<div class="insight-files-toggle" data-target="' + fid + '">' +
        '\u25B6 ' + insight.affectedFiles.length + ' affected file' +
        (insight.affectedFiles.length !== 1 ? 's' : '') + '</div>';
      html += '<div class="insight-files-list" id="' + fid + '">';
      for (const f of insight.affectedFiles) {
        html += '<div class="insight-file">' +
          '<span class="file-path">' + escapeHTML(f.path) + '</span>' +
          '<span class="file-size">' + formatSize(f.size) + '</span>' +
          (f.detail ? '<span class="file-detail">' + escapeHTML(f.detail) + '</span>' : '') +
          '</div>';
      }
      html += '</div>';
    }

    card.innerHTML = html;
    el.appendChild(card);
  }

  el.addEventListener('click', (e) => {
    const toggle = e.target.closest('.insight-files-toggle');
    if (!toggle) return;
    const targetId = toggle.dataset.target;
    const list = document.getElementById(targetId);
    if (list) {
      list.classList.toggle('open');
      toggle.textContent = (list.classList.contains('open') ? '\u25BC ' : '\u25B6 ') +
        toggle.textContent.slice(2);
    }
  });
}

renderInsights();

// Dependency Graph
function renderDepGraph() {
  if (!DEP_GRAPH) return;
  const el = document.getElementById('dependency-graph');
  if (!el) return;

  const header = document.createElement('div');
  header.id = 'dep-graph-header';
  const embedded = DEP_GRAPH.nodes.filter(n => n.nodeType === 'embeddedFramework').length;
  const spmCount = DEP_GRAPH.nodes.filter(n => n.nodeType === 'spmPackage').length;
  const system = DEP_GRAPH.nodes.filter(n => n.isSystemLibrary).length;
  const parts = [];
  if (embedded > 0) parts.push(embedded + ' embedded framework' + (embedded !== 1 ? 's' : ''));
  if (spmCount > 0) parts.push(spmCount + ' SPM package' + (spmCount !== 1 ? 's' : ''));
  if (system > 0) parts.push(system + ' system librar' + (system !== 1 ? 'ies' : 'y'));
  parts.push('depth ' + DEP_GRAPH.maxDepth);
  header.innerHTML =
    '<h2>Dependency Graph</h2>' +
    '<span class="dep-graph-summary">' + parts.join(' \u00B7 ') + '</span>';
  el.appendChild(header);

  // Build adjacency
  const edgeMap = {};
  for (const edge of DEP_GRAPH.edges) {
    if (!edgeMap[edge.from]) edgeMap[edge.from] = [];
    edgeMap[edge.from].push(edge);
  }
  const nodeMap = {};
  for (const node of DEP_GRAPH.nodes) nodeMap[node.name] = node;

  // Build tree
  const tree = document.createElement('div');
  tree.className = 'dep-tree';

  function buildTreeNode(name, visited) {
    const node = nodeMap[name];
    if (!node) return null;
    const li = document.createElement('div');
    li.className = 'dep-node' + (node.isSystemLibrary ? ' system' : '') + (node.nodeType === 'spmPackage' ? ' spm' : '');

    const label = document.createElement('span');
    label.className = 'dep-label';
    label.textContent = name + (node.nodeType === 'spmPackage' ? ' (SPM)' : '');
    li.appendChild(label);

    if (node.binarySize > 0) {
      const sz = document.createElement('span');
      sz.className = 'dep-size';
      sz.textContent = formatSize(node.binarySize);
      li.appendChild(sz);
    } else if (node.nodeType === 'spmPackage') {
      const sz = document.createElement('span');
      sz.className = 'dep-size';
      sz.textContent = '(statically linked)';
      li.appendChild(sz);
    }

    const edges = edgeMap[name] || [];
    const deps = edges.filter(e => !nodeMap[e.to]?.isSystemLibrary);
    const sysDeps = edges.filter(e => nodeMap[e.to]?.isSystemLibrary);

    if (deps.length > 0 && !visited.has(name)) {
      visited.add(name);
      const toggle = document.createElement('span');
      toggle.className = 'dep-toggle';
      toggle.textContent = '\u25BC';
      li.insertBefore(toggle, label);

      const children = document.createElement('div');
      children.className = 'dep-children';

      for (const edge of deps) {
        const tags = [];
        if (edge.linkType === 'weak') tags.push('[weak]');
        if (edge.linkType === 'lazy') tags.push('[lazy]');
        if (edge.isRedundant) tags.push('[redundant]');

        const child = buildTreeNode(edge.to, new Set(visited));
        if (child) {
          if (tags.length > 0) {
            const tagSpan = document.createElement('span');
            tagSpan.className = 'dep-tag';
            tagSpan.textContent = ' ' + tags.join(' ');
            child.insertBefore(tagSpan, child.children[child.children.length - 1]);
          }
          children.appendChild(child);
        }
      }

      if (sysDeps.length > 0) {
        for (const edge of sysDeps) {
          const sysNode = document.createElement('div');
          sysNode.className = 'dep-node system';
          const sysName = edge.to;
          let tagStr = '';
          if (edge.linkType === 'weak') tagStr = ' <span class="dep-tag">[weak]</span>';
          if (edge.linkType === 'lazy') tagStr = ' <span class="dep-tag">[lazy]</span>';
          sysNode.innerHTML = '<span class="dep-label">' + escapeHTML(sysName) + '</span>' + tagStr;
          children.appendChild(sysNode);
        }
      }

      li.appendChild(children);

      toggle.addEventListener('click', (e) => {
        e.stopPropagation();
        const open = children.style.display !== 'none';
        children.style.display = open ? 'none' : 'block';
        toggle.textContent = open ? '\u25B6' : '\u25BC';
      });

      visited.delete(name);
    } else if (sysDeps.length > 0) {
      // Leaf node with only system deps — show them inline
      const sysToggle = document.createElement('span');
      sysToggle.className = 'dep-toggle';
      sysToggle.textContent = '\u25B6';
      li.insertBefore(sysToggle, label);

      const sysChildren = document.createElement('div');
      sysChildren.className = 'dep-children';
      sysChildren.style.display = 'none';
      for (const edge of sysDeps) {
        const sysNode = document.createElement('div');
        sysNode.className = 'dep-node system';
        sysNode.innerHTML = '<span class="dep-label">' + escapeHTML(edge.to) + '</span>';
        sysChildren.appendChild(sysNode);
      }
      li.appendChild(sysChildren);

      sysToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        const open = sysChildren.style.display !== 'none';
        sysChildren.style.display = open ? 'none' : 'block';
        sysToggle.textContent = open ? '\u25B6' : '\u25BC';
      });
    }

    return li;
  }

  const rootNode = buildTreeNode(DEP_GRAPH.rootNode, new Set());
  if (rootNode) tree.appendChild(rootNode);

  el.appendChild(tree);

  // Heaviest chain
  if (DEP_GRAPH.heaviestChain && DEP_GRAPH.heaviestChain.path.length >= 1 && DEP_GRAPH.nodes.filter(n => !n.isSystemLibrary).length > 1) {
    const chain = document.createElement('div');
    chain.className = 'dep-chain';
    const chainPct = DATA.size > 0
      ? ((DEP_GRAPH.heaviestChain.totalSize / DATA.size) * 100).toFixed(1) : '0';
    chain.innerHTML =
      '<strong>Heaviest Dependency Chain</strong> \u2014 ' +
      formatSize(DEP_GRAPH.heaviestChain.totalSize) +
      ' (' + chainPct + '% of bundle)' +
      '<br><code>' + DEP_GRAPH.heaviestChain.path.join(' \u2192 ') + '</code>' +
      '<div class="dep-chain-desc">The longest chain of non-system dependencies by cumulative size. ' +
      'A heavy chain means a single dependency pulls in significant transitive weight. ' +
      'To reduce: replace heavy leaf dependencies with lighter alternatives, split large frameworks, ' +
      'or lazy-load frameworks that aren\u2019t needed at launch.</div>';
    el.appendChild(chain);
  }
}

renderDepGraph();
window.addEventListener('resize', () => render(currentNode));
render(currentNode);
renderBreadcrumb();
