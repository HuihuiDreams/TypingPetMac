export type ThemeMode = 'system' | 'light' | 'dark';
const storageKey = 'typingpet-theme';

function readMode(): ThemeMode {
  try {
    const saved = localStorage.getItem(storageKey);
    if (saved === 'light' || saved === 'dark') return saved;
  } catch {}
  return 'system';
}

function apply(mode: ThemeMode, systemDark: boolean) {
  const theme = mode === 'system' ? (systemDark ? 'dark' : 'light') : mode;
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
  const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  if (meta) meta.content = theme === 'dark' ? '#18191b' : '#f7f4ec';
}

// The controller also handles changes made in another tab and OS appearance changes.
export function mountTheme(onModeChange: (mode: ThemeMode) => void) {
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  let mode = readMode();
  function update(next: ThemeMode) {
    mode = next;
    apply(mode, media.matches);
    onModeChange(mode);
  }
  function systemChanged() { apply(mode, media.matches); }
  function storageChanged(event: StorageEvent) {
    if (event.key === storageKey || event.key === null) update(readMode());
  }
  update(mode);
  media.addEventListener('change', systemChanged);
  window.addEventListener('storage', storageChanged);
  return {
    choose(next: ThemeMode) {
      try { localStorage.setItem(storageKey, next); } catch {}
      update(next);
    },
    toggle() {
      const next = mode === 'system' ? (media.matches ? 'light' : 'dark') : 'system';
      try {
        if (next === 'system') localStorage.removeItem(storageKey);
        else localStorage.setItem(storageKey, next);
      } catch {}
      update(next);
    },
    destroy() {
      media.removeEventListener('change', systemChanged);
      window.removeEventListener('storage', storageChanged);
    },
  };
}
