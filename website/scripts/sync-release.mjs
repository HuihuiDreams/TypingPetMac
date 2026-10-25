import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const feedUrl = 'https://pet.miel.ing/update/production/latest.json';
async function getJson(url) {
  const response = await fetch(url, { headers: { Accept: 'application/json', 'User-Agent': 'TypingPet-website-publisher' }, signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response.json();
}
const feed = await getJson(feedUrl);
if (!/^\d+\.\d+\.\d+$/.test(feed.version) || !Number.isSafeInteger(feed.build)) throw new Error('Invalid feed version/build');
const expectedUrl = `https://pet.miel.ing/update/production/TypingPet-${feed.version}-${feed.build}-arm64.zip`;
if (feed.url !== expectedUrl || !/^[a-f0-9]{64}$/.test(feed.sha256)) throw new Error('Unexpected update archive URL or digest');
const release = await getJson(`https://api.github.com/repos/ynifamily3/TypingPetMac/releases/tags/v${feed.version}`);
if (release.draft || release.tag_name !== `v${feed.version}`) throw new Error('Matching GitHub release is not public');
const asset = release.assets.find(a => a.name === `TypingPetMac-v${feed.version}-arm64.zip`);
const checksum = release.assets.find(a => a.name === `TypingPetMac-v${feed.version}-arm64.zip.sha256`);
if (!asset || !checksum || asset.size !== feed.size || asset.digest !== `sha256:${feed.sha256}`) throw new Error('GitHub ZIP does not match the update feed');
// A DMG is optional: older releases and update-only releases can keep using ZIPs.
const dmgAsset = [`TypingPetMac-v${feed.version}-arm64-installer.dmg`, `TypingPetMac-v${feed.version}-arm64.dmg`]
  .map(name => release.assets.find(a => a.name === name)).find(Boolean);
const dmgChecksum = dmgAsset && release.assets.find(a => a.name === `${dmgAsset.name}.sha256`);
let dmg = null;
if (dmgAsset) {
  const url = `https://pet.miel.ing/update/production/${dmgAsset.name}`;
  if (!dmgChecksum || !/^sha256:[a-f0-9]{64}$/.test(dmgAsset.digest) || !Number.isSafeInteger(dmgAsset.size) || dmgAsset.size <= 0) throw new Error('Invalid GitHub DMG or missing checksum');
  const response = await fetch(url, { signal: AbortSignal.timeout(40000) });
  if (!response.ok) throw new Error(`DMG: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), byte => byte.toString(16).padStart(2, '0')).join('');
  if (bytes.length !== dmgAsset.size || `sha256:${sha256}` !== dmgAsset.digest) throw new Error('Hosted DMG differs from GitHub');
  const checksumResponse = await fetch(dmgChecksum.browser_download_url, { signal: AbortSignal.timeout(20000) });
  if (!checksumResponse.ok || (await checksumResponse.text()).trim() !== `${sha256}  ${dmgAsset.name}`) throw new Error('DMG checksum file differs from GitHub digest');
  dmg = { url, size: dmgAsset.size, sha256, githubUrl: dmgAsset.browser_download_url, checksumUrl: dmgChecksum.browser_download_url };
}
const notes = JSON.parse(await readFile(join(root, 'src/releases.json'), 'utf8'));
const locales = Object.keys(JSON.parse(await readFile(join(root, 'src/locales.json'), 'utf8')));
if (!notes.some(n => n.version === feed.version)) throw new Error(`Write notes for ${feed.version} in src/releases.json first`);
for (const note of notes) {
  for (const locale of locales) {
    const translation = note[locale];
    if (!translation?.title?.trim() || !Array.isArray(translation.items) || !translation.items.length || !translation.items.every(item => typeof item === 'string' && item.trim())) {
      throw new Error(`Write ${locale} notes for ${note.version} in src/releases.json first`);
    }
  }
}
const output = { version: feed.version, build: feed.build, date: release.published_at.slice(0, 10), prerelease: release.prerelease,
  size: feed.size, sha256: feed.sha256, url: feed.url, githubUrl: asset.browser_download_url,
  checksumUrl: checksum.browser_download_url, releaseUrl: release.html_url, minimumSystemVersion: feed.minimumSystemVersion, dmg };
await mkdir(join(root, 'src/generated'), { recursive: true });
await writeFile(join(root, 'src/generated/release.json'), JSON.stringify(output, null, 2) + '\n');
console.log(`Website release: ${output.version} (${output.build}), matching GitHub and update-server SHA-256.`);
