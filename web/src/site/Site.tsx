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

// ---- The first screen's picture: where you are, the machine, and the machines beside it ----

/** Where you reach the machine from, down the picture's left. */
const ENDS = ["手机", "网页", "桌面 app", "Slack", "飞书"];
const END_Y = (i: number) => 52 + i * 76;
/** The machine: a card in the middle, its name, how it is, what of it you reach. */
const MACHINE = { x: 220, y: 150, w: 196, h: 140 };
/** The other machines of the workspace, to its right. */
const OTHERS = [{ label: "Mini", sub: "macOS", y: 54 }, { label: "Linux 服务器", sub: "x64", y: 328 }];

/** From (x1, y1) to (x2, y2), leaving and arriving level. */
const across = (x1: number, y1: number, x2: number, y2: number) => {
  const mid = (x1 + x2) / 2;
  return `M${x1} ${y1} C${mid} ${y1} ${mid} ${y2} ${x2} ${y2}`;
};

/** A place you reach the machine from: a pill with its name. */
const End = ({ x, y, w, label }: { x: number; y: number; w: number; label: string }) => (
  <g className={css.end}>
    <rect x={x} y={y} width={w} height={34} rx={17} />
    <text x={x + w / 2} y={y + 17} dominantBaseline="central" textAnchor="middle">{label}</text>
  </g>
);

/** A line and, now and then, a dot going along it (not where less motion is asked for: site.css.ts). */
const Wire = ({ d, at }: { d: string; at: number }) => (
  <g>
    <path className={css.wire} d={d} />
    <circle className={css.pulse} r={3}><animateMotion dur="3.2s" begin={`${at * 0.55}s`} repeatCount="indefinite" path={d} /></circle>
  </g>
);

/** The machine, its top left at (x, y): its name, how it is, what of it you reach. */
function Machine({ x, y }: { x: number; y: number }) {
  return (
    <g className={css.machine}>
      <rect x={x} y={y} width={MACHINE.w} height={MACHINE.h} rx={16} />
      <circle className={css.online} cx={x + 24} cy={y + 30} r={4} />
      <text className={css.machineName} x={x + 38} y={y + 30} dominantBaseline="central">Studio</text>
      <text className={css.machineSub} x={x + 20} y={y + 58} dominantBaseline="central">你的 Mac · 在线</text>
      {["文件", "浏览器", "终端"].map((t, i) => (
        <g key={t} className={css.machinePart}>
          <rect x={x + 20 + i * 54} y={y + 86} width={48} height={30} rx={8} />
          <text x={x + 44 + i * 54} y={y + 101} dominantBaseline="central" textAnchor="middle">{t}</text>
        </g>
      ))}
    </g>
  );
}

/** Another machine of the workspace. */
const Other = ({ x, y, w, label }: { x: number; y: number; w: number; label: string }) => (
  <g className={css.other}>
    <rect x={x} y={y} width={w} height={38} rx={10} />
    <text x={x + w / 2} y={y + 19} dominantBaseline="central" textAnchor="middle">{label}</text>
  </g>
);

const LABEL = "手机、网页、桌面 app、Slack、飞书都连到你的机器，它和另外两台机器也连着";

/** Wide: where you are down the left, the machine in the middle, the other machines on the right. */
function WidePicture() {
  const into = MACHINE.y + MACHINE.h / 2;
  return (
    <svg className={`${css.picture} ${css.pictureWide}`} viewBox="0 0 560 420" role="img" aria-label={LABEL}>
      {ENDS.map((_, i) => <Wire key={i} at={i} d={across(112, END_Y(i), MACHINE.x, into - 36 + i * 18)} />)}
      {OTHERS.map((o) => <path key={o.label} className={css.wireQuiet} d={across(MACHINE.x + MACHINE.w, into, 440, o.y + 19)} />)}
      {ENDS.map((label, i) => <End key={label} x={0} y={END_Y(i) - 17} w={112} label={label} />)}
      <Machine x={MACHINE.x} y={MACHINE.y} />
      {OTHERS.map((o) => <Other key={o.label} x={440} y={o.y} w={120} label={o.label} />)}
    </svg>
  );
}

