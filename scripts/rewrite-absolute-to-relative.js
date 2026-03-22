const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const siteDir = path.join(root, 'site');

function walk(dir, out = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.html')) {
      out.push(full);
    }
  }
  return out;
}

function relPrefixForFile(filePath) {
  const relDir = path.relative(siteDir, path.dirname(filePath));
  if (!relDir) return './';
  const depth = relDir.split(path.sep).filter(Boolean).length;
  return '../'.repeat(depth);
}

function toRelative(prefix, urlPath) {
  const clean = urlPath.replace(/^\/+/, '');
  if (!clean) return prefix;
  return prefix + clean;
}

function rewriteHtml(filePath) {
  const prefix = relPrefixForFile(filePath);
  let html = fs.readFileSync(filePath, 'utf8');
  const original = html;

  // Rewrite common URL-bearing attributes that currently use root-absolute paths.
  html = html.replace(
    /(\b(?:href|src|poster|action|data-src|data-href|data-bg|data-thumb)=)(["'])\/(?!\/)([^"']*?)\2/gi,
    (_, attr, quote, value) => `${attr}${quote}${toRelative(prefix, value)}${quote}`
  );

  // Rewrite srcset entries like: /img/a.jpg 1x, /img/b.jpg 2x
  html = html.replace(/(\bsrcset=)(["'])([^"']*?)\2/gi, (_, attr, quote, value) => {
    const rewritten = value
      .split(',')
      .map((part) => {
        const trimmed = part.trim();
        if (!trimmed) return trimmed;
        const bits = trimmed.split(/\s+/);
        if (bits[0].startsWith('/') && !bits[0].startsWith('//')) {
          bits[0] = toRelative(prefix, bits[0]);
        }
        return bits.join(' ');
      })
      .join(', ');
    return `${attr}${quote}${rewritten}${quote}`;
  });

  // Rewrite inline CSS url(/...)
  html = html.replace(/url\((['"]?)\/(?!\/)([^'"\)]+)\1\)/gi, (_, quote, value) => {
    const q = quote || '';
    return `url(${q}${toRelative(prefix, value)}${q})`;
  });

  // In file:// mode, links ending with '/' open a folder listing instead of index.html.
  // Patch only anchor href values so local navigation and GitHub Pages both work.
  html = html.replace(/(<a\b[^>]*\bhref=)(["'])([^"']+)\2/gi, (_, attr, quote, value) => {
    const url = value.trim();

    // Ignore links that are not local page navigation.
    if (!url) return `${attr}${quote}${value}${quote}`;
    if (/^[a-z][a-z0-9+.-]*:/i.test(url)) return `${attr}${quote}${value}${quote}`;
    if (url.startsWith('//') || url.startsWith('#')) return `${attr}${quote}${value}${quote}`;
    if (url.includes('?') || url.includes('#')) return `${attr}${quote}${value}${quote}`;
    if (!url.endsWith('/')) return `${attr}${quote}${value}${quote}`;

    return `${attr}${quote}${url}index.html${quote}`;
  });

  if (html !== original) {
    fs.writeFileSync(filePath, html, 'utf8');
    return true;
  }
  return false;
}

const files = walk(siteDir);
let changed = 0;
for (const file of files) {
  if (rewriteHtml(file)) changed += 1;
}

console.log(JSON.stringify({ scanned: files.length, changed }, null, 2));
