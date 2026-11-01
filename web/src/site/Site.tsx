// The official site: one page, rendered to HTML when the site is built (prerender.tsx) and taken over in the browser
// (main.tsx), where the real app runs in its demo box (demo/). Nothing here reads the window while it renders.
//
// Two ideas of it are built side by side for now, the page showing one (?v=1 or ?v=2: data-v on the root, set before
// the first paint by site/index.html): your devices joined into one computer (OneComputer.tsx), and the distance it
// is used across (Distance.tsx). The one chosen stays.
import { useEffect, useRef, type CSSProperties, type ReactNode, type RefObject } from "react";
import type { DemoOptions, MountedDemo } from "../demo/mount.tsx";
import * as css from "./site.css.ts";
import { ThemeSwitch } from "./ThemeSwitch.tsx";
import { FeishuLogo, GitHubMark, RuntimeLogo, SlackLogo, type RuntimeMarkKind } from "@stillfail/ui/brands.tsx";
import { ChevronDown, Devices } from "@stillfail/ui/icons.tsx";
import { OneComputer } from "./OneComputer.tsx";
import { Distance } from "./Distance.tsx";
import { SiteLangContext, useSay, useSiteLang, type SiteLang } from "./words.ts";

declare const __SITE_BETA__: boolean;
/** The last release with notes in the repository (vite.demo.config.ts lastRelease), null where there are none. */
declare const __SITE_RELEASE__: { version: string; date: string; counts: { fresh: number; better: number; fixed: number }; lines: string[] } | null;
const RELEASE = typeof __SITE_RELEASE__ !== "undefined" ? __SITE_RELEASE__ : null;
/**
 * Built as the test channel's site (youdid.wtf, `pnpm build:site-beta`): named youdid.wtf, opening the test channel's
 * web app, its downloads the beta apps (named youdid.wtf, beside the released ones). The rest is the same page.
 */
const BETA = typeof __SITE_BETA__ !== "undefined" && __SITE_BETA__;
export const APP = BETA ? "https://app.youdid.wtf" : "https://app.still.fail";
const NAME = BETA ? { head: "youdid", tail: ".wtf" } : { head: "still", tail: ".fail" };
/** The apps' latest builds (cloud's /releases/latest/<app> goes to the one released last; -beta: the beta apps'). */
const MAC = `https://app.still.fail/releases/latest/${BETA ? "mac-beta" : "mac"}`;
const WINDOWS = `https://app.still.fail/releases/latest/${BETA ? "win-beta" : "win"}`;
const ANDROID = `https://app.still.fail/releases/latest/${BETA ? "android-beta" : "android"}`;
const INSTALL = "curl -fsSL https://app.still.fail/install.sh | sh -s -- <token>";
/** Its code. */
const GITHUB = "https://github.com/AFK-surf/still.fail";

/** A link as a button; with `then`, its words roll up on hover and those take their place (site.css.ts). */
export function Button({ href, kind, large, then, children, className }: { href: string; kind: "primary" | "ghost"; large?: boolean; then?: string; children: ReactNode; className?: string }) {
  return (
    <a className={`${css.button} ${className ?? ""}`} data-kind={kind} data-size={large ? "large" : undefined} href={href}>
      {then ? <span className={css.roll}><span>{children}</span><span aria-hidden>{then}</span></span> : children}
    </a>
  );
}

/** Whether the page shows idea `v` (data-v on the root; the first when it says none). */
const showing = (v: string) => (document.documentElement.dataset.v ?? "1") === v;

/** The demo's opening frame (demo/prerender.tsx): the desktop's app and the phone's, as HTML. */
export interface DemoFrame { wide: string; phone: string }

/**
 * A frame of the demo, built into the page: a picture of the app until the app takes it over, so it takes no input
 * (inert); the phone's app where its box is narrow, the desktop's elsewhere, as the demo picks (mount.tsx PHONE_BELOW).
 * Without `wide`, the phone's alone (site/phone.html).
 */
export function frameHtml(frame: { wide?: string; phone: string }): string {
  const apps = frame.wide === undefined ? frame.phone : `<div class="${css.frameWide}">${frame.wide}</div><div class="${css.framePhone}">${frame.phone}</div>`;
  return `<div class="${css.frame}" inert>${apps}</div>`;
}

/**
 * Where the app runs: mounted once its script is in the browser (demo/mount.tsx, loaded after the page's own: main.tsx),
 * in the idea the page shows. Built to HTML, it holds the demo's opening frame (`frame`); React leaves it alone until
 * the demo takes it over. `held`: the demo, once it runs.
 */
export function Demo({ mount, frame, v, className, start, held, reusePhoneFrame }: { mount?: DemoProps["mountDemo"]; frame?: DemoFrame; v: string; className?: string; start?: "chat" | "stations"; held?: RefObject<MountedDemo | null>; reusePhoneFrame?: boolean }) {
  const root = useRef<HTMLDivElement>(null);
  const lang = useSiteLang();
  useEffect(() => {
    if (!root.current || !mount || !showing(v)) return;
    const demo = mount(root.current, { ...(start ? { start } : {}), lang, ...(reusePhoneFrame ? { reusePhoneFrame } : {}) });
    if (held) held.current = demo;
  }, [mount, v, start, lang, held, reusePhoneFrame]);
  const html = frame ? frameHtml(frame) : "";
  return <div className={`${css.demo} ${className ?? ""}`} id="demo" ref={root} dangerouslySetInnerHTML={{ __html: html }} suppressHydrationWarning />;
}

