import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { render, content, locales, localeMetadata } from '../.runtime/ssr/entry-server.js';
const bootstrap = await readFile('dist/theme.js');
const themeAsset = `/assets/theme-${createHash('sha256').update(bootstrap).digest('hex').slice(0, 12)}.js`;
await mkdir('dist/assets', { recursive: true });
await rename('dist/theme.js', `dist${themeAsset}`);
const template = (await readFile('dist/index.html', 'utf8')).replace('src="/theme.js"', `src="${themeAsset}"`);
const origin = 'https://typing-pet.miel.ing';
const escape = s => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
const paths = [];
for (const locale of locales) {
  for (const page of ['home', 'changelog']) {
    const suffix = page === 'home' ? '' : 'changelog/';
    const path = `/${locale}/${suffix}`;
    const t = content[locale];
    const title = page === 'home' ? t.title : `${t.nav[2]} — Typing Pet for Mac`;
    const description = page === 'home' ? t.description : t.notesPageBody;
    const meta = `<meta name="description" content="${escape(description)}" />
    <link rel="canonical" href="${origin}${path}" />
    ${locales.map(language => `<link rel="alternate" hreflang="${language}" href="${origin}/${language}/${suffix}" />`).join('\n    ')}
    <link rel="alternate" hreflang="x-default" href="${origin}/ko/${suffix}" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Typing Pet" />
    <meta property="og:title" content="${escape(title)}" />
    <meta property="og:description" content="${escape(description)}" />
    <meta property="og:url" content="${origin}${path}" />
    <meta property="og:locale" content="${localeMetadata[locale].og}" />
    ${locales.filter(language => language !== locale).map(language => `<meta property="og:locale:alternate" content="${localeMetadata[language].og}" />`).join('\n    ')}
    <meta property="og:image" content="${origin}/assets/social-preview.png" />
    <meta property="og:image:type" content="image/png" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:image:alt" content="Typing Pet for Mac — A desktop friend for every keystroke" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:site" content="@miel_ggyu" />
    <meta name="twitter:creator" content="@miel_ggyu" />
    <meta name="twitter:title" content="${escape(title)}" />
    <meta name="twitter:description" content="${escape(description)}" />
    <meta name="twitter:image" content="${origin}/assets/social-preview.png" />
    <meta name="twitter:image:alt" content="Typing Pet for Mac — A desktop friend for every keystroke" />
    <link rel="preload" as="image" href="/assets/pet-left.webp" />
    <link rel="preload" as="image" href="/assets/pet-right.webp" />`;
    let html = template.replace('<html lang="ko">', `<html lang="${locale}">`)
      .replace('<title>Typing Pet for Mac</title>', `<title>${escape(title)}</title>`)
      .replace('<!--page-meta-->', meta)
      .replace('<div id="root"></div>', `<div id="root">${render(locale, page)}</div>`);
    await mkdir(`dist${path}`, { recursive: true });
    await writeFile(`dist${path}index.html`, html);
    paths.push(`${origin}${path}`);
  }
}
// A readable Korean fallback also works when JavaScript is disabled.
await writeFile('dist/index.html', (await readFile('dist/ko/index.html', 'utf8')).replace('</head>', '<meta name="robots" content="noindex,follow" /></head>'));
await writeFile('dist/sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${paths.map(url => `<url><loc>${url}</loc></url>`).join('')}</urlset>\n`);
await writeFile('dist/robots.txt', `User-agent: *\nAllow: /\nSitemap: ${origin}/sitemap.xml\n`);
console.log(`Pre-rendered ${paths.length} landing pages and changelogs in ${locales.length} languages.`);
