// Runs before the page paints. Keep preference resolution in sync with src/theme.ts.
(function () {
  var mode = 'system';
  try {
    var saved = localStorage.getItem('typingpet-theme');
    if (saved === 'light' || saved === 'dark') mode = saved;
  } catch (_) {}
  var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  var theme = mode === 'system' ? (dark ? 'dark' : 'light') : mode;
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
  var meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.content = theme === 'dark' ? '#18191b' : '#f7f4ec';
}());
