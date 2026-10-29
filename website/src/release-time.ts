import type { Locale } from './localization';

const dayMilliseconds = 86_400_000;

function publishedDate(value?: string): Date | undefined {
  if (!value || !/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) return undefined;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : undefined;
}

function calendarDate(value: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return undefined;
  const [year, month, day] = match.slice(1).map(Number);
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day ? date : undefined;
}

function daysSince(date: Date, now: number): number {
  const today = new Date(now);
  const ordinal = (value: Date) => Date.UTC(value.getFullYear(), value.getMonth(), value.getDate());
  return Math.max(0, Math.round((ordinal(today) - ordinal(date)) / dayMilliseconds));
}

export function formatReleaseDate(date: string, locale: Locale, publishedAt?: string, now = Date.now()): string {
  if (locale !== 'ko') return date;
  const published = publishedDate(publishedAt);
  let daysAgo: number;
  if (published) {
    const hoursAgo = Math.max(0, Math.floor((now - published.getTime()) / 3_600_000));
    if (hoursAgo < 1) return '방금 (1시간 이내)';
    if (hoursAgo < 24) return `${hoursAgo}시간 전`;
    daysAgo = Math.floor(hoursAgo / 24);
  } else {
    // 仅有日历日期信息不足以精确推算具体小时或分钟。
    const calendar = calendarDate(date);
    if (!calendar) return date;
    daysAgo = daysSince(calendar, now);
    if (daysAgo === 0) return '오늘';
  }
  if (daysAgo > 28) return date;
  if (daysAgo < 7) return `${daysAgo}일 전`;
  return `${Math.floor(daysAgo / 7)}주 전`;
}

export function formatHeroRelease(date: string, version: string, locale: Locale, updatedToday: string, publishedAt?: string, now = Date.now()): string {
  const published = publishedDate(publishedAt) ?? calendarDate(date);
  if (!published) return `v${version}`;
  const daysAgo = daysSince(published, now);
  if (daysAgo > 28) return `v${version}`;
  if (daysAgo === 0) return updatedToday;
  const relativeTime = new Intl.RelativeTimeFormat(locale, { numeric: 'always' });
  if (daysAgo < 7) return relativeTime.format(-daysAgo, 'day');
  return relativeTime.format(-Math.floor(daysAgo / 7), 'week');
}
