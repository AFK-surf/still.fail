// The official site: one page, rendered to HTML when the site is built (prerender.tsx) and taken over in the browser
// (main.tsx), where the real app runs in its demo box (demo/). Few words; what moves is CSS (site.css.ts). Nothing here
// reads the window while it renders.
import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import * as css from "./site.css.ts";
import { ThemeSwitch } from "./ThemeSwitch.tsx";
import { heroMotion } from "./motion.ts";

const APP = "https://app.still.fail";
/** The apps' latest builds (cloud's /releases/latest/<app> goes to the one released last). */
const MAC = `${APP}/releases/latest/mac`;
const ANDROID = `${APP}/releases/latest/android`;
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
function Button({ href, kind, large, then, children, className }: { href: string; kind: "primary" | "ghost"; large?: boolean; then?: string; children: ReactNode; className?: string }) {
  return (
    <a className={`${css.button} ${className ?? ""}`} data-kind={kind} data-size={large ? "large" : undefined} href={href}>
      {then ? <span className={css.roll}><span>{children}</span><span aria-hidden>{then}</span></span> : children}
    </a>
  );
}

/**
 * Where the app runs: mounted once the page is in the browser (demo/mount.tsx). Built to HTML, it holds the demo's
 * opening frame (`frame`, desktop and phone), which the demo replaces as it mounts; React leaves what is in it alone.
 */
function Demo({ mount, frame }: { mount?: (root: HTMLElement) => void; frame?: { wide: string; phone: string } }) {
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (root.current && mount) mount(root.current);
  }, [mount]);
  const html = frame ? `<div class="${css.frameWide}">${frame.wide}</div><div class="${css.framePhone}">${frame.phone}</div>` : "";
  return <div className={css.demo} id="demo" ref={root} dangerouslySetInnerHTML={{ __html: html }} suppressHydrationWarning />;
}

/**
 * A domain's dot, and what the domain says in Chinese standing upright on it: above it, and, when there is a `below`,
 * on through it underneath, the dot parting the two.
 */
/** Words a character to a span, for the characters to land one by one (motion.ts). */
const chars = (words: string) => [...words].map((c, i) => <span key={i} className={css.dotChar}><span className={css.dotGlyph}>{c}</span></span>);

/** The intro's characters, each its own box to fly to its place on a dot; spaces only keep their room. */
const bigChars = (words: string) => [...words].map((c, i) => c === " " ? <span key={i}>&nbsp;</span> : <span key={i} className={css.introChar}>{c}</span>);

function Dot({ above, below }: { above: string; below?: string }) {
  // Hangs just after the dot (the end of the word before): the words are outside the line's words, so the English can
  // be brought in (motion.ts) while they are already there.
  return (
    <span className={css.dot} aria-hidden>
      <span className={css.dotSay} data-at="above"><span className={css.dotWords}>{chars(above)}</span></span>
      {below && <span className={css.dotSay} data-at="below"><span className={css.dotWords}>{chars(below)}</span></span>}
    </span>
  );
}

// ---- The rest ----

export function Site({ mountDemo, demo }: { mountDemo?: (root: HTMLElement) => void; demo?: { wide: string; phone: string } }) {
  const hero = useRef<HTMLElement>(null);
  useEffect(() => (hero.current ? heroMotion(hero.current) : undefined), []);
  return (
    <div className={css.page}>
      <nav className={css.nav}>
        <div className={`${css.wrap} ${css.navRow}`}>
          <a href="/" className={css.brand} aria-label="still.fail"><Themed name="mark" className={css.logo} /><span>still<span className={css.brandTail}>.fail</span></span></a>
          <ThemeSwitch />
          <Button href={APP} kind="primary" className={css.navButton}>打开 still.fail</Button>
        </div>
      </nav>

      <header className={css.hero} ref={hero}>
        <div className={css.grid} /><div className={css.beam} />
        <div className={css.wrap}>
          {/* The two domains, what the user keeps saying to the agent: the one the page was opened on is lit (data-host, set
              before the first paint by site/index.html; still.fail when neither). */}
          <div className={css.titleStage}>
            {/* What the page opens with before the title (motion.ts): the Chinese, large, which then goes to the dots. */}
            <div className={css.intro} aria-hidden>
              <span className={css.introLine} data-line="still.fail">{bigChars("还是不行")}</span>
              <span className={css.introLine} data-line="youdid.wtf">{bigChars("干的什么 JB")}</span>
            </div>
            <h1 className={css.title}>
              <span className={css.titleDomain} data-domain="still.fail"><span className={css.word}>still.</span><Dot above="还是不行" /><span className={css.word}>fail</span></span><br />
              <span className={css.titleDomain} data-domain="youdid.wtf"><span className={css.word}>youdid.</span><Dot above="干的什么" below="JB" /><span className={css.word}>wtf</span></span>
            </h1>
          </div>
          <div className={`${css.actions} ${css.heroActions}`}>
            <Button href={APP} kind="primary" large then="开喷">我来指挥</Button>
            <Button href={MAC} kind="ghost" large>下载 Mac 版</Button>
            <Button href={ANDROID} kind="ghost" large>下载 Android 版</Button>
          </div>
          <div className={css.stage}>
            <div className={css.stageGlow} />
            <div className={css.edge}>
              <Demo {...(mountDemo ? { mount: mountDemo } : {})} {...(demo ? { frame: demo } : {})} />
            </div>
          </div>
        </div>
      </header>

      <section id="start" className={css.section}>
        <div className={css.sectionLight} />
        <div className={css.wrap}>
          <div className={`${css.terminal} ${css.reveal}`}>
            <div className={css.terminalBar}><span className={css.terminalDot} /><span className={css.terminalDot} /><span className={css.terminalDot} /></div>
            <div className={css.terminalBody}>
              <span className={css.prompt}>$ </span>
              <span className={css.typed} style={{ "--chars": `${INSTALL.length}ch`, "--steps": INSTALL.length } as CSSProperties}>{INSTALL}</span>
              <span className={css.output} data-at="1">→ 下载 still.fail station · 加入 workspace「Acme」</span>
              <span className={css.output} data-at="2">→ 注册为登录启动的服务</span>
              <span className={css.output} data-at="3" data-ok>✓ station 已上线，去聊天里 @ 它吧</span>
            </div>
          </div>
        </div>
      </section>

      <footer className={css.footer}>
        <div className={`${css.wrap} ${css.footerRow}`}>
          <span className={css.footerFirst}>© 2026 still.fail</span>
          <a className={css.navLink} href={APP}>网页版</a>
          <a className={css.navLink} href={MAC}>Mac</a>
          <a className={css.navLink} href={ANDROID}>Android</a>
          <a className={css.navLink} href="https://github.com/zzj3720/ember">GitHub</a>
        </div>
      </footer>
    </div>
  );
}
