import { hydrateRoot } from 'react-dom/client';
import '@fontsource-variable/space-grotesk';
import App from './App';
import './styles.css';
import './theme.css';
import './controls.css';
import { isLocale, resolveLocale } from './localization';
import { initWebsiteAnalytics } from './analytics';

if (location.pathname === '/') {
  let saved = '';
  try { saved = localStorage.getItem('typingpet-language') || ''; } catch {}
  const locale = isLocale(saved) ? saved : resolveLocale(navigator.languages?.[0] || navigator.language);
  location.replace(`/${locale}/${location.search}${location.hash}`);
} else {
  const pathLocale = location.pathname.split('/')[1];
  const locale = isLocale(pathLocale) ? pathLocale : 'ko';
  const page = location.pathname.includes('/unsubscribe') ? 'unsubscribe' : location.pathname.includes('/changelog') ? 'changelog' : 'home';
  void initWebsiteAnalytics().catch(() => {});
  hydrateRoot(document.getElementById('root')!, <App locale={locale} page={page} />);
}
