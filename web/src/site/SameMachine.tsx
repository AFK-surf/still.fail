// The first idea: wherever it is opened, it is the same machine. The real app runs in a frame that, as the page is
// scrolled, goes from a computer's window to a phone (the app itself turning into the phone's), then to a Slack
// thread and a Feishu group: other places, the same machine at work behind them.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { CHEN, LIN } from "../demo/fixtures.ts";
import * as css from "./site.css.ts";
import { APP, Button, Demo, Promises, type DemoProps } from "./Site.tsx";

/** Where it is opened, in the order the page goes through them. */
const PLACES = [
  { key: "desktop", label: "在电脑上", note: "桌面 app 或网页" },
  { key: "phone", label: "在手机上", note: "Android app，出门接着看" },
  { key: "slack", label: "在 Slack 里", note: "在 thread 里 @ 它" },
  { key: "feishu", label: "在飞书里", note: "在群里直接说" },
] as const;
type Place = (typeof PLACES)[number]["key"];

/** The frame's size and corners at a place, for the stage it is drawn in. */
function shapeOf(place: Place, stage: { w: number; h: number }, narrow: boolean): { w: number; h: number; r: number } {
  if (narrow) return { w: Math.min(390, stage.w - 32), h: Math.min(720, stage.h), r: place === "phone" ? 36 : 16 };
  if (place === "desktop") return { w: Math.min(1112, stage.w), h: Math.min(660, stage.h), r: 20 };
  if (place === "phone") return { w: 390, h: Math.min(780, stage.h), r: 44 };
  return { w: Math.min(880, stage.w), h: Math.min(600, stage.h), r: 16 };
}

const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const ease = (t: number) => t * t * (3 - 2 * t);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Which places each layer of the frame shows: the app for the computer and the phone, a mock for each of the rest. */
const LAYERS: { places: Place[]; render: (props: DemoProps) => ReactNode }[] = [
  { places: ["desktop", "phone"], render: (p) => <Demo v="1" className={css.sceneDemo} {...(p.mountDemo ? { mount: p.mountDemo } : {})} {...(p.demo ? { frame: p.demo } : {})} /> },
  { places: ["slack"], render: () => <SlackThread /> },
  { places: ["feishu"], render: () => <FeishuGroup /> },
];

