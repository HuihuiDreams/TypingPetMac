import { renderToString } from 'react-dom/server';
import App from './App';
import { content, type Locale } from './content';

export { content };
export { locales, localeMetadata, resolveLocale } from './localization';
export function render(locale: Locale, page: 'home' | 'changelog' | 'unsubscribe') {
  return renderToString(<App locale={locale} page={page} />);
}
