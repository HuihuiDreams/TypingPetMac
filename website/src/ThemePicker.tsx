import { useEffect, useRef, useState } from 'react';
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
const icons = { system: Monitor, light: Sun, dark: Moon };

export default function ThemePicker({ locale }: { locale: Locale }) {
  const t = text[locale];
  const [mode, setMode] = useState<ThemeMode>('system');
  const controller = useRef<ReturnType<typeof mountTheme> | null>(null);
  const CurrentIcon = icons[mode];
  useEffect(() => {
    const theme = mountTheme(setMode);
    controller.current = theme;
    return () => {
      theme.destroy(); controller.current = null;
    };
  }, []);
  return <button
    type="button"
    className="theme-toggle"
    aria-label={`${t.label}: ${t[mode]}`}
    data-tooltip={`${t.label}: ${t[mode]}`}
    onClick={() => controller.current?.toggle()}
  >
    <CurrentIcon size={18} aria-hidden="true" />
  </button>;
}
