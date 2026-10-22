// The official site: one page, rendered to HTML when the site is built (prerender.tsx) and taken over in the browser
// (main.tsx), where the real app runs in its demo box (demo/). Few words; what moves is CSS (site.css.ts). Nothing here
// reads the window while it renders.
import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import * as css from "./site.css.ts";
import { ThemeSwitch } from "./ThemeSwitch.tsx";

declare const __SITE_BETA__: boolean;
/**
 * Built as the test channel's site (youdid.wtf, `pnpm build:site-beta`): named youdid.wtf, opening the test channel's
 * web app, its downloads the beta apps (named youdid.wtf, beside the released ones). The rest is the same page.
 */
const BETA = typeof __SITE_BETA__ !== "undefined" && __SITE_BETA__;
const APP = BETA ? "https://app.youdid.wtf" : "https://app.still.fail";
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

// ---- What it connects ----

/** A box in a picture: a device or a machine, its name in it; `main`: the machine everything goes to, lit. */
function Node({ x, y, w, h, label, main, round }: { x: number; y: number; w: number; h: number; label: string; main?: boolean; round?: boolean }) {
  return (
    <g className={css.node} data-main={main ? "" : undefined}>
      <rect x={x} y={y} width={w} height={h} rx={round ? h / 2 : 10} />
      <text x={x + w / 2} y={y + h / 2} dominantBaseline="central" textAnchor="middle">{label}</text>
    </g>
  );
}

/** A line between two boxes, drawn in as it scrolls into view (site.css.ts). */
const Line = ({ d }: { d: string }) => <path className={css.wire} d={d} pathLength={1} />;

/** From (x1, y1) to (x2, y2), leaving and arriving level. */
const across = (x1: number, y1: number, x2: number, y2: number) => {
  const mid = (x1 + x2) / 2;
  return `M${x1} ${y1} C${mid} ${y1} ${mid} ${y2} ${x2} ${y2}`;
};

/** You and your machine: wherever you are, to the one machine. */
function YouPicture() {
  const from = ["手机", "网页", "Slack", "飞书"];
  return (
    <svg viewBox="0 0 300 150" role="img" aria-label="手机、网页、Slack、飞书都连到你的机器">
      {from.map((_, i) => <Line key={i} d={across(84, 18 + i * 38, 196, 75)} />)}
      {from.map((label, i) => <Node key={label} x={8} y={5 + i * 38} w={76} h={26} label={label} round />)}
      <Node x={196} y={45} w={96} h={60} label="你的机器" main />
    </svg>
  );
}

/** Machines and machines: a few, used as one. */
function MachinesPicture() {
  return (
    <svg viewBox="0 0 300 150" role="img" aria-label="Mac、Linux、Windows 三台机器互相连着">
      <Line d="M150 38 L70 112" />
      <Line d="M150 38 L230 112" />
      <Line d="M70 120 L230 120" />
      <Node x={102} y={8} w={96} h={44} label="Mac" main />
      <Node x={14} y={98} w={96} h={44} label="Linux" main />
      <Node x={190} y={98} w={96} h={44} label="Windows" main />
    </svg>
  );
}

/** People and people: one conversation, one machine. */
function PeoplePicture() {
  const people = ["林", "陈", "周"];
  return (
    <svg viewBox="0 0 300 150" role="img" aria-label="三个人在同一个对话里，用同一台机器">
      {people.map((_, i) => <Line key={i} d={across(48, 33 + i * 42, 118, 75)} />)}
      <Line d="M190 75 L206 75" />
      {people.map((label, i) => <Node key={label} x={14} y={16 + i * 42} w={34} h={34} label={label} round />)}
      <Node x={118} y={58} w={72} h={34} label="对话" round />
      <Node x={206} y={45} w={86} h={60} label="你的机器" main />
    </svg>
  );
}

const LINKS = [
  { title: "你和你的机器", text: "手机、网页、Slack、飞书里都能直接用它，文件、浏览器、桌面都在手边", picture: <YouPicture /> },
  { title: "机器和机器", text: "几台机器当一台用：订阅和 skill 互相借，任务交给空着的那台去跑", picture: <MachinesPicture /> },
  { title: "人和人", text: "同事在同一个对话里接着做，用的是同一台机器、同一份上下文", picture: <PeoplePicture /> },
];

// ---- The rest ----

