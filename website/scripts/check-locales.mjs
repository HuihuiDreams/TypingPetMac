import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { content, locales, localeMetadata, resolveLocale } from '../.runtime/ssr/entry-server.js';

for (const [input, expected] of [
  ['ko_KR', 'ko'], ['en-US', 'en'], ['ja-JP', 'ja'], ['ja_JP', 'ja'],
  ['zh', 'zh-Hans'], ['zh-CN', 'zh-Hans'], ['zh-SG', 'zh-Hans'], ['zh_Hans_CN', 'zh-Hans'],
  ['zh-Hans-HK', 'zh-Hans'], ['zh-TW', 'zh-Hant'], ['zh-HK', 'zh-Hant'], ['zh-MO', 'zh-Hant'],
  ['zh_Hant_TW', 'zh-Hant'], ['zh-Hant-CN', 'zh-Hant'], ['fr', 'en'], ['kok-IN', 'en'], ['jaq', 'en'], ['', 'en'],
]) assert.equal(resolveLocale(input), expected, input);

const notes = JSON.parse(await readFile('src/releases.json', 'utf8'));
const release = JSON.parse(await readFile('src/generated/release.json', 'utf8'));
for (const locale of locales) {
  assert.deepEqual(Object.keys(content[locale]).sort(), Object.keys(content.en).sort(), `${locale} content keys`);
  for (const [key, value] of Object.entries(content[locale])) {
    assert.ok(value.flat?.(2).every(item => typeof item === 'string' && item.trim()) ?? (typeof value === 'string' && value.trim()), `${locale}.${key}`);
  }
  for (const note of notes) {
    assert.ok(note[locale]?.title?.trim() && note[locale]?.items.length, `${locale} release ${note.version}`);
    assert.equal(note[locale].items.length, note.en.items.length, `${locale} release item count`);
  }
  for (const suffix of ['', 'changelog/']) {
    const html = await readFile(`dist/${locale}/${suffix}index.html`, 'utf8');
    assert.ok(html.includes(`<html lang="${locale}">`));
    assert.ok(html.includes(`content="${localeMetadata[locale].og}"`));
    assert.ok(html.includes(`rel="canonical" href="https://typing-pet.miel.ing/${locale}/${suffix}"`));
    for (const alternate of locales) {
      assert.ok(html.includes(`hreflang="${alternate}" href="https://typing-pet.miel.ing/${alternate}/${suffix}"`));
    }
    assert.ok(html.includes(notes.find(note => note.version === release.version)[locale].title));
    if (!suffix) {
      assert.ok(html.includes(content[locale].hero1));
      assert.ok(html.includes(`href="${release.githubUrl}"`), 'ZIP download retained');
      if (release.dmg) {
        assert.ok(html.includes(`href="${release.dmg.githubUrl}"`), 'DMG download');
        assert.ok(html.includes(content[locale].dmgTab), 'translated DMG tab');
      }
    }
    assert.ok(!html.includes('undefined'));
    const themeScript = html.match(/<script src="(\/assets\/theme-([a-f0-9]{12})\.js)"><\/script>/);
    assert.ok(themeScript, `${locale}/${suffix} blocking theme bootstrap`);
    assert.ok(themeScript.index < html.indexOf('rel="stylesheet"'), 'apply saved appearance before CSS and page content');
    const themeBytes = await readFile(`dist${themeScript[1]}`);
    assert.equal(createHash('sha256').update(themeBytes).digest('hex').slice(0, 12), themeScript[2]);
    assert.ok(html.includes('class="theme-picker"'));
    assert.equal((html.match(/type="radio"/g) || []).length, 3, 'three appearance choices');
  }
}
const sitemap = await readFile('dist/sitemap.xml', 'utf8');
assert.equal((sitemap.match(/<loc>/g) || []).length, locales.length * 2);
console.log(`Verified language detection, translated content and notes, and ${locales.length * 2} pre-rendered pages.`);
