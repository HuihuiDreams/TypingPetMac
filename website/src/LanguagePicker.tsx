import { Menu } from '@base-ui/react/menu';
import { Check, ChevronDown, Languages } from 'lucide-react';
import { content, type Locale } from './content';
import { locales, localeMetadata } from './localization';
import { trackSiteEvent } from './analytics';

export default function LanguagePicker({ locale, page }: { locale: Locale; page: 'home' | 'changelog' | 'unsubscribe' }) {
  const t = content[locale];
  return <Menu.Root>
    <Menu.Trigger className="language-switch" aria-label={`${t.languageLabel}: ${localeMetadata[locale].label}`}>
      <Languages size={15} aria-hidden="true" />{localeMetadata[locale].label}<ChevronDown size={14} aria-hidden="true" />
    </Menu.Trigger>
    <Menu.Portal>
      <Menu.Positioner className="ui-positioner" sideOffset={10} align="end" collisionPadding={12}>
        <Menu.Popup className="ui-popup language-options" aria-label={t.languageLabel}>
          {locales.map(language => <Menu.LinkItem key={language} className="ui-item" closeOnClick
            href={`/${language}/${page === 'changelog' ? 'changelog/' : page === 'unsubscribe' ? 'unsubscribe/' : ''}`} hrefLang={language} lang={language}
            label={localeMetadata[language].label} aria-current={locale === language ? 'page' : undefined}
            onClick={event => {
              event.currentTarget.href = `/${language}/${page === 'changelog' ? 'changelog/' : page === 'unsubscribe' ? 'unsubscribe/' : ''}` + window.location.search + window.location.hash;
              try { localStorage.setItem('typingpet-language', language); } catch {}
              if (language !== locale) trackSiteEvent({ event: 'language_changed', to_locale: language });
            }}>
            <span>{localeMetadata[language].label}</span>
            <span className="ui-indicator">{locale === language && <Check size={16} aria-hidden="true" />}</span>
          </Menu.LinkItem>)}
        </Menu.Popup>
      </Menu.Positioner>
    </Menu.Portal>
  </Menu.Root>;
}