export function Site({ mountDemo, demo }: { mountDemo?: (root: HTMLElement) => void; demo?: { wide: string; phone: string } }) {
  return (
    <div className={css.page}>
      <nav className={css.nav}>
        <div className={`${css.wrap} ${css.navRow}`}>
          <a href="/" className={css.brand} aria-label={NAME.head + NAME.tail}><Themed name="mark" className={css.logo} /><span>{NAME.head}<span className={css.brandTail}>{NAME.tail}</span></span></a>
          {/* The apps, for the device the page is on (data-platform, set before the first paint by site/index.html): on
              Android the app itself; on a computer a card under the word, with the Mac's, Windows' and a code to scan for Android. */}
          <a className={`${css.navLink} ${css.forAndroid}`} href={ANDROID}>下载</a>
          <span className={`${css.menu} ${css.forComputer}`}>
            <button type="button" className={css.navLink}>下载</button>
            <span className={css.menuCard}>
              <a className={css.menuItem} href={MAC}>
                <b>Mac</b><span>Apple 芯片</span><span className={css.menuGo}>下载 →</span>
              </a>
              <a className={css.menuItem} href={WINDOWS}>
                <b>Windows</b><span>x64</span><span className={css.menuGo}>下载 →</span>
              </a>
              <span className={css.menuItem}>
                <img className={css.scanCode} src={BETA ? "/android-beta-qr.svg" : "/android-qr.svg"} alt="下载 Android 版的二维码" width={33} height={33} />
                <span>Android 扫码下载</span>
              </span>
            </span>
          </span>
          <ThemeSwitch />
          <Button href={APP} kind="primary" className={css.navButton}>打开 {NAME.head + NAME.tail}</Button>
        </div>
      </nav>

      <header className={css.hero}>
        <div className={css.grid} /><div className={css.beam} />
        <div className={css.wrap}>
          {/* What it is, in a line: the two halves wrap as wholes on a narrow screen. */}
          <h1 className={css.title}><span>把你的机器</span><span className={css.titleLit}>连到任何地方</span></h1>
          <p className={css.lede}>在手机、网页、Slack 和飞书里，直接用家里或公司的那台机器做事</p>
          <div className={`${css.actions} ${css.heroActions}`}>
            <Button href={APP} kind="primary" large>开始使用</Button>
          </div>
          <div className={css.stage}>
            <div className={css.stageGlow} />
            <div className={css.edge}>
              <Demo {...(mountDemo ? { mount: mountDemo } : {})} {...(demo ? { frame: demo } : {})} />
            </div>
          </div>
        </div>
      </header>

      <section className={css.section}>
        <div className={css.sectionLight} />
        <div className={css.wrap}>
          <div className={`${css.heading} ${css.reveal}`}>
            <h2 className={css.headingTitle}>在哪都是同一台机器</h2>
            <p className={css.headingLede}>数据留在你自己的机器上，设备之间直连，不经过云</p>
          </div>
          <div className={css.links}>
            {LINKS.map((l) => (
              <article key={l.title} className={`${css.link} ${css.reveal}`}>
                <div className={css.linkPicture}>{l.picture}</div>
                <h3 className={css.linkTitle}>{l.title}</h3>
                <p className={css.linkText}>{l.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="start" className={css.section}>
        <div className={css.sectionLight} />
        <div className={css.wrap}>
          <div className={`${css.heading} ${css.reveal}`}>
            <h2 className={css.headingTitle}>一条命令接上一台机器</h2>
            <p className={css.headingLede}>macOS、Linux、Windows 都行，用的是那台机器上已经登录的账号和订阅</p>
          </div>
          <div className={`${css.terminal} ${css.reveal}`}>
            <div className={css.terminalBar}><span className={css.terminalDot} /><span className={css.terminalDot} /><span className={css.terminalDot} /></div>
            <div className={css.terminalBody}>
              <span className={css.prompt}>$ </span>
              <span className={css.typed} style={{ "--chars": `${INSTALL.length}ch`, "--steps": INSTALL.length } as CSSProperties}>{INSTALL}</span>
              <span className={css.output} data-at="1">→ 下载 still.fail station · 加入 workspace「Acme」</span>
              <span className={css.output} data-at="2">→ 注册为登录启动的服务</span>
              <span className={css.output} data-at="3" data-ok>✓ station 已上线</span>
            </div>
          </div>
        </div>
      </section>

      <footer className={css.footer}>
        <div className={`${css.wrap} ${css.footerRow}`}>
          <span className={css.footerFirst}>© 2026 {NAME.head + NAME.tail}</span>
          <a className={css.navLink} href={APP}>网页版</a>
          <a className={css.navLink} href={MAC}>Mac</a>
          <a className={css.navLink} href={WINDOWS}>Windows</a>
          <a className={css.navLink} href={ANDROID}>Android</a>
          <a className={css.navLink} href="https://github.com/AFK-surf/still.fail">GitHub</a>
          {/* The legal pages: static files in web/public (terms.html, privacy.html, trademark.html; en/ their English). */}
          <a className={css.navLink} href="/terms">服务条款</a>
          <a className={css.navLink} href="/privacy">隐私政策</a>
          <a className={css.navLink} href="/trademark">商标</a>
        </div>
      </footer>
    </div>
  );
}
