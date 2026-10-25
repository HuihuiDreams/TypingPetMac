import type { CaptureResult } from 'posthog-js/dist/module.no-external.js';

const events = new Set(['$pageview', 'download_clicked', 'homebrew_copied', 'language_changed']);
const properties = new Set([
  'token', 'distinct_id', '$device_id', '$session_id', '$window_id', '$lib', '$lib_version',
  '$browser', '$browser_version', '$os', '$os_version', '$device_type',
  '$screen_width', '$screen_height', '$viewport_width', '$viewport_height',
  '$host', '$pathname', '$current_url', '$referrer', '$referring_domain',
  '$process_person_profile', '$is_identified', '$pageview_id', 'title',
  'locale', 'page', 'app_version', 'source', 'placement', 'format', 'command', 'to_locale',
]);

// Only deliberate site events and these properties may leave the browser.
export function sanitizeCapture(event: CaptureResult): CaptureResult | null {
  if (!events.has(event.event)) return null;
  const clean = Object.fromEntries(Object.entries(event.properties).filter(([key]) => properties.has(key)));
  for (const key of ['$current_url', '$referrer']) {
    if (typeof clean[key] !== 'string') continue;
    try {
      const url = new URL(clean[key]);
      clean[key] = key === '$referrer' ? url.origin : url.origin + url.pathname;
    } catch { delete clean[key]; }
  }
  // Never forward person updates, even if a future SDK default adds them.
  const { $set, $set_once, $unset, ...rest } = event;
  return { ...rest, properties: clean };
}
