import { useEffect, useId, useRef, useState, type FormEvent } from 'react';
import { Button } from '@base-ui/react/button';
import { Checkbox } from '@base-ui/react/checkbox';
import { Field } from '@base-ui/react/field';
import { Form } from '@base-ui/react/form';
import { Input } from '@base-ui/react/input';
import { Select } from '@base-ui/react/select';
import { ArrowRight, Check, ChevronDown, Mail } from 'lucide-react';
import { localeMetadata, locales, type Locale } from './localization';
import { consentVersion, newsletterContent } from './newsletter-content';
import Disclosure from './Disclosure';
import './newsletter.css';

export default function Newsletter({ locale }: { locale: Locale }) {
  const t = newsletterContent[locale];
  const id = useId();
  const [mode, setMode] = useState<'subscribe' | 'unsubscribe'>('subscribe');
  const [language, setLanguage] = useState<Locale>(locale);
  const [status, setStatus] = useState<'idle' | 'sending' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');
  const [resetKey, setResetKey] = useState(0);
  const resultRef = useRef<HTMLDivElement>(null);
  const sending = status === 'sending';
  useEffect(() => {
    if (new URLSearchParams(location.search).get('newsletter') === 'unsubscribe') setMode('unsubscribe');
  }, []);
  useEffect(() => {
    if (status === 'success' || status === 'error') resultRef.current?.focus();
  }, [status]);

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
      // Remount the form to reset native inputs, Base UI controls, and validation together.
      setResetKey(key => key + 1);
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
      <Form key={resetKey} method="post" action={`/api/newsletter/${mode}`} onSubmit={submit} aria-busy={sending}>
        <Field.Root name="email" disabled={sending} className="newsletter-field">
          <Field.Label>{t.email}</Field.Label>
          <Input type="email" autoComplete="email" placeholder="you@example.com" required maxLength={254} />
          <Field.Error className="field-error">{t.emailInvalid}</Field.Error>
        </Field.Root>
        {mode === 'subscribe' && <>
          <div className="newsletter-fields">
            <Field.Root name="nickname" disabled={sending} className="newsletter-field">
              <Field.Label>{t.nickname} <span>({t.optional})</span></Field.Label>
              <Input type="text" autoComplete="nickname" maxLength={80} />
              <Field.Description className="newsletter-hint">{t.nicknameHint}</Field.Description>
              <Field.Error className="field-error">{t.invalid}</Field.Error>
            </Field.Root>
            <Field.Root name="locale" disabled={sending} className="newsletter-field">
              <Select.Root value={language} onValueChange={value => { if (value) setLanguage(value); }}
                items={locales.map(value => ({ value, label: localeMetadata[value].label }))}>
                <Select.Label className="newsletter-label">{t.language}</Select.Label>
                <Select.Trigger className="ui-select-trigger"><Select.Value /><Select.Icon><ChevronDown size={17} aria-hidden="true" /></Select.Icon></Select.Trigger>
                <Select.Portal>
                  <Select.Positioner className="ui-positioner" sideOffset={6} alignItemWithTrigger={false} collisionPadding={12}>
                    <Select.Popup className="ui-popup ui-select-popup">
                      <Select.List className="ui-select-list">
                        {locales.map(item => <Select.Item className="ui-item" key={item} value={item} lang={item}>
                          <Select.ItemText>{localeMetadata[item].label}</Select.ItemText>
                          <Select.ItemIndicator className="ui-indicator"><Check size={16} aria-hidden="true" /></Select.ItemIndicator>
                        </Select.Item>)}
                      </Select.List>
                    </Select.Popup>
                  </Select.Positioner>
                </Select.Portal>
              </Select.Root>
            </Field.Root>
          </div>
          <Disclosure className="newsletter-privacy" label={t.privacy}><p>{t.purpose}</p><p>{t.items}</p><p>{t.retention}</p><p>{t.rights}</p></Disclosure>
          {(['collect', 'receive'] as const).map(name => <Field.Root name={name} key={name} disabled={sending} className="newsletter-consent-field">
            <Field.Label className="newsletter-consent"><Checkbox.Root className="ui-checkbox" required value="on"><Checkbox.Indicator><Check size={14} aria-hidden="true" /></Checkbox.Indicator></Checkbox.Root><span>{t[name]}</span></Field.Label>
            <Field.Error className="field-error">{t.consentRequired}</Field.Error>
          </Field.Root>)}
        </>}
        <div className="newsletter-honey" aria-hidden="true"><label htmlFor={`${id}-website`}>{t.honeypot}</label><input id={`${id}-website`} name="website" tabIndex={-1} autoComplete="off" /></div>
        <Button type="submit" className="button primary newsletter-submit" disabled={sending}>
          {status === 'success' ? <Check size={18} aria-hidden="true" /> : <Mail size={18} aria-hidden="true" />}
          {status === 'sending' ? t.sending : mode === 'subscribe' ? t.subscribe : t.unsubscribe}<ArrowRight size={18} aria-hidden="true" />
        </Button>
        {mode === 'subscribe' && <p className="newsletter-pending">{t.pending}</p>}
      </Form>
      <div ref={resultRef} tabIndex={-1} className={`newsletter-result ${status}`} role={status === 'error' ? 'alert' : 'status'}>{message}</div>
      <div className="newsletter-mode"><Button type="button" className="text-link" disabled={sending} onClick={() => changeMode(mode === 'subscribe' ? 'unsubscribe' : 'subscribe')}>{mode === 'subscribe' ? t.unsubscribe : t.subscribe}<ArrowRight size={14} aria-hidden="true" /></Button></div>
      <noscript><p>{t.failed} <a href="mailto:support@miel.ing">support@miel.ing</a></p></noscript>
    </div>
  </section>;
}