export function SameMachine(props: DemoProps) {
  const scene = useRef<HTMLElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const frame = useRef<HTMLDivElement>(null);
  const clip = useRef<HTMLDivElement>(null);
  const layers = useRef<(HTMLDivElement | null)[]>([]);
  const [at, setAt] = useState<Place>("desktop");

  useEffect(() => {
    const el = scene.current, room = stage.current, box = frame.current, inner = clip.current;
    if (!el || !room || !box || !inner) return;
    let asked = 0;
    // Where the page is in the scene says where between two places the frame is: it holds at each, and goes from one
    // to the next over the middle of the way between them.
    const draw = () => {
      asked = 0;
      if (el.offsetParent === null) return;
      const narrow = innerWidth <= 860;
      const places = PLACES.filter((p) => !narrow || p.key !== "desktop").map((p) => p.key);
      const size = { w: room.clientWidth, h: room.clientHeight };
      const span = el.offsetHeight - innerHeight;
      const x = clamp(-el.getBoundingClientRect().top / Math.max(1, span)) * (places.length - 1);
      const i = Math.min(Math.floor(x), places.length - 2);
      const pos = i + ease(clamp((x - i - 0.3) / 0.4));
      const a = shapeOf(places[i]!, size, narrow), b = shapeOf(places[i + 1]!, size, narrow), t = pos - i;
      box.style.width = `${lerp(a.w, b.w, t)}px`;
      box.style.height = `${lerp(a.h, b.h, t)}px`;
      // Rounded by its shadow's box outside and a clip inside (a rounded overflow would draw the phone app's frosted
      // bar as a plain rectangle: site.css.ts demo).
      const r = lerp(a.r, b.r, t);
      box.style.borderRadius = `${r}px`;
      inner.style.clipPath = `inset(0 round ${r}px)`;
      LAYERS.forEach((layer, k) => {
        const own = layer.places.map((p) => places.indexOf(p)).filter((n) => n >= 0);
        const lo = Math.min(...own), hi = Math.max(...own);
        const seen = own.length === 0 ? 0 : pos < lo ? clamp(1 - (lo - pos) * 2) : pos > hi ? clamp(1 - (pos - hi) * 2) : 1;
        const node = layers.current[k];
        if (node) { node.style.opacity = `${seen}`; node.style.visibility = seen > 0 ? "visible" : "hidden"; }
      });
      setAt(places[Math.round(pos)]!);
    };
    const ask = () => { if (!asked) asked = requestAnimationFrame(draw); };
    draw();
    addEventListener("scroll", ask, { passive: true });
    addEventListener("resize", ask);
    return () => { removeEventListener("scroll", ask); removeEventListener("resize", ask); cancelAnimationFrame(asked); };
  }, []);

  return (
    <>
      <header className={css.sameHero}>
        <div className={css.wrap}>
          <h1 className={css.sameTitle}><span className={css.phrase}>在哪打开，</span><span className={css.phrase}>都是同一台机器</span></h1>
          <p className={css.sameLede}>电脑、手机、Slack、飞书，打开哪个都是你自己的那台机器，接着做手上的事</p>
          <div className={css.sameActions}><Button href={APP} kind="primary" large>开始使用</Button></div>
        </div>
      </header>

      <section className={css.scene} ref={scene} style={{ height: `${PLACES.length * 100}vh` }}>
        <div className={css.sceneStick}>
          <div className={`${css.wrap} ${css.sceneBar}`}>
            <ol className={css.places}>
              {PLACES.map((p) => (
                <li key={p.key} className={css.place} data-place={p.key} data-at={at === p.key ? "" : undefined}>
                  <b>{p.label}</b><span>{p.note}</span>
                </li>
              ))}
            </ol>
            <span className={css.sameMachine}><i className={css.onlineDot} />始终是 Studio · 你的 Mac</span>
          </div>
          <div className={css.sceneRoom} ref={stage}>
            <div className={css.sceneFrame} ref={frame}>
              <div className={css.sceneClip} ref={clip}>
                {LAYERS.map((layer, k) => (
                  <div key={k} className={css.sceneLayer} ref={(node) => { layers.current[k] = node; }}>{layer.render(props)}</div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      <Promises />
    </>
  );
}

// ---- Slack and Feishu, as they look: other conversations, the same machine at work behind them ----

const BUDDY = "/mark.svg";

function SlackThread() {
  const said = [
    { who: LIN.name, face: LIN.shown?.picture, time: "10:21", text: <><span className={css.slackMention}>@still.fail</span> 登录页在手机上显示不对，帮我修一下</> },
    { who: "still.fail", face: BUDDY, app: true, time: "10:24", text: <>登录按钮在手机上写死了 320px 宽，超出了屏幕。改成撑满容器，375px 宽下截图看过了，分支 <code>fix/login-button</code></> },
    { who: LIN.name, face: LIN.shown?.picture, time: "10:30", text: <>表单看着还是有点偏</> },
    { who: "still.fail", face: BUDDY, app: true, time: "10:32", text: <>表单左右留白是 8px 和 24px，改成各 16px，现在居中了，测试都过了</> },
  ];
  return (
    <div className={css.slack}>
      <aside className={css.slackSide}>
        <b className={css.slackTeam}>Acme</b>
        <span># general</span>
        <span data-on=""># frontend</span>
        <span># releases</span>
      </aside>
      <div className={css.slackMain}>
        <div className={css.slackHead}><b>Thread</b><span># frontend</span></div>
        <div className={css.slackList}>
          {said.map((m, i) => (
            <div key={i} className={css.slackMessage}>
              <img src={m.face} alt="" />
              <div>
                <div className={css.slackWho}><b>{m.who}</b>{m.app && <span className={css.slackApp}>APP</span>}<time>{m.time}</time></div>
                <p>{m.text}</p>
              </div>
            </div>
          ))}
        </div>
        <div className={css.slackCompose}>回复…</div>
      </div>
    </div>
  );
}

function FeishuGroup() {
  const said = [
    { who: CHEN.name, face: CHEN.shown?.picture, text: <>@still.fail 这周的依赖升级跑一下</> },
    { who: "still.fail", face: BUDDY, bot: true, text: <>其余 23 个包都升好了，测试通过。React Router 8 也升好了：codemod 改了 14 个路由文件，312 个测试全过</> },
    { who: CHEN.name, face: CHEN.shown?.picture, text: <>好，发 PR 吧</> },
    { who: "still.fail", face: BUDDY, bot: true, text: <>PR 在 <code>chore/deps-2026-w40</code></> },
  ];
  return (
    <div className={css.feishu}>
      <div className={css.feishuHead}><b>前端小组</b><span>3 人</span></div>
      <div className={css.feishuList}>
        {said.map((m, i) => (
          <div key={i} className={css.feishuMessage}>
            <img src={m.face} alt="" />
            <div>
              <div className={css.feishuWho}>{m.who}{m.bot && <span className={css.feishuBot}>机器人</span>}</div>
              <p className={css.feishuBubble}>{m.text}</p>
            </div>
          </div>
        ))}
      </div>
      <div className={css.feishuCompose}>发送给 前端小组</div>
    </div>
  );
}