/** Down: on a narrow screen, where you are along the top, the machine under it, the other machines below. */
const DOWN_ENDS = [{ w: 56 }, { w: 56 }, { w: 80 }, { w: 64 }, { w: 52 }];
function NarrowPicture() {
  const left = (i: number) => DOWN_ENDS.slice(0, i).reduce((x, e) => x + e.w + 8, 0);
  const mx = (340 - MACHINE.w) / 2, my = 104;
  return (
    <svg className={`${css.picture} ${css.pictureNarrow}`} viewBox="0 0 340 340" role="img" aria-label={LABEL}>
      {DOWN_ENDS.map((e, i) => (
        <Wire key={i} at={i} d={`M${left(i) + e.w / 2} 34 C${left(i) + e.w / 2} 70 ${mx + 38 + i * 30} 70 ${mx + 38 + i * 30} ${my}`} />
      ))}
      <path className={css.wireQuiet} d={`M${mx + 60} ${my + MACHINE.h} C${mx + 60} ${my + MACHINE.h + 30} 60 ${my + MACHINE.h + 20} 60 300`} />
      <path className={css.wireQuiet} d={`M${mx + MACHINE.w - 60} ${my + MACHINE.h} C${mx + MACHINE.w - 60} ${my + MACHINE.h + 30} 275 ${my + MACHINE.h + 20} 275 300`} />
      {DOWN_ENDS.map((e, i) => <End key={i} x={left(i)} y={0} w={e.w} label={ENDS[i]!} />)}
      <Machine x={mx} y={my} />
      <Other x={0} y={300} w={120} label="Mini" />
      <Other x={210} y={300} w={130} label="Linux 服务器" />
    </svg>
  );
}

function ConnectPicture() {
  return <div className={css.pictureBox}><WidePicture /><NarrowPicture /></div>;
}

/** What it connects, read down the page. */
const LINKS = [
  { title: "你和你的机器", text: "在手机、网页、桌面 app、Slack 和飞书里直接用它，就像坐在它面前", parts: ["文件", "浏览器和桌面", "命令行登录", "后台任务"] },
  { title: "机器和机器", text: "几台机器当一台用：订阅和 skill 互相借，任务交给空着的那台去跑", parts: ["借用订阅", "跨机器任务", "端口转发"] },
  { title: "人和人", text: "同事在同一个对话里接着做，用的是同一台机器、同一份上下文", parts: ["Slack", "飞书", "still.fail 对话"] },
];

/** What it promises about where things are. */
const PROMISES = [
  { title: "数据在你的机器上", text: "对话、文件和记录存在你自己的机器上，云端只管账号和中继" },
  { title: "设备之间直连", text: "手机、电脑和机器之间点对点连接，连不上时经加密的中继转发" },
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
        <div className={`${css.wrap} ${css.heroRow}`}>
          <div className={css.heroWords}>
            <h1 className={css.title}>把你的机器<br />连到任何地方</h1>
            <p className={css.lede}>在手机、网页、Slack 和飞书里，直接用家里或公司的那台机器做事</p>
            <div className={css.heroActions}>
              <Button href={APP} kind="primary" large>开始使用</Button>
              <span className={css.heroNote}>机器支持 macOS、Linux、Windows</span>
            </div>
          </div>
          <ConnectPicture />
        </div>
      </header>

      <section className={css.stageSection}>
        <div className={css.wrap}>
          <div className={css.edge}>
            <Demo {...(mountDemo ? { mount: mountDemo } : {})} {...(demo ? { frame: demo } : {})} />
          </div>
          <p className={css.caption}>真的 still.fail，跑在示例数据上，可以直接点</p>
        </div>
      </section>

      <section className={css.section}>
        <div className={css.wrap}>
          <h2 className={css.headingTitle}>连起你、你的机器和你的同事</h2>
          <ol className={css.links}>
            {LINKS.map((l, i) => (
              <li key={l.title} className={css.link}>
                <span className={css.linkNumber}>{String(i + 1).padStart(2, "0")}</span>
                <h3 className={css.linkTitle}>{l.title}</h3>
                <p className={css.linkText}>{l.text}</p>
                <ul className={css.parts}>{l.parts.map((p) => <li key={p}>{p}</li>)}</ul>
              </li>
            ))}
          </ol>
        </div>
      </section>

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

      <section id="start" className={css.section}>
        <div className={`${css.wrap} ${css.install}`}>
          <div>
            <h2 className={css.headingTitle}><span className={css.phrase}>一条命令</span><span className={css.phrase}>接上一台机器</span></h2>
            <p className={css.headingLede}>在要连的机器上运行，用的是它上面已经登录的账号和订阅</p>
          </div>
          <div className={css.terminal}>
            <div className={css.terminalBody}>
              <span className={css.command}><span className={css.prompt}>$ </span><span className={css.typed} style={{ "--chars": `${INSTALL.length}ch`, "--steps": INSTALL.length } as CSSProperties}>{INSTALL}</span></span>
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
