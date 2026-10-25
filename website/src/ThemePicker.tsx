import { useEffect, useRef, useState } from 'react';
import { Menu } from '@base-ui/react/menu';
import { Check, Monitor, Moon, Sun } from 'lucide-react';
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
  const CurrentIcon = icons[mode];
  useEffect(() => {
    const theme = mountTheme(setMode);
    controller.current = theme;
    return () => {
      theme.destroy(); controller.current = null;
    };
  }, []);
  return <Menu.Root>
    <Menu.Trigger className="theme-toggle" aria-label={`${t.label}: ${t[mode]}`} title={`${t.label}: ${t[mode]}`}>
      <CurrentIcon size={18} aria-hidden="true" />
    </Menu.Trigger>
    <Menu.Portal>
      <Menu.Positioner className="ui-positioner" sideOffset={10} align="end" collisionPadding={12}>
        <Menu.Popup className="ui-popup theme-options" aria-label={t.label}>
          <Menu.RadioGroup value={mode} onValueChange={(value: ThemeMode) => controller.current?.choose(value)}>
            <Menu.GroupLabel className="ui-group-label">{t.label}</Menu.GroupLabel>
            {modes.map(value => {
              const Icon = icons[value];
              return <Menu.RadioItem className="ui-item" key={value} value={value} label={t[value]} closeOnClick>
                <Icon size={17} aria-hidden="true" /><span>{t[value]}</span>
                <Menu.RadioItemIndicator className="ui-indicator"><Check size={16} aria-hidden="true" /></Menu.RadioItemIndicator>
              </Menu.RadioItem>;
            })}
          </Menu.RadioGroup>
        </Menu.Popup>
      </Menu.Positioner>
    </Menu.Portal>
  </Menu.Root>;
}
