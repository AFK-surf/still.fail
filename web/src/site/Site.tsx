// The official site: one page, rendered to HTML when the site is built (prerender.tsx) and taken over in the browser
// (main.tsx), where the real app runs in its demo box (demo/). Nothing here reads the window while it renders.
//
// Two ideas of it are built side by side for now, the page showing one (?v=1 or ?v=2: data-v on the root, set before
// the first paint by site/index.html): your devices joined into one computer (OneComputer.tsx), and the distance it
// is used across (Distance.tsx). The one chosen stays.
import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import * as css from "./site.css.ts";
import { ThemeSwitch } from "./ThemeSwitch.tsx";
import { OneComputer } from "./OneComputer.tsx";
import { Distance } from "./Distance.tsx";
import { SiteLangContext, useSay, useSiteLang, type SiteLang } from "./words.ts";

declare const __SITE_BETA__: boolean;
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

/** A picture of web/public and its -dark twin: the one for the page's theme shows (site.css.ts), with no script. */
function Themed({ name, className, alt = "", life }: { name: string; className?: string; alt?: string; life?: string }) {
  return (
    <>
      <span className={css.lightOnly}><img className={className} src={`/${name}.svg`} alt={alt} data-life={life} /></span>
      <span className={css.darkOnly}><img className={className} src={`/${name}-dark.svg`} alt={alt} data-life={life} /></span>
    </>
  );
}

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

/**
 * Where the app runs: mounted once the page is in the browser (demo/mount.tsx), in the idea the page shows. Built to
 * HTML, it holds the demo's opening frame (`frame`, desktop and phone), which the demo replaces as it mounts; React
 * leaves what is in it alone.
 */
export function Demo({ mount, frame, v, className, start }: { mount?: DemoProps["mountDemo"]; frame?: { wide: string; phone: string }; v: string; className?: string; start?: "chat" | "stations" }) {
  const root = useRef<HTMLDivElement>(null);
  const lang = useSiteLang();
  useEffect(() => {
    if (root.current && mount && showing(v)) mount(root.current, { ...(start ? { start } : {}), lang });
  }, [mount, v, start, lang]);
  const html = frame ? `<div class="${css.frameWide}">${frame.wide}</div><div class="${css.framePhone}">${frame.phone}</div>` : "";
  return <div className={`${css.demo} ${className ?? ""}`} id="demo" ref={root} dangerouslySetInnerHTML={{ __html: html }} suppressHydrationWarning />;
}

export interface DemoProps { mountDemo?: (root: HTMLElement, options?: { start?: "chat" | "stations"; lang?: "zh" | "en" }) => void; demo?: { wide: string; phone: string } }

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
          <a href={lang === "en" ? "/en/" : "/"} className={css.brand} aria-label={NAME.head + NAME.tail}><Themed name="mark" className={css.logo} /><span>{NAME.head}<span className={css.brandTail}>{NAME.tail}</span></span></a>
          {/* The apps, for the device the page is on (data-platform, set before the first paint by site/index.html): on
              Android the app itself; on a computer a card under the word, with the Mac's, Windows' and a code to scan for Android. */}
          <a className={`${css.navLink} ${css.forAndroid}`} href={ANDROID}>{say.download}</a>
          <span className={`${css.menu} ${css.forComputer}`}>
            <button type="button" className={css.navLink}>{say.download}</button>
            <span className={css.menuCard}>
              <a className={css.menuItem} href={MAC}>
                <b>Mac</b><span>{say.appleSilicon}</span><span className={css.menuGo}>{say.downloadGo}</span>
              </a>
              <a className={css.menuItem} href={WINDOWS}>
                <b>Windows</b><span>x64</span><span className={css.menuGo}>{say.downloadGo}</span>
              </a>
              <span className={css.menuItem}>
                <img className={css.scanCode} src={BETA ? "/android-beta-qr.svg" : "/android-qr.svg"} alt={say.androidQr} width={33} height={33} />
                <span>{say.androidScan}</span>
              </span>
            </span>
          </span>
          {/* The page in the other language (on a phone, in the footer: the bar has no room). */}
          <a className={`${css.navLink} ${css.navButton}`} href={say.otherHref} lang={lang === "en" ? "zh" : "en"} onClick={chooseLang(lang === "en" ? "zh" : "en")}>{say.other}</a>
          <ThemeSwitch />
          <Button href={APP} kind="primary" className={css.navButton}>{say.open} {NAME.head + NAME.tail}</Button>
        </div>
      </nav>

      <div className={css.idea} data-idea="1"><OneComputer {...(mountDemo ? { mountDemo } : {})} {...(demo ? { demo } : {})} /></div>
      <div className={css.idea} data-idea="2"><Distance {...(mountDemo ? { mountDemo } : {})} {...(demo ? { demo } : {})} /></div>

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

      <footer className={css.footer}>
        <div className={`${css.wrap} ${css.footerRow}`}>
          <span className={css.footerFirst}>© 2026 {NAME.head + NAME.tail}</span>
          <a className={css.navLink} href={APP}>{say.web}</a>
          <a className={css.navLink} href={MAC}>Mac</a>
          <a className={css.navLink} href={WINDOWS}>Windows</a>
          <a className={css.navLink} href={ANDROID}>Android</a>
          <a className={css.navLink} href="https://github.com/AFK-surf/still.fail">GitHub</a>
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
