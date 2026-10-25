import { useEffect, useState } from 'react';
import { Switch } from '@base-ui/react/switch';
import type { Locale } from './localization';
import { analyticsEnabled, browserRejectsAnalytics, setAnalyticsEnabled } from './analytics';

const text = {
  ko: { notice: '이 웹사이트는 PostHog로 이용 패턴을 분석합니다. 입력 내용과 화면은 수집하지 않습니다.', label: '방문 통계', blocked: '브라우저 설정으로 통계 꺼짐' },
  en: { notice: 'This website uses PostHog to measure visits and install actions. Typed content and screen recordings are never collected.', label: 'Visit analytics', blocked: 'Analytics disabled by your browser' },
  ja: { notice: 'このサイトではPostHogで訪問とインストール操作を分析します。入力内容や画面録画は収集しません。', label: 'アクセス解析', blocked: 'ブラウザの設定で解析はオフです' },
  'zh-Hans': { notice: '本网站使用PostHog分析访问和安装操作，不收集输入内容或录制屏幕。', label: '访问统计', blocked: '浏览器设置已关闭统计' },
  'zh-Hant': { notice: '本網站使用PostHog分析造訪和安裝操作，不收集輸入內容或錄製畫面。', label: '造訪統計', blocked: '瀏覽器設定已關閉統計' },
};

export default function AnalyticsNotice({ locale }: { locale: Locale }) {
  const t = text[locale];
  const [enabled, setEnabled] = useState(true);
  const [blocked, setBlocked] = useState(false);
  useEffect(() => { setEnabled(analyticsEnabled()); setBlocked(browserRejectsAnalytics()); }, []);
  function toggle(checked: boolean) {
    setAnalyticsEnabled(checked);
    setEnabled(analyticsEnabled());
  }
  return <aside className="analytics-notice section"><p>{t.notice}</p><label className="analytics-setting"><Switch.Root className="analytics-switch" checked={enabled} onCheckedChange={toggle} disabled={blocked}><Switch.Thumb className="analytics-switch-thumb" /></Switch.Root><span>{blocked ? t.blocked : t.label}</span></label></aside>;
}
