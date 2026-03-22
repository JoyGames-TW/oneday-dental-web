const fs = require('fs');
const path = require('path');

const siteRoot = path.resolve(__dirname, '..', 'site');
const imagesRoot = path.join(siteRoot, 'images');
const imageExt = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.avif', '.bmp', '.ico']);

function walk(dir, out = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === 'images') continue;
      walk(full, out);
    } else if (e.isFile() && e.name.toLowerCase().endsWith('.html')) {
      out.push(full);
    }
  }
  return out;
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function toPosix(p) {
  return p.replace(/\\/g, '/');
}

function pageKeyFromHtml(htmlPath) {
  const rel = toPosix(path.relative(siteRoot, htmlPath));
  const noHtml = rel.endsWith('/index.html') ? rel.slice(0, -('/index.html'.length)) : rel.slice(0, -('.html'.length));
  if (!noHtml) return 'home';
  return noHtml;
}

function parseUrlParts(raw) {
  const m = raw.match(/^([^?#]+)(\?[^#]*)?(#.*)?$/);
  if (!m) return { pathname: raw, query: '', hash: '' };
  return {
    pathname: m[1] || '',
    query: m[2] || '',
    hash: m[3] || ''
  };
}

function isLocalCandidate(url) {
  return !/^(https?:|\/\/|data:|mailto:|tel:)/i.test(url);
}

function resolveSource(htmlPath, urlPath) {
  const cleaned = urlPath.replace(/\\/g, '/');
  if (cleaned.startsWith('/')) {
    return path.join(siteRoot, cleaned.slice(1));
  }
  return path.resolve(path.dirname(htmlPath), cleaned);
}

function uniqueDestPath(destDir, baseName, sourcePath, usedByDestName) {
  const parsed = path.parse(baseName);
  let candidate = baseName;
  let i = 1;
  while (true) {
    const existingSrc = usedByDestName.get(candidate);
    if (!existingSrc || existingSrc === sourcePath) {
      usedByDestName.set(candidate, sourcePath);
      return path.join(destDir, candidate);
    }
    candidate = `${parsed.name}-${i}${parsed.ext}`;
    i += 1;
  }
}

function buildUrlReplacer(htmlPath, pageKey, stats) {
  const destDir = path.join(imagesRoot, pageKey);
  ensureDir(destDir);
  const usedByDestName = new Map();
  const urlMap = new Map();

  function mapUrl(rawUrl) {
    if (!isLocalCandidate(rawUrl)) return rawUrl;
    const { pathname, query, hash } = parseUrlParts(rawUrl);
    const ext = path.extname(pathname).toLowerCase();
    if (!imageExt.has(ext)) return rawUrl;

    const sourcePath = resolveSource(htmlPath, pathname);
    if (!fs.existsSync(sourcePath) || !fs.statSync(sourcePath).isFile()) {
      stats.missing += 1;
      return rawUrl;
    }

    const key = `${pathname}||${sourcePath}`;
    let mapped = urlMap.get(key);
    if (!mapped) {
      const destPath = uniqueDestPath(destDir, path.basename(pathname), sourcePath, usedByDestName);
      if (!fs.existsSync(destPath)) {
        fs.copyFileSync(sourcePath, destPath);
        stats.copied += 1;
      }
      const relDest = toPosix(path.relative(siteRoot, destPath));
      mapped = `/${relDest}`;
      urlMap.set(key, mapped);
    }

    stats.rewrittenRefs += 1;
    return `${mapped}${query}${hash}`;
  }

  return mapUrl;
}

function rewriteHtml(htmlPath, stats) {
  const pageKey = pageKeyFromHtml(htmlPath);
  const mapUrl = buildUrlReplacer(htmlPath, pageKey, stats);

  const original = fs.readFileSync(htmlPath, 'utf8');
  let updated = original;

  updated = updated.replace(/\b(src|href|poster)\s*=\s*(["'])([^"']+)\2/gi, (full, attr, q, url) => {
    const newUrl = mapUrl(url);
    if (newUrl === url) return full;
    return `${attr}=${q}${newUrl}${q}`;
  });

  updated = updated.replace(/\bsrcset\s*=\s*(["'])([^"']+)\1/gi, (full, q, setVal) => {
    const items = setVal.split(',').map((item) => {
      const trimmed = item.trim();
      if (!trimmed) return trimmed;
      const firstSpace = trimmed.search(/\s/);
      const url = firstSpace === -1 ? trimmed : trimmed.slice(0, firstSpace);
      const desc = firstSpace === -1 ? '' : trimmed.slice(firstSpace);
      const newUrl = mapUrl(url);
      return `${newUrl}${desc}`;
    });
    const next = items.join(', ');
    if (next === setVal) return full;
    return `srcset=${q}${next}${q}`;
  });

  updated = updated.replace(/url\((['"]?)([^)"']+)\1\)/gi, (full, q, raw) => {
    const newUrl = mapUrl(raw.trim());
    if (newUrl === raw.trim()) return full;
    const quote = q || '';
    return `url(${quote}${newUrl}${quote})`;
  });

  if (updated !== original) {
    fs.writeFileSync(htmlPath, updated, 'utf8');
    stats.changedFiles += 1;
  }
}

function main() {
  ensureDir(imagesRoot);
  const htmlFiles = walk(siteRoot);
  const stats = {
    htmlFiles: htmlFiles.length,
    changedFiles: 0,
    copied: 0,
    rewrittenRefs: 0,
    missing: 0
  };

  for (const htmlPath of htmlFiles) {
    rewriteHtml(htmlPath, stats);
  }

  console.log(JSON.stringify(stats, null, 2));
}

main();
