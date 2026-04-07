//
//  HTMLFormatter.swift
//  BundleProfiler
//
//  Created by Khoren Katklian on 06/04/2026.
//  MIT
//

import Foundation

/// Formats bundle analysis as a self-contained HTML treemap report.
public struct HTMLFormatter: Sendable {
    public init() {}

    /// Format a BundleInfo as a self-contained HTML document with an interactive treemap.
    public func format(bundle: BundleInfo) throws -> String {
        let rootJSON = buildTreeJSON(from: bundle.files, bundleName: bundle.bundleName)
        let jsonData = try JSONSerialization.data(withJSONObject: rootJSON, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Bundle Report — \(escapeHTML(bundle.bundleName))</title>
        <style>
        \(Self.css)
        </style>
        </head>
        <body>
        <div id="header">
          <h1>\(escapeHTML(bundle.bundleName))</h1>
          <span class="total">Total: \(SizeFormatter.format(bundle.totalSize))</span>
        </div>
        <div id="breadcrumb"></div>
        <div id="treemap"></div>
        <div id="tooltip"></div>
        <script>
        const DATA = \(jsonString);
        \(Self.javascript)
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Tree Building

    private func buildTreeJSON(from files: [FileEntry], bundleName: String) -> [String: Any] {
        // Build nested dictionary tree from flat file paths
        var root: [String: Any] = ["name": bundleName, "size": 0 as UInt64]
        var rootChildren: [[String: Any]] = []

        // Group files by top-level directory
        var dirMap: [String: [FileEntry]] = [:]
        var topFiles: [FileEntry] = []

        for file in files {
            let components = file.relativePath.split(separator: "/", maxSplits: 1).map(String.init)
            if components.count == 1 {
                topFiles.append(file)
            } else {
                dirMap[components[0], default: []].append(
                    FileEntry(
                        relativePath: String(components[1]),
                        size: file.size,
                        category: file.category,
                        contentHash: file.contentHash
                    )
                )
            }
        }

        // Build directory nodes recursively
        for (dirName, dirFiles) in dirMap.sorted(by: { $0.value.reduce(0) { $0 + $1.size } > $1.value.reduce(0) { $0 + $1.size } }) {
            rootChildren.append(buildDirectoryJSON(name: dirName, files: dirFiles))
        }

        // Add top-level files
        for file in topFiles.sorted(by: { $0.size > $1.size }) {
            rootChildren.append([
                "name": file.relativePath,
                "size": file.size,
                "category": file.category.rawValue,
            ] as [String: Any])
        }

        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }
        root["size"] = totalSize
        root["children"] = rootChildren
        return root
    }

    private func buildDirectoryJSON(name: String, files: [FileEntry]) -> [String: Any] {
        var children: [[String: Any]] = []
        var subDirs: [String: [FileEntry]] = [:]
        var directFiles: [FileEntry] = []

        for file in files {
            let components = file.relativePath.split(separator: "/", maxSplits: 1).map(String.init)
            if components.count == 1 {
                directFiles.append(file)
            } else {
                subDirs[components[0], default: []].append(
                    FileEntry(
                        relativePath: String(components[1]),
                        size: file.size,
                        category: file.category,
                        contentHash: file.contentHash
                    )
                )
            }
        }

        for (dirName, dirFiles) in subDirs.sorted(by: { $0.value.reduce(0) { $0 + $1.size } > $1.value.reduce(0) { $0 + $1.size } }) {
            children.append(buildDirectoryJSON(name: dirName, files: dirFiles))
        }

        for file in directFiles.sorted(by: { $0.size > $1.size }) {
            children.append([
                "name": file.relativePath,
                "size": file.size,
                "category": file.category.rawValue,
            ] as [String: Any])
        }

        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }
        return [
            "name": name,
            "size": totalSize,
            "children": children,
        ] as [String: Any]
    }

    // MARK: - HTML Escaping

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Embedded Assets

