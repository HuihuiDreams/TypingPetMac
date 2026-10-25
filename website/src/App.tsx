import { useEffect, useRef, useState } from 'react';
import { Accordion } from '@base-ui/react/accordion';
import { Button } from '@base-ui/react/button';
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUpRight, Check, Copy, Download, Image, Keyboard, ListTodo, Mail, MousePointer2, Move, PawPrint, Plus, Terminal, Timer, Wrench, X } from 'lucide-react';
import { content, type Locale } from './content';
import release from './release';
import { downloadUrl } from './downloads';
import history from './releases.json';
import { trackSiteEvent } from './analytics';
import AnalyticsNotice from './AnalyticsNotice';
import Newsletter from './Newsletter';
import ThemePicker from './ThemePicker';
import LanguagePicker from './LanguagePicker';

const repo = 'https://github.com/ynifamily3/TypingPetMac';
const brew = 'brew tap ynifamily3/tap\nbrew install --cask ynifamily3/tap/typing-pet';
const compareVersion = (a: string, b: string) => {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
};
const publishedNotes = history.filter(n => compareVersion(n.version, release.version) <= 0).sort((a, b) => compareVersion(b.version, a.version));
const iconProps = { size: 20, strokeWidth: 2 };
async function copyText(value: string) {
  try {
    await navigator.clipboard.writeText(value);
    return;
  } catch {}
  const input = document.createElement('textarea');
  input.value = value;
  input.setAttribute('readonly', '');
  input.style.position = 'fixed';
  input.style.opacity = '0';
  document.body.append(input);
  input.select();
  const copied = document.execCommand('copy');
  input.remove();
  if (!copied) throw new Error('Clipboard access is unavailable');
}
function Github({ size = 20 }: { size?: number; strokeWidth?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 6v-3.9a3.4 3.4 0 0 0-1-2.7c3.3-.4 6.7-1.6 6.7-7.3a5.7 5.7 0 0 0-1.5-4c.2-.4.7-1.9-.1-3.9 0 0-1.3-.4-4.1 1.5a14.4 14.4 0 0 0-7.4 0C4.8-.2 3.5.2 3.5.2c-.8 2-.3 3.5-.1 3.9a5.7 5.7 0 0 0-1.5 4c0 5.7 3.4 6.9 6.7 7.3a3.4 3.4 0 0 0-1 2.7V22" transform="translate(1 1) scale(.91)" /></svg>;
}

function HeroTitle({ locale }: { locale: Locale }) {
  const t = content[locale];
  const lines = [t.hero1, t.hero2, t.hero3];
  const total = lines.reduce((sum, line) => sum + line.length, 0);
  const [visibleCount, setVisibleCount] = useState(0);
  useEffect(() => {
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (motion.matches) {
      setVisibleCount(total);
      return;
    }
    let count = 0;
    let interval: ReturnType<typeof setInterval> | undefined;
    const start = window.setTimeout(() => {
      interval = window.setInterval(() => {
        count += 1;
        setVisibleCount(count);
        window.dispatchEvent(new CustomEvent('typingpet:typewriter-tick', { detail: { count } }));
        if (count >= total && interval) clearInterval(interval);
      }, 54);
    }, 180);
    const onMotionChange = (event: MediaQueryListEvent) => {
      if (!event.matches) return;
      clearTimeout(start);
      if (interval) clearInterval(interval);
      setVisibleCount(total);
    };
    motion.addEventListener('change', onMotionChange);
    return () => {
      clearTimeout(start);
      if (interval) clearInterval(interval);
      motion.removeEventListener('change', onMotionChange);
    };
  }, [total]);

  let remaining = visibleCount;
  const shown = lines.map(line => {
    const count = Math.min(line.length, remaining);
    remaining = Math.max(0, remaining - count);
    return line.slice(0, count);
  });
  const activeLine = visibleCount < lines[0].length ? 0 : visibleCount < lines[0].length + lines[1].length ? 1 : 2;
  const cursor = <span className="typewriter-cursor" aria-hidden="true" />;
  return <h1 className="typewriter-title">
    <span className="sr-only">{lines.join(' ')}</span>
    <span className="typewriter-line hero-line-first" aria-hidden="true">{shown[0]}{activeLine === 0 && cursor}</span><br aria-hidden="true" />
    <span className="typewriter-line" aria-hidden="true">{shown[1]}{activeLine === 1 && cursor}</span><br aria-hidden="true" />
    <span className="typewriter-line highlight" aria-hidden="true">{shown[2]}{activeLine === 2 && cursor}</span>
  </h1>;
}

function CodeBlock({ code, locale, command }: { code: string; locale: Locale; command: 'install' | 'update' }) {
  const t = content[locale];
  const [status, setStatus] = useState<'idle' | 'success' | 'error'>('idle');
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  async function copy() {
    try { await copyText(code); setStatus('success'); trackSiteEvent({ event: 'homebrew_copied', command }); }
    catch { setStatus('error'); }
    clearTimeout(timer.current); timer.current = setTimeout(() => setStatus('idle'), 3000);
  }
  const tooltip = status === 'success' ? t.copied : status === 'error' ? t.copyFailed : t.copy;
  return <div className="code-box"><div className="code-toolbar"><span><Terminal size={16} /> {t.terminal}</span><Button className="copy-button" onClick={copy} aria-label={tooltip} data-tooltip={tooltip}>{status === 'success' ? <Check size={16} /> : status === 'error' ? <X size={16} /> : <Copy size={16} />}</Button></div><pre><code>{code}</code></pre><span className="sr-only" role="status">{status === 'success' ? t.copied : status === 'error' ? t.copyError : ''}</span></div>;
}

function PetDemo({ locale }: { locale: Locale }) {
  const t = content[locale];
  const [seconds, setSeconds] = useState(20 * 60);
  useEffect(() => {
    const interval = setInterval(() => setSeconds(value => value <= 1 ? 20 * 60 : value - 1), 1000);
    return () => clearInterval(interval);
  }, []);
  const time = `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  return <div className="demo-wrap"><div className="demo-window"><div className="window-bar"><div className="window-dots" aria-hidden="true"><i /><i /><i /></div><span className="window-title"><PawPrint size={16} fill="currentColor" aria-hidden="true" />{t.demoTitle}</span></div><div className="desktop-scene"><div className="demo-note"><span className="check-circle" /><span>{t.demoTask}</span><span className="timer-text">{time}</span></div><div className="desk-line" /><span className="keycap keycap-left" aria-hidden="true">⌘</span><span className="keycap keycap-right" aria-hidden="true">↵</span></div></div></div>;
}

function FloatingPet({ locale, page }: { locale: Locale; page: 'home' | 'changelog' | 'unsubscribe' }) {
  const t = content[locale];
  const [pose, setPose] = useState('idle');
  const [tick, setTick] = useState(0);
  const [position, setPosition] = useState<{ x: number; y: number } | null>(null);
  const [anchor, setAnchor] = useState<{ x: number; y: number } | null>(null);
  const [stuck, setStuck] = useState(page !== 'home');
  const [ready, setReady] = useState(page !== 'home');
  const [jumping, setJumping] = useState(false);
  const [dragging, setDragging] = useState(false);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const preloadedPoses = useRef<HTMLImageElement[]>([]);
  const count = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const jumpTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const dragOffset = useRef<{ x: number; y: number } | null>(null);
  const manuallyPositioned = useRef(false);
  const previousStuck = useRef(stuck);
  const lastTypingReaction = useRef(0);
  const react = () => {
    count.current += 1;
    setPose(count.current % 2 ? 'left' : 'right');
    setTick(count.current);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setPose('idle'), 750);
  };
  const reactRef = useRef(react);
  reactRef.current = react;
  useEffect(() => {
    preloadedPoses.current = ['idle', 'left', 'right'].map(pose => {
      const image = new window.Image();
      image.src = `/assets/pet-${pose}.webp`;
      return image;
    });
    const onKeyDown = (event: KeyboardEvent) => {
      if (!event.repeat && !event.metaKey && !event.ctrlKey && !event.altKey && event.key.length === 1) reactRef.current();
    };
    const onTypewriterTick = (event: Event) => {
      const count = (event as CustomEvent<{ count: number }>).detail.count;
      const now = performance.now();
      if (count % 4 === 0 && now - lastTypingReaction.current >= 180) {
        lastTypingReaction.current = now;
        reactRef.current();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('typingpet:typewriter-tick', onTypewriterTick);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('typingpet:typewriter-tick', onTypewriterTick);
      clearTimeout(timer.current);
      clearTimeout(jumpTimer.current);
    };
  }, []);
  useEffect(() => {
    if (page !== 'home') {
      setStuck(true);
      setReady(true);
      return;
    }
    const updateAnchor = () => {
      const scene = document.querySelector('.desktop-scene');
      if (!scene) return;
      const rect = scene.getBoundingClientRect();
      const size = buttonRef.current?.getBoundingClientRect().width || 100;
      setAnchor({
        x: rect.left + window.scrollX + (rect.width - size) / 2,
        y: rect.top + window.scrollY + (rect.height - size) / 2,
      });
      setReady(true);
    };
    const updateStuck = () => {
      if (manuallyPositioned.current) return;
      const hero = document.querySelector('.hero');
      const threshold = (hero?.getBoundingClientRect().height || window.innerHeight) * 0.45;
      setStuck(window.scrollY > threshold);
    };
    updateAnchor();
    updateStuck();
    window.addEventListener('scroll', updateStuck, { passive: true });
    window.addEventListener('resize', updateAnchor);
    return () => {
      window.removeEventListener('scroll', updateStuck);
      window.removeEventListener('resize', updateAnchor);
    };
  }, [page]);
  useEffect(() => {
    if (previousStuck.current !== stuck) {
      setJumping(true);
      clearTimeout(jumpTimer.current);
      jumpTimer.current = setTimeout(() => setJumping(false), 520);
      previousStuck.current = stuck;
    }
  }, [stuck]);
  const style = position
    ? { left: position.x, top: position.y, right: 'auto' as const, bottom: 'auto' as const }
    : !stuck && anchor
      ? { left: anchor.x, top: anchor.y, right: 'auto' as const, bottom: 'auto' as const }
      : !ready ? { visibility: 'hidden' as const } : undefined;
  return <Button
    ref={buttonRef}
    className={`floating-pet ${stuck ? 'is-stuck' : 'is-anchored'}${dragging ? ' is-dragging' : ''}${jumping ? ' is-jumping' : ''}`}
    style={style}
    aria-label={t.demoKey}
    onClick={react}
    onPointerDown={event => {
      const rect = event.currentTarget.getBoundingClientRect();
      dragOffset.current = { x: event.clientX - rect.left, y: event.clientY - rect.top };
      manuallyPositioned.current = true;
      setPosition({ x: rect.left, y: rect.top });
      setStuck(true);
      setDragging(true);
      event.currentTarget.setPointerCapture(event.pointerId);
    }}
    onPointerMove={event => {
      if (!dragOffset.current) return;
      const rect = event.currentTarget.getBoundingClientRect();
      setPosition({
        x: Math.max(0, Math.min(window.innerWidth - rect.width, event.clientX - dragOffset.current.x)),
        y: Math.max(0, Math.min(window.innerHeight - rect.height, event.clientY - dragOffset.current.y)),
      });
    }}
    onPointerUp={() => { dragOffset.current = null; setDragging(false); }}
    onPointerCancel={() => { dragOffset.current = null; setDragging(false); }}
  >
    <span className="floating-pet-bubble" aria-hidden="true">{t.demoBubble}</span>
    <img key={tick} className={pose !== 'idle' ? 'pet-image reacting' : 'pet-image'} src={`/assets/pet-${pose}.webp`} width="480" height="480" alt="" draggable="false" />
  </Button>;
}

function Checksum({ value, locale }: { value: string; locale: Locale }) {
  const t = content[locale];
  const [status, setStatus] = useState<'idle' | 'success' | 'error'>('idle');
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  async function copy() {
    try {
      await copyText(value);
      setStatus('success');
    } catch {
      setStatus('error');
    }
    clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setStatus('idle'), 1800);
  }
  const tooltip = status === 'success' ? t.copied : status === 'error' ? t.copyFailed : t.copyChecksum;
  return <div className="checksum-row">
    <span>{t.checksum}</span>
    <code>{value}</code>
    <button type="button" className="checksum-copy" aria-label={tooltip} data-tooltip={tooltip} onClick={copy}>
      {status === 'success' ? <Check size={16} aria-hidden="true" /> : status === 'error' ? <X size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}
    </button>
    <span className="sr-only" role="status">{status === 'success' ? t.copied : status === 'error' ? t.copyError : ''}</span>
  </div>;
}

function Install({ locale }: { locale: Locale }) {
  const t = content[locale];
  return <section id="install" className="section install-section">
    <div className="section-head"><h2>{t.installTitle}</h2>{t.installBody && <p>{t.installBody}</p>}</div>
    <div className="install-card panel install-methods">
      {release.dmg && <article className="install-method" id="dmg-install">
        <div className="install-heading"><h3>{t.dmgTitle}</h3><span className="tag">v{release.version} ({(release.dmg.size / 1e6).toFixed(1)} MB)</span></div>

        <div className="download-actions"><a className="button primary" href={downloadUrl('github', 'dmg')} onClick={() => trackSiteEvent({ event: 'download_clicked', source: 'github', placement: 'install', format: 'dmg' })}><Github {...iconProps} />{t.dmgDownload}<span className="small-label">{t.recommended}</span></a><a className="text-link" href={downloadUrl('direct', 'dmg')} onClick={() => trackSiteEvent({ event: 'download_clicked', source: 'direct', placement: 'install', format: 'dmg' })}>{t.directDownload}<ArrowDown size={17} /></a></div>
        <Checksum value={release.dmg.sha256} locale={locale} />
        <div className="minor-links"><a href={release.releaseUrl}>{t.releasePage}<ArrowUpRight size={14} /></a></div>
      </article>}
      <article className="install-method" id="zip-install">
        <div className="install-heading"><h3>{t.zipTitle}</h3><span className="tag">v{release.version} ({(release.size / 1e6).toFixed(1)} MB)</span></div>

        <div className="download-actions"><a className="button primary" href={downloadUrl('github', 'zip')} onClick={() => trackSiteEvent({ event: 'download_clicked', source: 'github', placement: 'install', format: 'zip' })}><Github {...iconProps} />{t.zipTab}</a><a className="text-link" href={downloadUrl('direct', 'zip')} onClick={() => trackSiteEvent({ event: 'download_clicked', source: 'direct', placement: 'install', format: 'zip' })}>{t.directDownload}<ArrowDown size={17} /></a></div>
        <Checksum value={release.sha256} locale={locale} />
        <div className="minor-links"><a href={release.releaseUrl}>{t.releasePage}<ArrowUpRight size={14} /></a></div>
      </article>
      <article className="install-method" id="homebrew">
        <h3>{t.brewTitle}</h3><p>{t.brewBody} <a href="https://brew.sh/" target="_blank" rel="noreferrer">Homebrew <ArrowUpRight size={14} /></a></p>
        <CodeBlock code={brew} locale={locale} command="install" />
        <p className="brew-after">{t.brewAfter}</p>

      </article>
    </div>
  </section>;
}

function formatReleaseDate(date: string, locale: Locale) {
  if (locale !== 'ko') return date;
  const releasedAt = new Date(`${date}T00:00:00`).getTime();
  const hoursAgo = Math.max(0, Math.floor((Date.now() - releasedAt) / 3_600_000));
  if (hoursAgo < 1) return '방금 (1시간 이내)';
  if (hoursAgo < 24) return `${hoursAgo}시간 전`;
  const daysAgo = Math.floor(hoursAgo / 24);
  if (daysAgo > 28) return date;
  if (daysAgo < 7) return `${daysAgo}일 전`;
  return `${Math.floor(daysAgo / 7)}주 전`;
}

function formatHeroRelease(date: string, version: string, locale: Locale, updatedToday: string) {
  const released = new Date(`${date}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const daysAgo = Math.max(0, Math.floor((today.getTime() - released.getTime()) / 86_400_000));
  if (daysAgo > 28) return `v${version}`;
  if (daysAgo === 0) return updatedToday;
  const relativeTime = new Intl.RelativeTimeFormat(locale, { numeric: 'always' });
  if (daysAgo < 7) return relativeTime.format(-daysAgo, 'day');
  return relativeTime.format(-Math.floor(daysAgo / 7), 'week');
}

function Note({ note, locale }: { note: typeof history[number]; locale: Locale }) {
  const t = content[locale];
  const [dateLabel, setDateLabel] = useState(note.date);
  useEffect(() => {
    const update = () => setDateLabel(formatReleaseDate(note.date, locale));
    update();
    const interval = setInterval(update, 60_000);
    return () => clearInterval(interval);
  }, [note.date, locale]);
  return <article className="release-card panel"><div className="release-meta"><span className="version-label">v{note.version}</span><time dateTime={note.date}>{dateLabel}</time></div><h3>{note[locale].title}</h3><ul>{note[locale].items.map(item => <li key={item}>{item}</li>)}</ul><a className="text-link" href={`${repo}/releases/tag/v${note.version}`}>{t.releasePage}<ArrowUpRight size={16} /></a></article>;
}

export default function App({ locale = 'ko', page = 'home' }: { locale?: Locale; page?: 'home' | 'changelog' | 'unsubscribe' }) {
  const t = content[locale];
  const home = `/${locale}/`;
  const featureIcons = [Keyboard, Image, Timer, MousePointer2];
  const benefitIcons = [Move, PawPrint, Download];
  const navIds = ['features', 'install', 'notes', 'newsletter'];
  return <><a className="skip-link" href="#main">{t.skip}</a><header className="site-header"><div className="header-inner"><a className="brand" href={home} aria-label={t.homeLabel}><span className="brand-icon"><PawPrint size={22} fill="currentColor" /></span><span>typing pet<span className="brand-dot">.</span></span><span className="brand-platform">for Mac</span></a><nav aria-label={t.menuLabel}>{t.nav.map((name, i) => <a key={name} href={page === 'home' ? `#${navIds[i]}` : `${home}#${navIds[i]}`}>{name}</a>)}</nav><div className="header-controls"><LanguagePicker locale={locale} page={page} /><ThemePicker locale={locale} /></div></div></header><main id="main" tabIndex={-1}>{page === 'home' ? <><section className="hero section"><div className="hero-copy">{t.heroLabel && <div className="hero-label"><span className="status-dot" />{t.heroLabel}</div>}<HeroTitle locale={locale} /><p className="hero-description">{t.heroBody}</p><div className="hero-actions"><a className="button primary" href={downloadUrl('github', release.dmg ? 'dmg' : 'zip')} onClick={() => trackSiteEvent({ event: 'download_clicked', source: 'github', placement: 'hero', format: release.dmg ? 'dmg' : 'zip' })}><Github {...iconProps} />{release.dmg ? t.dmgDownload : t.zipTab}<ArrowDown size={18} /></a>{release.dmg && <a className="brew-link" href={downloadUrl('github', 'zip')} onClick={() => trackSiteEvent({ event: 'download_clicked', source: 'github', placement: 'hero', format: 'zip' })}><ArrowDown size={17} />{t.zipTab}</a>}<a className="brew-link" href="#homebrew"><Terminal size={17} />{t.installBrew}<ArrowUpRight size={16} /></a></div><div className="hero-meta"><span>{formatHeroRelease(release.date, release.version, locale, t.updatedToday)}</span><span>{t.requirements}</span></div></div><PetDemo locale={locale} /></section><div className="benefit-strip"><div>{t.strip.map((text, i) => { const Icon = benefitIcons[i]; return <span key={text}><Icon size={19} aria-hidden="true" />{text}</span>; })}</div></div><section id="features" className="section features-section"><div className="section-head"><h2>{t.featureTitle}</h2></div><div className="feature-grid">{t.features.map(([title, description], i) => { const Icon = featureIcons[i]; return <article className={`feature-card feature-${i + 1}`} key={title}><div className="feature-top"><span className="feature-number">0{i + 1}</span><Icon size={28} strokeWidth={1.8} /></div><h3>{title}</h3><p>{description}</p></article>; })}</div></section><section className="section focus-section"><div className="focus-copy"><h2>{t.focusTitle}</h2>{t.focusBody && <p>{t.focusBody}</p>}<div className="focus-tags">{t.focusTags.map((tag, index) => { const Icon = index === 0 ? ListTodo : index === 1 ? Timer : null; return <span className="tag" key={tag}>{Icon ? <Icon size={14} aria-hidden="true" /> : <span aria-hidden="true">🍅</span>}{tag}</span>; })}</div></div><div className="focus-visual panel">{t.focusLabel && <div className="focus-visual-label"><ListTodo size={18} />{t.focusLabel}</div>}<img src="/assets/todo-active.webp" width="720" height="220" alt={t.screenshotAlt} loading="lazy" /><div className="focus-bottom"><span className="focus-mini-pet"><img src="/assets/pet-sparkle.webp" width="90" height="90" alt="" loading="lazy" /></span><Timer size={22} /></div></div></section><Install locale={locale} /><section className="section faq-section"><h2>{t.faqTitle}</h2><Accordion.Root className="faq" multiple>{t.faqs.map(([question, answer], i) => <Accordion.Item key={question} value={i} className="faq-item"><Accordion.Header><Accordion.Trigger className="faq-trigger">{question}<Plus size={21} /></Accordion.Trigger></Accordion.Header><Accordion.Panel className="faq-panel"><p>{locale === 'ko' && i === 2 ? <>{answer.split(t.faqWindowsLink)[0]}<a href="https://github.com/swoonqx/TypingPet" target="_blank" rel="noreferrer">{t.faqWindowsLink}</a>{answer.split(t.faqWindowsLink)[1]}</> : answer}</p></Accordion.Panel></Accordion.Item>)}</Accordion.Root></section><section id="notes" className="section notes-section"><div className="section-head notes-head"><div><h2>{t.notesTitle}</h2><p className="notes-description"><Wrench size={16} aria-hidden="true" />{t.notesBody}</p></div><a className="button secondary" href={`${home}changelog/`}>{t.allNotes}<ArrowRight size={18} /></a></div><Note note={publishedNotes[0]} locale={locale} /></section></> : page === 'changelog' ? <section className="section changelog-page"><a className="text-link back-link" href={home}><ArrowLeft size={17} />{t.back}</a><h1>{t.notesPageTitle}</h1><p className="changelog-intro">{t.notesPageBody}</p><div className="release-list">{publishedNotes.map(note => <Note key={note.version} note={note} locale={locale} />)}</div></section> : null}<Newsletter locale={locale} view={page === 'unsubscribe' ? 'unsubscribe' : 'subscribe'} />{page !== 'unsubscribe' && <section id="about" className="about-section"><div className="section about-inner"><div className="about-copy"><h2>{t.creditTitle}</h2>{t.creditBody.split('\n\n').map((paragraph, index) => <p key={index}>{paragraph}</p>)}{locale === 'ko' && <p className="credit-personal-note">일할 때 쓰려고 만들었어요.</p>}<a className="button secondary" href="https://github.com/swoonqx/TypingPet" target="_blank" rel="noreferrer">{t.windowsVersion}<ArrowUpRight size={17} /></a></div><div className="maker-card panel"><span className="maker-label">{t.maker}</span><div className="maker-name">{t.makerDisplayName}<span>Jongkeun Choi</span></div><a className="maker-email" href="mailto:support@miel.ing"><Mail size={18} />support@miel.ing</a><div className="social-links"><a href="https://github.com/ynifamily3" target="_blank" rel="noreferrer"><Github size={18} />GitHub<ArrowUpRight size={14} /></a><a href="https://x.com/miel_ggyu" target="_blank" rel="noreferrer"><span className="x-icon">𝕏</span>@miel_ggyu<ArrowUpRight size={14} /></a></div></div></div></section>}</main><FloatingPet locale={locale} page={page} /><footer className="site-footer section"><a className="footer-brand" href={home}><PawPrint size={19} />typing pet.</a><span>{t.footer}</span><div><a href={repo} target="_blank" rel="noreferrer">{t.source}<ArrowUpRight size={14} /></a><span>{t.license}</span></div></footer><AnalyticsNotice locale={locale} /></>;
}
