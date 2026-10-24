import type { PostHog } from 'posthog-js/dist/module.no-external.js';
import { sanitizeCapture } from './analytics-policy';
import release from './generated/release.json';

const preference = 'typingpet-site-analytics';
let client: PostHog | undefined;
let initializing: Promise<void> | undefined;
const pendingEvents: SiteEvent[] = [];

export function browserRejectsAnalytics() {
  if (typeof navigator === 'undefined') return false;
  return navigator.doNotTrack === '1' || navigator.doNotTrack === 'yes'
    || (navigator as Navigator & { globalPrivacyControl?: boolean }).globalPrivacyControl === true;
}

export function analyticsEnabled() {
  if (typeof window === 'undefined' || browserRejectsAnalytics()) return false;
  try { return localStorage.getItem(preference) !== 'off'; } catch { return true; }
}

function pageProperties() {
  return {
    locale: location.pathname.split('/')[1],
    page: location.pathname.includes('/changelog/') ? 'changelog' : 'home',
    app_version: release.version,
  };
}

export async function initWebsiteAnalytics() {
  if (client || location.hostname !== 'typing-pet.miel.ing' || !analyticsEnabled()) return;
  if (initializing) return initializing;
  initializing = loadClient();
  try { await initializing; } finally { initializing = undefined; }
}

async function loadClient() {
  const { default: posthog } = await import('posthog-js/dist/module.no-external.js');
  if (!analyticsEnabled()) return;
  posthog.init('phc_Ess4H9LyqTbFexI9Qj6ifgV4ZniFWIiAIIczMoSZyva', {
    api_host: location.origin + '/relay',
    ui_host: 'https://us.posthog.com',
    defaults: '2026-08-30',
    persistence: 'localStorage',
    persistence_name: 'typingpet-site',
    cross_subdomain_cookie: false,
    person_profiles: 'never',
    autocapture: false,
    capture_pageview: false,
    capture_pageleave: false,
    capture_dead_clicks: false,
    rageclick: false,
    capture_performance: false,
    disable_session_recording: true,
    disable_surveys: true,
    disable_external_dependency_loading: true,
    advanced_disable_flags: true,
    remote_config_refresh_interval_ms: 0,
    save_campaign_params: false,
    save_referrer: false,
    respect_dnt: true,
    before_send: event => analyticsEnabled() ? sanitizeCapture(event) : null,
  });
  client = posthog;
  posthog.opt_in_capturing({ captureEventName: false });
  capturePageview();
  for (const event of pendingEvents.splice(0)) trackSiteEvent(event);
}

function capturePageview() {
  if (client && analyticsEnabled()) client.capture('$pageview', pageProperties());
}

type SiteEvent =
  | { event: 'download_clicked'; source: 'github' | 'direct'; placement: 'hero' | 'install' }
  | { event: 'homebrew_copied'; command: 'install' | 'update' }
  | { event: 'language_changed'; to_locale: string };

export function trackSiteEvent(data: SiteEvent) {
  if (!analyticsEnabled()) return;
  if (!client) {
    if (initializing && pendingEvents.length < 20) pendingEvents.push(data);
    return;
  }
  const { event, ...properties } = data;
  // Immediate fetch uses keepalive across navigation and keeps retries on server errors.
  try { client.capture(event, { ...pageProperties(), ...properties }, { send_instantly: true }); } catch {}
}

export function setAnalyticsEnabled(enabled: boolean) {
  try { localStorage.setItem(preference, enabled ? 'on' : 'off'); } catch {}
  if (!enabled) {
    pendingEvents.length = 0;
    if (client) client.opt_out_capturing();
    return;
  }
  if (browserRejectsAnalytics()) return;
  if (client) {
    client.opt_in_capturing({ captureEventName: false });
    capturePageview();
  } else void initWebsiteAnalytics().catch(() => {});
}
