import metadata from './locales.json';

export type Locale = keyof typeof metadata;
export const localeMetadata = metadata;
export const locales = Object.keys(metadata) as Locale[];
export const isLocale = (value: string): value is Locale => Object.hasOwn(metadata, value);

// Follow the first browser language, matching the app. An explicit script wins over a region.
export function resolveLocale(language = 'en'): Locale {
  const parts = language.toLowerCase().replaceAll('_', '-').split('-');
  if (parts[0] === 'ko' || parts[0] === 'ja') return parts[0];
  if (parts[0] === 'zh') {
    if (parts.includes('hant')) return 'zh-Hant';
    if (parts.includes('hans')) return 'zh-Hans';
    return parts.some(p => ['tw', 'hk', 'mo'].includes(p)) ? 'zh-Hant' : 'zh-Hans';
  }
  return 'en';
}
