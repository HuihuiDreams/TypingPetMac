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

export default function Newsletter({ locale, view = 'subscribe' }: { locale: Locale; view?: 'subscribe' | 'unsubscribe' }) {
  const t = newsletterContent[locale];
  const id = useId();
  const mode = view;
  const [language, setLanguage] = useState<Locale>(locale);
  const [status, setStatus] = useState<'idle' | 'sending' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');
  const [resetKey, setResetKey] = useState(0);
  const resultRef = useRef<HTMLDivElement>(null);
  const sending = status === 'sending';
  useEffect(() => {
    if (status === 'success' || status === 'error') resultRef.current?.focus();
  }, [status]);

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
          consent: data.get('consent') === 'on',
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
    <div className="newsletter-copy">
      <h2 id={`${id}-heading`}>{mode === 'subscribe' ? t.title : t.unsubscribeTitle}</h2>
      <p>{mode === 'subscribe' ? t.description : t.unsubscribeBody}</p>
      {mode === 'subscribe' && <span className="newsletter-note"><Mail size={17} aria-hidden="true" />{t.note}</span>}
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
          <Disclosure className="newsletter-privacy" label={t.privacy}>
            {locale === 'ko' ? <>
              <p>{t.purpose}</p>
              <h4>수집 항목</h4>
              <p>이메일 주소, 선택한 이름 또는 닉네임, 수신 언어를 수집합니다.</p>
              <p>또한 신청 및 동의 시각과 동의 문구의 버전을 기록합니다. 중복 신청과 남용을 방지하기 위해 키 기반 해시도 보관합니다.</p>
              <h4>보관 기간</h4>
              <ul>
                <li>확인 대기 중인 신청: 7일</li>
                <li>승인된 구독 정보: 구독 해지 시까지</li>
                <li>해지 후 이메일 주소: 구독 그룹 정리를 위해 최대 30일</li>
                <li>해지 후 키 기반 해시: 재등록 방지를 위해 최대 180일</li>
              </ul>
              <p>구독을 해지하면 즉시 뉴스레터 발송 대상에서 제외하며, 닉네임은 해지 시 삭제합니다.</p>
              <h4>동의 거부 및 문의</h4>
              <p>동의하지 않아도 앱을 다운로드하거나 이용하는 데 제한이 없습니다. 다만, 뉴스레터를 구독하려면 위 항목에 동의해야 합니다.</p>
              <p>문의: <a href="mailto:support@miel.ing">support@miel.ing</a></p>
            </> : <><p>{t.purpose}</p><p>{t.items}</p><p>{t.retention}</p><p>{t.rights} <a href="mailto:support@miel.ing">support@miel.ing</a></p></>}
          </Disclosure>
          <Field.Root name="consent" disabled={sending} className="newsletter-consent-field">
            <Field.Label className="newsletter-consent"><Checkbox.Root className="ui-checkbox" required value="on"><Checkbox.Indicator><Check size={14} aria-hidden="true" /></Checkbox.Indicator></Checkbox.Root><span>{t.collect}</span></Field.Label>
            <Field.Error className="field-error">{t.consentRequired}</Field.Error>
          </Field.Root>
        </>}
        <div className="newsletter-honey" aria-hidden="true"><label htmlFor={`${id}-website`}>{t.honeypot}</label><input id={`${id}-website`} name="website" tabIndex={-1} autoComplete="off" /></div>
        <Button type="submit" className="button primary newsletter-submit" disabled={sending}>
          {status === 'success' ? <Check size={18} aria-hidden="true" /> : <Mail size={18} aria-hidden="true" />}
          {status === 'sending' ? t.sending : mode === 'subscribe' ? t.subscribe : t.unsubscribe}<ArrowRight size={18} aria-hidden="true" />
        </Button>
      </Form>
      <div ref={resultRef} tabIndex={-1} className={`newsletter-result ${status}`} role={status === 'error' ? 'alert' : 'status'}>{message}</div>
      <noscript><p>{t.failed} <a href="mailto:support@miel.ing">support@miel.ing</a></p></noscript>
    </div>
  </section>;
}