/** `demo`: the demo's opening frames, built into the page, by where it opens (on its chat, or on the stations' page). */
export interface DemoProps { mountDemo?: (root: HTMLElement, options?: DemoOptions) => MountedDemo; demo?: Record<"chat" | "stations", DemoFrame> }

/** What it promises about where things are. */
const PROMISES = [
  { title: "数据保存在你的电脑上", text: "对话、文件和记录保存在你的电脑上，云端只负责账号和中继" },
  { title: "点对点连接", text: "设备之间直接连接，无法直连时经加密中继转发" },
];

export function Promises() {
  return (
    <section className={css.section}>
      <div className={`${css.wrap} ${css.promises}`}>
        {PROMISES.map((p) => (
          <div key={p.title} className={css.promise}>
            <h3 className={css.promiseTitle}>{p.title}</h3>
            <p className={css.promiseText}>{p.text}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/** The app to download first, by the device the page is on (data-platform on the root, set before the first paint by
 *  site/index.html): its button shown, the others' not (site.css.ts downloadMain). A device none is made for (an
 *  iPhone, Linux) opens the web app. */
const MAIN = [["mac", MAC], ["windows", WINDOWS], ["android", ANDROID], ["other", APP]] as const;

/** The apps, in a band: its title with a line of every app under it; the button for this device's, and on a computer
 *  a code to scan for the Android app. */
function Downloads() {
  const say = useSay();
  const d = say.downloads;
  return (
    <section id="download" className={css.section}>
      <div className={`${css.wrap} ${css.downloadBand}`}>
        <div>
          <h2 className={css.headingTitle}>{d.title}</h2>
          <p className={css.downloadAll}>
            <span>{d.all}</span>
            <a href={MAC}>Mac</a><a href={WINDOWS}>Windows</a><a href={ANDROID}>Android</a><a href={APP}>{d.web}</a>
          </p>
        </div>
        <div className={css.downloadMain}>
          <span className={css.scanOnComputer}><img className={css.scanCode} src={BETA ? "/android-beta-qr.svg" : "/android-qr.svg"} alt={say.androidQr} width={33} height={33} />{say.androidScan}</span>
          {MAIN.map(([key, href]) => <span key={key} className={css.downloadFor} data-for={key}><Button href={href} kind="primary" large>{d.main[key]}</Button></span>)}
        </div>
      </div>
    </section>
  );
}

/** The agents it runs (station's RuntimeKind), by their names (web/src/format.ts RUNTIME_LABEL). */
const AGENTS: [RuntimeMarkKind, string][] = [
  ["claude", "Claude Code"], ["codex", "Codex"], ["cursor", "Cursor"], ["devin", "Devin"], ["grok", "Grok Build"], ["dsh", "DeepSeek Harness"], ["hermes", "Hermes Agent"],
];

/** What it works with: the agents it runs, and where they are directed from, each its mark and its name. */
function Works() {
  const w = useSay().works;
  return (
    <section className={css.section}>
      <div className={css.wrap}>
        <h2 className={css.headingTitle}>{w.title}</h2>
        <div className={css.works}>
          <span className={css.worksRow}>{w.agents}</span>
          <ul className={css.marks}>{AGENTS.map(([kind, name]) => <li key={kind}><RuntimeLogo runtime={kind} size={18} />{name}</li>)}</ul>
          <span className={css.worksRow}>{w.from}</span>
          <ul className={css.marks}>
            <li><Devices size={18} />{w.places.app}</li>
            <li><SlackLogo size={18} />{w.places.slack}</li>
            <li><FeishuLogo size={18} />{w.places.feishu}</li>
          </ul>
        </div>
      </div>
    </section>
  );
}

/** What a visitor asks first: the question in view, its answer opened under it (no script: <details>). */
function Questions() {
  const say = useSay();
  return (
    <section className={css.section}>
      <div className={`${css.wrap} ${css.questions}`}>
        <h2 className={css.headingTitle}>{say.questionsTitle}</h2>
        <div className={css.questionList}>
          {say.questions.map((x) => (
            <details key={x.q} className={css.question}>
              <summary className={css.questionAsked}>{x.q}<ChevronDown size={18} className={css.questionOpen} /></summary>
              <p className={css.questionAnswer}>{x.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}

/** What the last release brought: its number and day, how many things new, better and fixed, its first new things. */
function Shipped() {
  const s = useSay().shipped;
  if (!RELEASE) return null;
  return (
    <section className={css.section}>
      <div className={`${css.wrap} ${css.shipped}`}>
        <h2 className={css.headingTitle}>{s.title}</h2>
        <div>
          <p className={css.shippedWhen}><span>{s.when(RELEASE.version, RELEASE.date)}</span><span>{s.counts(RELEASE.counts)}</span></p>
          {s.lines && RELEASE.lines.length ? <ul className={css.shippedLines}>{RELEASE.lines.map((l) => <li key={l}>{l}</li>)}</ul> : null}
        </div>
      </div>
    </section>
  );
}

/** The page's last word: its title again, with the ways in. */
function Closing() {
  const say = useSay();
  return (
    <section className={css.section}>
      <div className={`${css.wrap} ${css.closing}`}>
        <h2 className={css.closingTitle}>{say.closing.replace(/\.$/, "")}<span className={css.titleDot}>.</span></h2>
        <div className={css.closingActions}>
          <Button href={APP} kind="primary" large>{say.open} {NAME.head + NAME.tail}</Button>
          <Button href="#download" kind="ghost" large>{say.download}</Button>
        </div>
      </div>
    </section>
  );
}

// ---- The rest ----

export function Site({ mountDemo, demo, lang = "zh" }: DemoProps & { lang?: SiteLang }) {
  return <SiteLangContext.Provider value={lang}><Page {...(mountDemo ? { mountDemo } : {})} {...(demo ? { demo } : {})} /></SiteLangContext.Provider>;
}

/** The other language's page, chosen: kept, so that the page at / does not send this visitor on again (site/index.html). */
const chooseLang = (to: SiteLang) => () => { try { localStorage.setItem("stillfail.site.lang", to); } catch { /* not kept */ } };

function Page({ mountDemo, demo }: DemoProps) {
  const say = useSay(), lang = useSiteLang();
  return (
    <div className={css.page}>
      <nav className={css.nav}>
        <div className={`${css.wrap} ${css.navRow}`}>
          <a href={lang === "en" ? "/en/" : "/"} className={css.brand} aria-label={NAME.head + NAME.tail}><span>{NAME.head}<span className={css.brandDot}>.</span>{NAME.tail.slice(1)}</span></a>
          {/* The apps: their section, on every device. */}
          <a className={css.navLink} href="#download">{say.download}</a>
          {/* The page in the other language (on a phone, in the footer: the bar has no room). */}
          <a className={`${css.navLink} ${css.navButton}`} href={say.otherHref} lang={lang === "en" ? "zh" : "en"} onClick={chooseLang(lang === "en" ? "zh" : "en")}>{say.other}</a>
          {/* Its code, a mark the bar keeps on a phone too. */}
          <a className={`${css.navLink} ${css.navMark}`} href={GITHUB} aria-label="GitHub" title="GitHub"><GitHubMark size={20} /></a>
          <ThemeSwitch />
          <Button href={APP} kind="primary" className={css.navButton}>{say.open} {NAME.head + NAME.tail}</Button>
        </div>
      </nav>

      <div className={css.idea} data-idea="1"><OneComputer {...(mountDemo ? { mountDemo } : {})} {...(demo ? { demo } : {})} /></div>
      <div className={css.idea} data-idea="2"><Distance {...(mountDemo ? { mountDemo } : {})} {...(demo ? { demo } : {})} /></div>

      <Works />

      <Downloads />

      <section id="start" className={css.section}>
        <div className={`${css.wrap} ${css.install}`}>
          <div>
            <h2 className={css.headingTitle}><span className={css.phrase}>{say.install[0]}</span>{lang === "en" ? " " : ""}<span className={css.phrase}>{say.install[1]}</span></h2>
          </div>
          <div className={css.terminal}>
            <div className={css.terminalBody}>
              <span className={css.command}><span className={css.prompt}>$ </span><span className={css.typed} style={{ "--chars": `${INSTALL.length}ch`, "--steps": INSTALL.length } as CSSProperties}>{INSTALL}</span></span>
              <span className={css.output} data-at="1">{say.installSteps[0]}</span>
              <span className={css.output} data-at="2">{say.installSteps[1]}</span>
              <span className={css.output} data-at="3" data-ok>{say.installSteps[2]}</span>
            </div>
          </div>
        </div>
      </section>

      <Shipped />

      <Questions />

      <Closing />

      <footer className={css.footer}>
        <div className={`${css.wrap} ${css.footerRow}`}>
          <span className={css.footerFirst}>© 2026 {NAME.head + NAME.tail}</span>
          <a className={css.navLink} href={APP}>{say.web}</a>
          <a className={css.navLink} href={MAC}>Mac</a>
          <a className={css.navLink} href={WINDOWS}>Windows</a>
          <a className={css.navLink} href={ANDROID}>Android</a>
          <a className={css.navLink} href={GITHUB}>GitHub</a>
          {/* The legal pages: static files in web/public (terms.html, privacy.html, trademark.html; en/ their English). */}
          <a className={css.navLink} href={`${say.legal}/terms`}>{say.terms}</a>
          <a className={css.navLink} href={`${say.legal}/privacy`}>{say.privacy}</a>
          <a className={css.navLink} href={`${say.legal}/trademark`}>{say.trademark}</a>
          <a className={css.navLink} href={say.otherHref} lang={lang === "en" ? "zh" : "en"} onClick={chooseLang(lang === "en" ? "zh" : "en")}>{say.other}</a>
        </div>
      </footer>
    </div>
  );
}
