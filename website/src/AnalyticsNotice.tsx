import { useEffect, useState } from 'react';
import type { Locale } from './localization';
import { analyticsEnabled, browserRejectsAnalytics, setAnalyticsEnabled } from './analytics';

const text = {
  ko: { notice: '이 웹사이트는 PostHog로 방문과 설치 버튼 이용을 분석합니다. 입력 내용과 화면은 수집하지 않습니다.', off: '방문 통계 끄기', on: '방문 통계 켜기', blocked: '브라우저 설정으로 통계 꺼짐' },
  en: { notice: 'This website uses PostHog to measure visits and install actions. Typed content and screen recordings are never collected.', off: 'Turn analytics off', on: 'Turn analytics on', blocked: 'Analytics disabled by your browser' },
  ja: { notice: 'このサイトではPostHogで訪問とインストール操作を分析します。入力内容や画面録画は収集しません。', off: 'アクセス解析をオフ', on: 'アクセス解析をオン', blocked: 'ブラウザの設定で解析はオフです' },
  'zh-Hans': { notice: '本网站使用PostHog分析访问和安装操作，不收集输入内容或录制屏幕。', off: '关闭访问统计', on: '开启访问统计', blocked: '浏览器设置已关闭统计' },
  'zh-Hant': { notice: '本網站使用PostHog分析造訪和安裝操作，不收集輸入內容或錄製畫面。', off: '關閉造訪統計', on: '開啟造訪統計', blocked: '瀏覽器設定已關閉統計' },
};

export default function AnalyticsNotice({ locale }: { locale: Locale }) {
  const t = text[locale];
  const [enabled, setEnabled] = useState(true);
  const [blocked, setBlocked] = useState(false);
  useEffect(() => { setEnabled(analyticsEnabled()); setBlocked(browserRejectsAnalytics()); }, []);
  function toggle() {
    setAnalyticsEnabled(!enabled);
    setEnabled(analyticsEnabled());
  }
  return <aside className="analytics-notice section"><p>{t.notice}</p><button type="button" onClick={toggle} disabled={blocked} aria-pressed={enabled}>{blocked ? t.blocked : enabled ? t.off : t.on}</button></aside>;
}
