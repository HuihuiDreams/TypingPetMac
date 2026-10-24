import { useEffect, useRef, useState } from 'react';
import { Tabs } from '@base-ui/react/tabs';
import { Accordion } from '@base-ui/react/accordion';
import { Button } from '@base-ui/react/button';
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUpRight, Check, ChevronDown, Copy, Image, Keyboard, ListTodo, Mail, MousePointer2, PawPrint, Plus, ShieldCheck, Sparkles, Terminal, Timer } from 'lucide-react';
import { content, type Locale } from './content';
import { locales, localeMetadata } from './localization';
import release from './generated/release.json';
import history from './releases.json';

const repo = 'https://github.com/ynifamily3/TypingPetMac';
const brew = 'brew tap ynifamily3/tap\nbrew install --cask ynifamily3/tap/typing-pet';
const upgrade = 'brew update\nbrew upgrade --cask --greedy ynifamily3/tap/typing-pet';
const compareVersion = (a: string, b: string) => {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
};
const publishedNotes = history.filter(n => compareVersion(n.version, release.version) <= 0).sort((a, b) => compareVersion(b.version, a.version));
const iconProps = { size: 20, strokeWidth: 2 };
function Github({ size = 20 }: { size?: number; strokeWidth?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 6v-3.9a3.4 3.4 0 0 0-1-2.7c3.3-.4 6.7-1.6 6.7-7.3a5.7 5.7 0 0 0-1.5-4c.2-.4.7-1.9-.1-3.9 0 0-1.3-.4-4.1 1.5a14.4 14.4 0 0 0-7.4 0C4.8-.2 3.5.2 3.5.2c-.8 2-.3 3.5-.1 3.9a5.7 5.7 0 0 0-1.5 4c0 5.7 3.4 6.9 6.7 7.3a3.4 3.4 0 0 0-1 2.7V22" transform="translate(1 1) scale(.91)" /></svg>;
}

function CodeBlock({ code, locale }: { code: string; locale: Locale }) {
  const t = content[locale];
  const [status, setStatus] = useState('');
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  async function copy() {
    try { await navigator.clipboard.writeText(code); setStatus(t.copied); }
    catch { setStatus(t.copyError); }
    clearTimeout(timer.current); timer.current = setTimeout(() => setStatus(''), 3000);
  }
  return <div className="code-box"><div className="code-toolbar"><span><Terminal size={16} /> {t.terminal}</span><Button className="copy-button" onClick={copy} aria-label={t.copy}>{status === t.copied ? <Check size={16} /> : <Copy size={16} />}<span>{status === t.copied ? t.copied : t.copy}</span></Button></div><pre><code>{code}</code></pre><span className="sr-only" role="status">{status}</span></div>;
}

function PetDemo({ locale }: { locale: Locale }) {
  const t = content[locale];
  const [pose, setPose] = useState('idle');
  const [tick, setTick] = useState(0);
  const count = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  function react() {
    count.current += 1; setPose(count.current % 2 ? 'left' : 'right'); setTick(count.current);
    clearTimeout(timer.current); timer.current = setTimeout(() => setPose('idle'), 750);
  }
  return <div className="demo-wrap"><span className="sticker sticker-lime">100% YOUR VIBE <Sparkles size={17} /></span><div className="demo-window"><div className="window-bar"><div className="window-dots" aria-hidden="true"><i /><i /><i /></div><span>{t.demoTitle}</span><PawPrint size={16} /></div><div className="desktop-scene"><div className="demo-note"><span className="check-circle" /><span>{t.demoTask}</span><span className="timer-text">19:52</span></div><div className="demo-speech">{t.demoBubble}<Sparkles size={17} /></div><Button className="pet-button" onClick={react} aria-label={t.demoKey}><img key={tick} className={pose !== 'idle' ? 'pet-image reacting' : 'pet-image'} src={`/assets/pet-${pose}.webp`} width="480" height="480" alt="" fetchPriority="high" /></Button><div className="desk-line" /><span className="keycap keycap-left" aria-hidden="true">⌘</span><span className="keycap keycap-right" aria-hidden="true">↵</span></div><div className="demo-input-wrap"><span>{t.demoHint}</span><div className="demo-input"><Keyboard size={19} /><input aria-label={t.demoLabel} placeholder={t.demoPlaceholder} autoComplete="off" spellCheck={false} onKeyDown={e => { if (!e.metaKey && !e.ctrlKey && !e.altKey && e.key.length === 1) react(); }} onChange={e => { e.target.value = ''; }} /></div></div></div><p className="demo-caption"><ShieldCheck size={14} />{t.demoCaption}</p></div>;
}

function Install({ locale }: { locale: Locale }) {
  const t = content[locale];
  const [tab, setTab] = useState('zip');
  useEffect(() => {
    const select = () => { if (location.hash === '#homebrew') setTab('brew'); };
    select(); window.addEventListener('hashchange', select);
    return () => window.removeEventListener('hashchange', select);
  }, []);
  return <section id="install" className="section install-section"><div className="section-head"><span className="eyebrow">{t.installLabel}</span><h2>{t.installTitle}</h2><p>{t.installBody}</p></div><div id="homebrew" className="install-card panel"><Tabs.Root value={tab} onValueChange={value => setTab(String(value))}><Tabs.List className="install-tabs" aria-label={t.installMethod}><Tabs.Tab className="install-tab" value="zip"><ArrowDown {...iconProps} />{t.zipTab}</Tabs.Tab><Tabs.Tab className="install-tab" value="brew"><Terminal {...iconProps} />{t.brewTab}</Tabs.Tab></Tabs.List><Tabs.Panel className="install-panel" value="zip"><div className="install-heading"><h3>{t.zipTitle}</h3><span className="tag">v{release.version} · {(release.size / 1e6).toFixed(1)} MB</span></div><ol className="steps">{t.zipSteps.map((step, i) => <li key={step}><span>{String(i + 1).padStart(2, '0')}</span>{step}</li>)}</ol><div className="download-actions"><a className="button primary" href={release.githubUrl}><Github {...iconProps} />{t.githubDownload}<span className="small-label">{t.recommended}</span></a><a className="text-link" href="https://pet.miel.ing/download/latest">{t.directDownload}<ArrowDown size={17} /></a></div><div className="minor-links"><a href={release.checksumUrl}>{t.checksum}<ArrowUpRight size={14} /></a><a href={release.releaseUrl}>{t.releasePage}<ArrowUpRight size={14} /></a></div></Tabs.Panel><Tabs.Panel className="install-panel" value="brew"><h3>{t.brewTitle}</h3><p>{t.brewBody} <a href="https://brew.sh/" target="_blank" rel="noreferrer">Homebrew <ArrowUpRight size={14} /></a></p><CodeBlock code={brew} locale={locale} /><p className="brew-after">{t.brewAfter}</p><details className="brew-update"><summary>{t.brewUpdate}</summary><CodeBlock code={upgrade} locale={locale} /></details></Tabs.Panel></Tabs.Root><div className="permission-note"><ShieldCheck size={23} /><p>{t.permission}</p></div></div></section>;
}

function Note({ note, locale }: { note: typeof history[number]; locale: Locale }) {
  const t = content[locale];
  return <article className="release-card panel"><div className="release-meta"><span className="version-label">v{note.version}</span><time dateTime={note.date}>{note.date.replaceAll('-', '.')}</time>{note.version === release.version && <span className="tag yellow">{t.latest}</span>}</div><h3>{note[locale].title}</h3><ul>{note[locale].items.map(item => <li key={item}>{item}</li>)}</ul><a className="text-link" href={`${repo}/releases/tag/v${note.version}`}>{t.releasePage}<ArrowUpRight size={16} /></a></article>;
}

export default function App({ locale = 'ko', page = 'home' }: { locale?: Locale; page?: 'home' | 'changelog' }) {
  const t = content[locale];
  const home = `/${locale}/`;
  const featureIcons = [Keyboard, Image, Timer, MousePointer2];
  const navIds = ['features', 'install', 'notes'];
  function saveLanguage(language: Locale, event: { currentTarget: HTMLAnchorElement }) {
    event.currentTarget.href = `/${language}/${page === 'changelog' ? 'changelog/' : ''}` + window.location.search + window.location.hash;
    try { localStorage.setItem('typingpet-language', language); } catch {}
  }
  return <><a className="skip-link" href="#main">{t.skip}</a><header className="site-header"><div className="header-inner"><a className="brand" href={home} aria-label={t.homeLabel}><span className="brand-icon"><PawPrint size={22} fill="currentColor" /></span><span>typing pet<span className="brand-dot">.</span></span><span className="brand-platform">for Mac</span></a><nav aria-label={t.menuLabel}>{t.nav.map((name, i) => <a key={name} href={page === 'home' ? `#${navIds[i]}` : `${home}#${navIds[i]}`}>{name}</a>)}</nav><details className="language-menu"><summary className="language-switch" aria-label={t.languageLabel}>{localeMetadata[locale].label}<ChevronDown size={14} /></summary><div className="language-options">{locales.map(language => <a key={language} href={`/${language}/${page === 'changelog' ? 'changelog/' : ''}`} hrefLang={language} lang={language} aria-label={localeMetadata[language].label} aria-current={locale === language ? 'page' : undefined} onClick={event => saveLanguage(language, event)}>{localeMetadata[language].label}{locale === language && <Check size={14} />}</a>)}</div></details></div></header><main id="main">{page === 'home' ? <><section className="hero section"><div className="hero-copy"><div className="hero-label"><span className="status-dot" />{t.heroLabel}</div><h1><span>{t.hero1}</span><br />{t.hero2}<br /><span className="highlight">{t.hero3}</span></h1><p className="hero-description">{t.heroBody}</p><div className="hero-actions"><a className="button primary" href={release.githubUrl}><Github {...iconProps} />{t.githubDownload}<ArrowDown size={18} /></a><a className="brew-link" href="#homebrew"><Terminal size={17} />{t.installBrew}<ArrowUpRight size={16} /></a></div><div className="hero-meta"><span>v{release.version}{release.prerelease ? ` ${t.prerelease}` : ''}</span><span>{t.requirements}</span></div><p className="signed-note"><ShieldCheck size={15} />{t.signed}</p></div><PetDemo locale={locale} /></section><div className="benefit-strip"><div>{t.strip.map((text, i) => <span key={text}>{i === 0 ? <PawPrint size={19} /> : i === 1 ? <Sparkles size={19} /> : <Keyboard size={19} />}{text}</span>)}</div></div><section id="features" className="section features-section"><div className="section-head"><span className="eyebrow">{t.featureLabel}</span><h2>{t.featureTitle}</h2><p>{t.featureBody}</p></div><div className="feature-grid">{t.features.map(([title, description], i) => { const Icon = featureIcons[i]; return <article className={`feature-card feature-${i + 1}`} key={title}><div className="feature-top"><span className="feature-number">0{i + 1}</span><Icon size={28} strokeWidth={1.8} /></div><h3>{title}</h3><p>{description}</p></article>; })}</div></section><section className="section focus-section"><div className="focus-copy"><span className="eyebrow">{t.focusLabel}</span><h2>{t.focusTitle}</h2><p>{t.focusBody}</p><div className="focus-tags">{t.focusTags.map(tag => <span className="tag" key={tag}><Check size={14} />{tag}</span>)}</div></div><div className="focus-visual panel"><div className="focus-visual-label"><ListTodo size={18} />LESS NOISE. MORE FOCUS.</div><img src="/assets/todo-active.webp" width="720" height="220" alt={t.screenshotAlt} loading="lazy" /><div className="focus-bottom"><span className="focus-mini-pet"><img src="/assets/pet-idle.webp" width="90" height="90" alt="" loading="lazy" /></span><span>{t.screenshotCaption}</span><Timer size={22} /></div></div></section><Install locale={locale} /><section className="section faq-section"><h2>{t.faqTitle}</h2><Accordion.Root className="faq" multiple>{t.faqs.map(([question, answer], i) => <Accordion.Item key={question} value={i} className="faq-item"><Accordion.Header><Accordion.Trigger className="faq-trigger">{question}<Plus size={21} /></Accordion.Trigger></Accordion.Header><Accordion.Panel className="faq-panel"><p>{answer}</p></Accordion.Panel></Accordion.Item>)}</Accordion.Root></section><section id="notes" className="section notes-section"><div className="section-head notes-head"><div><span className="eyebrow">{t.notesLabel}</span><h2>{t.notesTitle}</h2><p>{t.notesBody}</p></div><a className="button secondary" href={`${home}changelog/`}>{t.allNotes}<ArrowRight size={18} /></a></div><Note note={publishedNotes[0]} locale={locale} /></section></> : <section className="section changelog-page"><a className="text-link back-link" href={home}><ArrowLeft size={17} />{t.back}</a><span className="eyebrow">THE CHANGELOG</span><h1>{t.notesPageTitle}</h1><p className="changelog-intro">{t.notesPageBody}</p><div className="release-list">{publishedNotes.map(note => <Note key={note.version} note={note} locale={locale} />)}</div></section>}<section id="about" className="about-section"><div className="section about-inner"><div className="about-copy"><span className="eyebrow">{t.creditLabel}</span><h2>{t.creditTitle}</h2><p>{t.creditBody}</p><a className="text-link" href="https://github.com/swoonqx/TypingPet" target="_blank" rel="noreferrer">{t.inspiration} · swoonqx/TypingPet<ArrowUpRight size={17} /></a></div><div className="maker-card panel"><span className="maker-label">{t.maker}</span><div className="maker-name">Jongkeun Choi<span>미엘 (Miel)</span></div><a className="maker-email" href="mailto:support@miel.ing"><Mail size={18} />support@miel.ing</a><div className="social-links"><a href="https://github.com/ynifamily3" target="_blank" rel="noreferrer"><Github size={18} />GitHub<ArrowUpRight size={14} /></a><a href="https://x.com/miel_ggyu" target="_blank" rel="noreferrer"><span className="x-icon">𝕏</span>@miel_ggyu<ArrowUpRight size={14} /></a></div></div></div></section></main><footer className="site-footer section"><a className="footer-brand" href={home}><PawPrint size={19} />typing pet.</a><span>{t.footer}</span><div><a href={repo} target="_blank" rel="noreferrer">{t.source}<ArrowUpRight size={14} /></a><span>{t.license}</span></div></footer></>;
}
