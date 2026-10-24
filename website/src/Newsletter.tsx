import { useEffect, useId, useState, type FormEvent } from 'react';
import { ArrowRight, Check, Mail } from 'lucide-react';
import { localeMetadata, locales, type Locale } from './localization';
import { consentVersion, newsletterContent } from './newsletter-content';
import './newsletter.css';

export default function Newsletter({ locale }: { locale: Locale }) {
  const t = newsletterContent[locale];
  const id = useId();
  const [mode, setMode] = useState<'subscribe' | 'unsubscribe'>('subscribe');
  const [language, setLanguage] = useState<Locale>(locale);
  const [status, setStatus] = useState<'idle' | 'sending' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');
  useEffect(() => {
    if (new URLSearchParams(location.search).get('newsletter') === 'unsubscribe') setMode('unsubscribe');
  }, []);

  function changeMode(next: typeof mode) {
    setMode(next); setStatus('idle'); setMessage('');
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (status === 'sending') return;
    const form = event.currentTarget;
    const data = new FormData(form);
    setStatus('sending'); setMessage('');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(`/api/newsletter/${mode}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'omit',
        signal: controller.signal,
        body: JSON.stringify({ email: data.get('email'), nickname: data.get('nickname') || '', locale: language,
          consent: data.get('collect') === 'on' && data.get('receive') === 'on',
          consent_version: consentVersion, website: data.get('website') || '' }),
      });
      const result = await response.json();
      if (!response.ok || result.ok !== true) {
        throw new Error(response.status === 429 ? t.limit : response.status === 400 ? t.invalid : t.failed);
      }
      setStatus('success'); setMessage(mode === 'subscribe' ? t.subscribed : t.unsubscribed);
      form.reset();
    } catch (error) {
      setStatus('error');
      setMessage(error instanceof Error && [t.limit, t.invalid, t.failed].includes(error.message) ? error.message : t.failed);
    } finally { clearTimeout(timeout); }
  }

  return <section id="newsletter" className="section newsletter-section ph-no-capture ph-no-autocapture ph-no-record" data-ph-no-autocapture aria-labelledby={`${id}-heading`}>
    <div className="newsletter-copy"><span className="eyebrow">{t.eyebrow}</span>
      <h2 id={`${id}-heading`}>{mode === 'subscribe' ? t.title : t.unsubscribeTitle}</h2>
      <p>{mode === 'subscribe' ? t.description : t.unsubscribeBody}</p>
      <span className="newsletter-note"><Mail size={17} aria-hidden="true" />{t.note}</span>
    </div>
    <div className="newsletter-card panel">
      <form method="post" action={`/api/newsletter/${mode}`} onSubmit={submit} aria-busy={status === 'sending'}>
        <label htmlFor={`${id}-email`}>{t.email}</label>
        <input id={`${id}-email`} name="email" type="email" autoComplete="email" placeholder="you@example.com" required maxLength={254} disabled={status === 'sending'} />
        {mode === 'subscribe' && <>
          <div className="newsletter-fields"><div>
            <label htmlFor={`${id}-nickname`}>{t.nickname} <span>({t.optional})</span></label>
            <input id={`${id}-nickname`} name="nickname" type="text" autoComplete="nickname" maxLength={80} aria-describedby={`${id}-optional`} disabled={status === 'sending'} />
            <small id={`${id}-optional`}>{t.nicknameHint}</small>
          </div><div>
            <label htmlFor={`${id}-language`}>{t.language}</label>
            <select id={`${id}-language`} name="locale" value={language} onChange={e => setLanguage(e.target.value as Locale)} disabled={status === 'sending'}>
              {locales.map(item => <option key={item} value={item} lang={item}>{localeMetadata[item].label}</option>)}
            </select>
          </div></div>
          <details className="newsletter-privacy"><summary>{t.privacy}</summary><div><p>{t.purpose}</p><p>{t.items}</p><p>{t.retention}</p><p>{t.rights}</p></div></details>
          <label className="newsletter-consent"><input type="checkbox" name="collect" required disabled={status === 'sending'} /><span>{t.collect}</span></label>
          <label className="newsletter-consent"><input type="checkbox" name="receive" required disabled={status === 'sending'} /><span>{t.receive}</span></label>
        </>}
        <div className="newsletter-honey" aria-hidden="true"><label htmlFor={`${id}-website`}>{t.honeypot}</label><input id={`${id}-website`} name="website" tabIndex={-1} autoComplete="off" /></div>
        <button type="submit" className="button primary newsletter-submit" disabled={status === 'sending'}>
          {status === 'success' ? <Check size={18} aria-hidden="true" /> : <Mail size={18} aria-hidden="true" />}
          {status === 'sending' ? t.sending : mode === 'subscribe' ? t.subscribe : t.unsubscribe}<ArrowRight size={18} aria-hidden="true" />
        </button>
        <div className={`newsletter-result ${status}`} role={status === 'error' ? 'alert' : 'status'} aria-live="polite">{message}</div>
        {mode === 'subscribe' && <p className="newsletter-pending">{t.pending}</p>}
      </form>
      <div className="newsletter-mode"><button type="button" className="text-link" disabled={status === 'sending'} onClick={() => changeMode(mode === 'subscribe' ? 'unsubscribe' : 'subscribe')}>{mode === 'subscribe' ? t.unsubscribe : t.subscribe}<ArrowRight size={14} aria-hidden="true" /></button></div>
      <noscript><p>{t.failed} <a href="mailto:support@miel.ing">support@miel.ing</a></p></noscript>
    </div>
  </section>;
}