    private static let css = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background: #1a1a2e; color: #e0e0e0; }
    #header { display: flex; justify-content: space-between; align-items: center; padding: 16px 24px; background: #16213e; }
    #header h1 { font-size: 20px; font-weight: 600; }
    .total { font-size: 16px; color: #a0a0b0; }
    #breadcrumb { padding: 8px 24px; background: #1a1a2e; font-size: 13px; color: #8888aa; min-height: 32px; display: flex; align-items: center; gap: 4px; }
    #breadcrumb span { cursor: pointer; }
    #breadcrumb span:hover { color: #ffffff; text-decoration: underline; }
    #breadcrumb .sep { color: #555; cursor: default; }
    #treemap { position: relative; width: calc(100vw - 48px); height: calc(100vh - 120px); margin: 0 24px 24px; }
    .node { position: absolute; overflow: hidden; cursor: pointer; border: 1px solid rgba(0,0,0,0.3); transition: opacity 0.15s; }
    .node:hover { opacity: 0.85; }
    .node-label { position: absolute; top: 4px; left: 6px; right: 6px; font-size: 11px; font-weight: 500; color: #fff; text-shadow: 0 1px 2px rgba(0,0,0,0.7); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; pointer-events: none; }
    .node-size { position: absolute; top: 18px; left: 6px; font-size: 10px; color: rgba(255,255,255,0.7); text-shadow: 0 1px 2px rgba(0,0,0,0.5); pointer-events: none; }
    #tooltip { display: none; position: fixed; background: #222244; border: 1px solid #444466; border-radius: 6px; padding: 10px 14px; font-size: 13px; pointer-events: none; z-index: 100; max-width: 350px; box-shadow: 0 4px 12px rgba(0,0,0,0.5); }
    #tooltip .tt-name { font-weight: 600; margin-bottom: 4px; }
    #tooltip .tt-size { color: #aaa; }
    #tooltip .tt-cat { color: #8888cc; font-size: 12px; }
    """

    private static let javascript = """
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

    assignColors(DATA);

    function render(node) {
      container.innerHTML = '';
      const rect = container.getBoundingClientRect();
      const children = node.children || [];
      if (!children.length) return;

      const rects = squarify(children, 0, 0, rect.width, rect.height);

      for (const r of rects) {
        if (r.w < 2 || r.h < 2) continue;

        const el = document.createElement('div');
        el.className = 'node';
        el.style.left = r.x + 'px';
        el.style.top = r.y + 'px';
        el.style.width = r.w + 'px';
        el.style.height = r.h + 'px';
        el.style.background = r.node._color || getColor(r.node);

        if (r.w > 40 && r.h > 18) {
          const label = document.createElement('div');
          label.className = 'node-label';
          label.textContent = r.node.name;
          el.appendChild(label);
        }
        if (r.w > 60 && r.h > 32) {
          const sizeLabel = document.createElement('div');
          sizeLabel.className = 'node-size';
          sizeLabel.textContent = formatSize(r.node.size);
          el.appendChild(sizeLabel);
        }

        el.addEventListener('click', () => {
          if (r.node.children && r.node.children.length > 0) {
            pathStack.push(currentNode);
            currentNode = r.node;
            render(currentNode);
            renderBreadcrumb();
          }
        });

        el.addEventListener('mouseenter', (e) => {
          tooltip.style.display = 'block';
          let html = '<div class="tt-name">' + escapeHTML(r.node.name) + '</div>';
          html += '<div class="tt-size">' + formatSize(r.node.size) + '</div>';
          if (r.node.category) html += '<div class="tt-cat">' + r.node.category + '</div>';
          if (r.node.children) html += '<div class="tt-cat">' + r.node.children.length + ' items</div>';
          tooltip.innerHTML = html;
        });

        el.addEventListener('mousemove', (e) => {
          tooltip.style.left = (e.clientX + 12) + 'px';
          tooltip.style.top = (e.clientY + 12) + 'px';
        });

        el.addEventListener('mouseleave', () => {
          tooltip.style.display = 'none';
        });

        container.appendChild(el);
      }
    }

    function renderBreadcrumb() {
      breadcrumb.innerHTML = '';
      const all = [...pathStack, currentNode];
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

    window.addEventListener('resize', () => render(currentNode));
    render(currentNode);
    renderBreadcrumb();
    """
}
