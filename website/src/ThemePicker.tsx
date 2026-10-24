import { useEffect, useId, useRef, useState } from 'react';
import { Monitor, Moon, Sun } from 'lucide-react';
import type { Locale } from './localization';
import { mountTheme, type ThemeMode } from './theme';

const text = {
  ko: { label: '화면 모드', system: '시스템 설정', light: '라이트', dark: '다크' },
  en: { label: 'Appearance', system: 'System', light: 'Light', dark: 'Dark' },
  ja: { label: '表示モード', system: 'システム設定', light: 'ライト', dark: 'ダーク' },
  'zh-Hans': { label: '显示模式', system: '跟随系统', light: '浅色', dark: '深色' },
  'zh-Hant': { label: '顯示模式', system: '跟隨系統', light: '淺色', dark: '深色' },
};
const modes = ['system', 'light', 'dark'] as const;
const icons = { system: Monitor, light: Sun, dark: Moon };

export default function ThemePicker({ locale }: { locale: Locale }) {
  const t = text[locale];
  // The server and first client render agree; the head script already applied the palette.
  const [mode, setMode] = useState<ThemeMode>('system');
  const controller = useRef<ReturnType<typeof mountTheme> | null>(null);
  const menu = useRef<HTMLDetailsElement>(null);
  const id = useId();
  const CurrentIcon = icons[mode];
  useEffect(() => {
    const theme = mountTheme(setMode);
    controller.current = theme;
    function outside(event: PointerEvent) {
      if (event.target instanceof Node && !menu.current?.contains(event.target) && menu.current) menu.current.open = false;
    }
    document.addEventListener('pointerdown', outside);
    return () => {
      theme.destroy(); controller.current = null;
      document.removeEventListener('pointerdown', outside);
    };
  }, []);
  function close() {
    if (menu.current) {
      menu.current.open = false;
      menu.current.querySelector('summary')?.focus();
    }
  }
  return <details ref={menu} className="theme-picker" onKeyDown={event => {
    if (event.key === 'Escape') { event.preventDefault(); close(); }
  }} onToggle={event => {
    if (event.currentTarget.open) document.querySelector('.language-menu')?.removeAttribute('open');
  }}>
    <summary className="theme-toggle" aria-label={`${t.label}: ${t[mode]}`} title={`${t.label}: ${t[mode]}`}>
      <CurrentIcon size={18} aria-hidden="true" />
    </summary>
    <fieldset className="theme-options" aria-label={t.label}>
      <legend>{t.label}</legend>
      {modes.map(value => {
        const Icon = icons[value];
        return <label key={value}>
          <Icon size={17} aria-hidden="true" />
          <span>{t[value]}</span>
          <input type="radio" name={`${id}-theme`} value={value} checked={mode === value} onChange={() => {
            controller.current?.choose(value); close();
          }} />
        </label>;
      })}
    </fieldset>
  </details>;
}
