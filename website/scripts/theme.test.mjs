import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { mountTheme } from '../src/theme.ts';

const bootstrap = await readFile(new URL('../public/theme.js', import.meta.url), 'utf8');
const key = 'typingpet-theme';

function browser({ saved = null, dark = false, blocked = false } = {}) {
  const mediaListeners = new Set();
  const storageListeners = new Set();
  const media = {
    matches: dark,
    addEventListener: (_, callback) => mediaListeners.add(callback),
    removeEventListener: (_, callback) => mediaListeners.delete(callback),
  };
  const document = { documentElement: { dataset: {}, style: {} }, querySelector: () => meta };
  const meta = { content: '' };
  const localStorage = {
    getItem(name) { assert.equal(name, key); if (blocked) throw new Error('Storage denied'); return saved; },
    setItem(name, value) { assert.equal(name, key); if (blocked) throw new Error('Storage denied'); saved = value; },
  };
  const window = {
    matchMedia(query) { assert.equal(query, '(prefers-color-scheme: dark)'); return media; },
    addEventListener: (_, callback) => storageListeners.add(callback),
    removeEventListener: (_, callback) => storageListeners.delete(callback),
  };
  return {
    document, localStorage, window, meta,
    system(dark) { media.matches = dark; mediaListeners.forEach(callback => callback()); },
    storage(value, changedKey = key) { saved = value; storageListeners.forEach(callback => callback({ key: changedKey })); },
    saved: () => saved,
    listeners: () => [mediaListeners.size, storageListeners.size],
    theme: () => document.documentElement.dataset.theme,
  };
}

function mount(env) {
  globalThis.document = env.document;
  globalThis.window = env.window;
  globalThis.localStorage = env.localStorage;
  const modes = [];
  return { ...mountTheme(mode => modes.push(mode)), modes };
}

test('pre-paint bootstrap and mounted controller resolve the same preference', () => {
  for (const saved of [null, 'system', 'light', 'dark', 'invalid']) {
    for (const dark of [false, true]) {
      for (const blocked of [false, true]) {
        const env = browser({ saved, dark, blocked });
        const expected = !blocked && ['light', 'dark'].includes(saved) ? saved : dark ? 'dark' : 'light';
        runInNewContext(bootstrap, env);
        assert.equal(env.theme(), expected);
        assert.equal(env.document.documentElement.style.colorScheme, expected);
        assert.equal(env.meta.content, expected === 'dark' ? '#18191b' : '#f7f4ec');
        const controller = mount(env);
        assert.equal(env.theme(), expected);
        assert.equal(controller.modes.at(-1), !blocked && ['light', 'dark'].includes(saved) ? saved : 'system');
        controller.destroy();
      }
    }
  }
});

test('system follows OS changes; an explicit choice persists and overrides OS', () => {
  const env = browser();
  const controller = mount(env);
  env.system(true);
  assert.equal(env.theme(), 'dark');
  controller.choose('light');
  assert.equal(env.saved(), 'light');
  env.system(false); env.system(true);
  assert.equal(env.theme(), 'light');
  controller.choose('dark');
  env.system(false);
  assert.equal(env.theme(), 'dark');
  controller.choose('system');
  assert.equal(env.saved(), 'system');
  assert.equal(env.theme(), 'light');
  env.system(true);
  assert.equal(env.theme(), 'dark');
  controller.destroy();
});

test('other tabs update the selected mode; removal and clearing return to system', () => {
  const env = browser();
  const controller = mount(env);
  env.storage('dark');
  assert.equal(env.theme(), 'dark');
  assert.equal(controller.modes.at(-1), 'dark');
  env.storage(null);
  assert.equal(env.theme(), 'light');
  assert.equal(controller.modes.at(-1), 'system');
  env.storage('dark');
  env.storage(null, null);
  assert.equal(env.theme(), 'light');
  const count = controller.modes.length;
  env.storage('dark', 'unrelated');
  assert.equal(controller.modes.length, count);
  controller.destroy();
  assert.deepEqual(env.listeners(), [0, 0]);
});

test('manual choice works for the current page when storage is blocked', () => {
  const env = browser({ dark: true, blocked: true });
  const controller = mount(env);
  controller.choose('light');
  env.system(false); env.system(true);
  assert.equal(env.theme(), 'light');
  assert.equal(controller.modes.at(-1), 'light');
  controller.choose('system');
  assert.equal(env.theme(), 'dark');
  controller.destroy();
});
