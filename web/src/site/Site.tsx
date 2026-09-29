// The official site: one page, rendered to HTML when the site is built (prerender.tsx) and taken over in the browser
// (main.tsx), where the real app runs in its demo box (demo/). Few words; what moves is CSS (site.css.ts). Nothing here
// reads the window while it renders.
import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import * as css from "./site.css.ts";
import { ThemeSwitch } from "./ThemeSwitch.tsx";

const APP = "https://ember.3720.org";
const INSTALL = "curl -fsSL https://ember.3720.org/install.sh | sh -s -- <token>";

/** A picture of web/public and its -dark twin: the one for the page's theme shows (site.css.ts), with no script. */
function Themed({ name, className, alt = "", life }: { name: string; className?: string; alt?: string; life?: string }) {
  return (
    <>
      <span className={css.lightOnly}><img className={className} src={`/${name}.svg`} alt={alt} data-life={life} /></span>
      <span className={css.darkOnly}><img className={className} src={`/${name}-dark.svg`} alt={alt} data-life={life} /></span>
    </>
  );
}

function Button({ href, kind, large, children, className }: { href: string; kind: "primary" | "ghost"; large?: boolean; children: ReactNode; className?: string }) {
  return <a className={`${css.button} ${className ?? ""}`} data-kind={kind} data-size={large ? "large" : undefined} href={href}>{children}</a>;
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

/** A domain's dot, with what the domain says in Chinese hanging off it on a line: above the first, below the second. */
function Dot({ say, up }: { say: string; up?: boolean }) {
  return <span className={css.dot}>.<span className={css.dotNote} data-up={up ? "" : undefined} aria-hidden><span className={css.dotLine} /><span className={css.dotSay}>{say}</span></span></span>;
}

// ---- The mesh ----

interface Point { x: number; y: number }
interface Station extends Point { name: string }
interface Device extends Point { name: string; links: number[] }

/** One layout of the mesh: where its stations, devices and ember cloud stand, in a drawing of `size`. */
interface Layout { size: [number, number]; box: [number, number]; cloud: Point; stations: Station[]; devices: Device[] }

const WIDE: Layout = {
  size: [1000, 540], box: [150, 56], cloud: { x: 500, y: 34 },
  stations: [
    { name: "Mac Studio", x: 500, y: 250 },
    { name: "MacBook", x: 300, y: 420 },
    { name: "Linux 服务器", x: 700, y: 420 },
  ],
  devices: [
    { name: "Slack", x: 110, y: 200, links: [0, 1] },
    { name: "网页", x: 110, y: 470, links: [1] },
    { name: "桌面端", x: 890, y: 200, links: [0, 2] },
    { name: "手机", x: 890, y: 470, links: [2, 0] },
  ],
};
const TALL: Layout = {
  size: [420, 800], box: [124, 52], cloud: { x: 210, y: 30 },
  stations: [
    { name: "Mac Studio", x: 210, y: 330 },
    { name: "MacBook", x: 96, y: 520 },
    { name: "Linux 服务器", x: 324, y: 520 },
  ],
  devices: [
    { name: "Slack", x: 76, y: 170, links: [0, 1] },
    { name: "桌面端", x: 344, y: 170, links: [0, 2] },
    { name: "网页", x: 76, y: 730, links: [1] },
    { name: "手机", x: 344, y: 730, links: [2] },
  ],
};

/**
 * The mesh: stations (each a machine of yours, its agents on it) linked to each other, and the devices people talk
 * from linked straight to them; ember cloud off to the side, for accounts only, with no work passing through it.
 */
function Mesh({ tall }: { tall?: boolean }) {
  const { size: [W, H], box: [bw, bh], cloud, stations, devices } = tall ? TALL : WIDE;
  const id = tall ? "tall" : "wide";
  const line = (a: Point, b: Point) => `M ${a.x} ${a.y} L ${b.x} ${b.y}`;
  const mesh = [[0, 1], [1, 2], [2, 0]].map(([a, b]) => line(stations[a!]!, stations[b!]!));
  const reach = devices.flatMap((d) => d.links.map((s) => line(d, stations[s]!)));
  const accounts = stations.map((s) => line({ x: cloud.x, y: cloud.y + bh / 2 }, s));
  return (
    <svg className={`${css.network} ${css.reveal}`} data-shape={id} viewBox={`0 0 ${W} ${H}`} role="img"
      aria-label="几台 station 连成一张网，Slack、网页、桌面端和手机点对点直连它们；ember cloud 只管账号">
      {accounts.map((d, i) => <path key={`c${i}`} className={css.wire} data-kind="cloud" d={d} />)}
      {reach.map((d, i) => <path key={`r${i}`} id={`${id}-reach-${i}`} className={css.wire} d={d} />)}
      {mesh.map((d, i) => <path key={`m${i}`} id={`${id}-mesh-${i}`} className={css.wire} data-kind="mesh" d={d} />)}
      {/* What flows: messages from the devices to the stations and back, and work between the stations. */}
      {reach.map((_, i) => (
        <circle key={`pr${i}`} className={css.packet} r="4">
          <animateMotion dur={`${2.2 + (i % 3) * 0.6}s`} begin={`${(i * 0.41) % 2}s`} repeatCount="indefinite" keyPoints={i % 2 ? "1;0" : "0;1"} keyTimes="0;1" calcMode="linear">
            <mpath href={`#${id}-reach-${i}`} />
          </animateMotion>
        </circle>
      ))}
      {mesh.map((_, i) => (
        <circle key={`pm${i}`} className={css.packet} data-kind="mesh" r="5">
          <animateMotion dur="3.2s" begin={`${i * 1.1}s`} repeatCount="indefinite" keyPoints={i % 2 ? "1;0" : "0;1"} keyTimes="0;1" calcMode="linear">
            <mpath href={`#${id}-mesh-${i}`} />
          </animateMotion>
        </circle>
      ))}
      <g transform={`translate(${cloud.x - 90} ${cloud.y - bh / 2})`}>
        <rect className={css.node} data-kind="cloud" width="180" height={bh} rx="14" />
        <text className={css.nodeLabel} x="90" y={bh / 2 + 5} textAnchor="middle">ember cloud</text>
      </g>
      {devices.map((d) => (
        <g key={d.name} transform={`translate(${d.x - bw / 2} ${d.y - bh / 2})`}>
          <rect className={css.node} width={bw} height={bh} rx="14" />
          <text className={css.nodeLabel} x={bw / 2} y={bh / 2 + 5} textAnchor="middle">{d.name}</text>
        </g>
      ))}
      {stations.map((s, i) => (
        <g key={s.name}>
          <circle className={css.ring} cx={s.x} cy={s.y} r="52" style={{ animationDelay: `${i * 0.9}s` }} />
          <circle className={css.hub} cx={s.x} cy={s.y} r="50" />
          <g className={css.lightOnly}><image href="/mark.svg" x={s.x - 30} y={s.y - 34} width="60" height="60" /></g>
          <g className={css.darkOnly}><image href="/mark-dark.svg" x={s.x - 30} y={s.y - 34} width="60" height="60" /></g>
          <text className={css.nodeLabel} x={s.x} y={s.y + 76} textAnchor="middle">{s.name}</text>
        </g>
      ))}
    </svg>
  );
}

// ---- The rest ----



export function Site({ mountDemo, demo }: { mountDemo?: (root: HTMLElement) => void; demo?: { wide: string; phone: string } }) {
  return (
    <div className={css.page}>
      <nav className={css.nav}>
        <div className={`${css.wrap} ${css.navRow}`}>
          <a href="/"><Themed name="lockup" className={css.logo} alt="ember" /></a>
          <div className={css.navLinks}>
            <a className={css.navLink} href="#mesh">mesh</a>
            <a className={css.navLink} href="#start">安装</a>
          </div>
          <ThemeSwitch />
          <Button href={APP} kind="primary" className={css.navButton}>打开 ember</Button>
        </div>
      </nav>

      <header className={css.hero}>
        <div className={css.grid} /><div className={css.beam} />
        <div className={css.wrap}>
          {/* The two domains, what the user keeps saying to the agent: the one the page was opened on is lit (data-host, set
              before the first paint by site/index.html; still.fail when neither). */}
          <h1 className={css.title}>
            <span className={css.titleDomain} data-domain="still.fail">still<Dot say="还是不行" up />fail</span><br />
            <span className={css.titleDomain} data-domain="youdid.wtf">youdid<Dot say="干的什么 jb" />wtf</span>
          </h1>
          <div className={`${css.actions} ${css.heroActions}`}>
            <Button href={APP} kind="primary" large>免费开始</Button>
            <Button href="#start" kind="ghost" large>安装 station</Button>
          </div>
          <div className={css.stage}>
            <div className={css.stageGlow} />
            <div className={css.edge}>
              <Demo {...(mountDemo ? { mount: mountDemo } : {})} {...(demo ? { frame: demo } : {})} />
            </div>
          </div>
        </div>
      </header>

      <section id="mesh" className={css.section}>
        <div className={css.sectionLight} />
        <div className={css.wrap}>
          <Mesh />
          <Mesh tall />
        </div>
      </section>

      <section id="start" className={css.section}>
        <div className={css.sectionLight} />
        <div className={css.wrap}>
          <h2 className={`${css.sectionTitle} ${css.reveal}`}>一行命令<span className={css.faint}>机器就上岗</span></h2>
          <div className={`${css.terminal} ${css.reveal}`}>
            <div className={css.terminalBar}><span className={css.terminalDot} /><span className={css.terminalDot} /><span className={css.terminalDot} /></div>
            <div className={css.terminalBody}>
              <span className={css.prompt}>$ </span>
              <span className={css.typed} style={{ "--chars": `${INSTALL.length}ch`, "--steps": INSTALL.length } as CSSProperties}>{INSTALL}</span>
              <span className={css.output} data-at="1">→ 下载 ember station · 加入 workspace「Acme」</span>
              <span className={css.output} data-at="2">→ 注册为登录启动的服务</span>
              <span className={css.output} data-at="3" data-ok>✓ station 已上线，去聊天里 @ 它吧</span>
            </div>
          </div>
        </div>
      </section>

      <footer className={css.footer}>
        <div className={`${css.wrap} ${css.footerRow}`}>
          <span className={css.footerFirst}>© 2026 ember</span>
          <a className={css.navLink} href={APP}>网页版</a>
          <a className={css.navLink} href="https://github.com/zzj3720/ember">GitHub</a>
        </div>
      </footer>
    </div>
  );
}
