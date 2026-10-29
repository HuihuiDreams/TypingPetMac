import assert from 'node:assert/strict';
import test from 'node:test';
import { formatHeroRelease, formatReleaseDate } from '../src/release-time.ts';

function inTimeZone(zone, action) {
  const previous = process.env.TZ;
  process.env.TZ = zone;
  try { action(); }
  finally {
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
}

const publication = '2026-10-25T22:31:24Z';

test('a just-published release uses the real instant in every timezone', () => {
  for (const zone of ['Asia/Seoul', 'UTC', 'America/Los_Angeles']) {
    inTimeZone(zone, () => {
      const now = Date.parse('2026-10-25T22:36:00Z');
      assert.equal(formatReleaseDate('2026-10-26', 'ko', publication, now), '방금 (1시간 이내)');
      assert.equal(formatReleaseDate('2026-10-26', 'ko', '2026-10-26T07:31:24+09:00', now), '방금 (1시간 이내)');
      assert.equal(formatReleaseDate('2026-10-26', 'ko', publication, now + 2 * 3_600_000), '2시간 전');
    });
  }
});

test('date-only history never invents an hour of publication', () => {
  for (const zone of ['Asia/Seoul', 'UTC', 'America/Los_Angeles']) {
    inTimeZone(zone, () => {
      const now = new Date(2026, 9, 26, 7, 33).getTime();
      assert.equal(formatReleaseDate('2026-10-26', 'ko', undefined, now), '오늘');
      assert.equal(formatReleaseDate('2026-10-25', 'ko', undefined, now), '1일 전');
      assert.equal(formatReleaseDate('2026-10-26', 'ko', '2026-10-26T00:00:00', now), '오늘');
    });
  }
});

test('the hero uses the local publication day across the UTC/Korean date boundary', () => {
  inTimeZone('Asia/Seoul', () => {
    const now = Date.parse('2026-10-25T22:36:00Z');
    assert.equal(formatHeroRelease('2026-10-25', '0.19.0', 'ko', '오늘 업데이트', publication, now), '오늘 업데이트');
  });
});

test('calendar-day fallback handles daylight saving, old releases, and missing data', () => {
  inTimeZone('America/Los_Angeles', () => {
    const now = new Date(2026, 2, 9, 0, 30).getTime();
    assert.equal(formatReleaseDate('2026-03-08', 'ko', undefined, now), '1일 전');
    assert.equal(formatReleaseDate('2026-01-01', 'ko', undefined, now), '2026-01-01');
    assert.equal(formatReleaseDate('bad-date', 'ko', 'bad-time', now), 'bad-date');
    assert.equal(formatReleaseDate('2026-02-31', 'ko', undefined, now), '2026-02-31');
    assert.equal(formatHeroRelease('bad-date', '0.19.0', 'ko', '오늘 업데이트', undefined, now), 'v0.19.0');
  });
});

test('other note languages keep their existing calendar date display', () => {
  for (const locale of ['en', 'ja', 'zh-Hans', 'zh-Hant']) {
    assert.equal(formatReleaseDate('2026-10-26', locale, publication, Date.parse(publication)), '2026-10-26');
  }
});
