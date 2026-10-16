// The gallery (`pnpm stories`), built of the app's own parts: its sidebar listing every story (stories.tsx) by group,
// the one picked beside it at the width and in the theme picked, and what takes it there. `?story=<id>&theme=light|dark`
// is one story alone, as the tests (test/browser/stories.mjs) open it; with `&play=1` (the gallery's screen) it takes its
// own steps, with `&device=<id>` it is on that device (devices.ts).
import "../src/styles/index.ts";
import "../src/viewer/whole.ts";
import "@fontsource-variable/inter";
import { StrictMode, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter } from "react-router";
import { Tooltip } from "radix-ui";
import { ToastProvider } from "@stillfail/ui/toast.tsx";
import { extendDemo, mountDemo } from "../src/demo/mount.tsx";
import { Button, Segmented, Select } from "../src/ui.tsx";
import { ArrowUpRight } from "@stillfail/ui/icons.tsx";
import * as shellCss from "../src/styles/shell.css.ts";
import * as nav from "../src/Sidebar.css.ts";
import * as pagesCss from "../src/styles/pages.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { CHANGELOG, PEEK, SENT, readFile } from "./data.ts";
import { DEVICES, device, wear, type Device } from "./devices.ts";
import { play } from "./play.ts";
import { stories, type Story } from "./stories.tsx";

const root = document.getElementById("app")!;
const query = new URLSearchParams(location.search);
const id = query.get("story");
const theme = query.get("theme");
const story = id ? stories.find((s) => s.id === id) : undefined;
if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
const worn = device(query.get("device"));
if (worn) wear(worn);

// What the stories show that the site's demo has none of: files to read and play, and (for those that show it) the
// changelog's news.
extendDemo({
  topic: (t) => (t.topic === "changelog" ? (story?.news ? CHANGELOG : { tabs: [] }) : undefined),
  // A chat's messages with files: the last of a person's with the picture and the files, the agent's next with a file.
  then: (t, value) => {
    if (!(story?.files || story?.peek) || t.topic !== "chat" || !value) return undefined;
    const chat = value as { messages: { authorKind: string; text: string; attachments: unknown[] }[] };
    const person = chat.messages.findLastIndex((m) => m.authorKind === "person");
    // The first of the agent's, not its last: the demo's agent says more as the story runs, and what its last said would
    // move to the next.
    const agent = chat.messages.findIndex((m) => m.authorKind === "agent");
    return {
      ...chat,
      messages: chat.messages.map((m, i) => story.files && i === person ? { ...m, attachments: [SENT.picture, ...SENT.files] }
        : i === agent ? { ...m, ...(story.files ? { attachments: [SENT.files[0]] } : {}), ...(story.peek ? { text: `${m.text}\n\n改在 \`${PEEK.path}\` 里。` } : {}) } : m),
    };
  },
  // A file named in a message, as its card reads it: there, or (`peek: "missing"`) not.
  call: (name, p) => name === "drive.read" ? readFile(String(p.path), Number(p.offset), Number(p.length))
    : name === "file.peek" ? (story?.peek === "missing" ? Promise.reject(new Error("No such file")) : PEEK)
    : name === "drive.place" || name === "changelog.seen" || name === "station.updateNotice" ? null : undefined,
});
// What the tests read: the stories and how each is reached.
(window as unknown as { stories: unknown }).stories = stories.map(({ id, group, title, steps, phone }) => ({ id, group, title, steps: steps ?? [], phone: !!phone }));

if (id) {
  if (!story) root.textContent = `no story ${id}`;
  else if (story.app) { root.style.cssText = "position:fixed;inset:0"; mountDemo(root); }
  else {
    createRoot(root).render(
      <StrictMode>
        <ToastProvider><Tooltip.Provider delayDuration={300}><MemoryRouter>{story.render?.()}</MemoryRouter></Tooltip.Provider></ToastProvider>
      </StrictMode>,
    );
  }
  if (story && query.get("play")) void play(story.steps ?? []);
  // In development (the gallery), what is off outlined in red, as in the app (src/dev/offs.ts); the tests' build measures
  // it itself.
  if (import.meta.env.DEV) void import("../src/dev/offs.ts").then((m) => m.watchOffs());
} else {
  createRoot(root).render(<StrictMode><Tooltip.Provider delayDuration={300}><Gallery /></Tooltip.Provider></StrictMode>);
}

/** Every story in the sidebar, the one picked on the screen and in the theme picked. */
function Gallery() {
  const first = stories.find((s) => s.id === location.hash.slice(1)) ?? stories[0]!;
  const [picked, setPicked] = useState<Story>(first);
  const [look, setLook] = useState<string>("light");
  const [want, setWant] = useState<string>(device(query.get("device"))?.id ?? "mac");
  useEffect(() => { document.documentElement.dataset.theme = look; }, [look]);
  useEffect(() => { history.replaceState(null, "", `#${picked.id}`); }, [picked]);
  useEffect(() => {
    const follow = () => { const s = stories.find((s) => s.id === location.hash.slice(1)); if (s) setPicked(s); };
    addEventListener("hashchange", follow);
    return () => removeEventListener("hashchange", follow);
  }, []);
  const groups = [...new Set(stories.map((s) => s.group))];
  // A phone's story on a phone (the first) when a Mac is picked.
  const on = device(want)!.mac && picked.phone ? DEVICES.find((d) => d.safe && d.cutout)! : device(want)!;
  const src = `?story=${picked.id}&theme=${look}&device=${on.id}&play=1`;
  return (
    <div className={shellCss.shell}>
      <nav className={nav.sidebar} aria-label="stories">
        <div className={nav.navScroll}>
          {groups.map((g) => (
            <section key={g}>
              <div className={nav.navHeading}>{g}</div>
              {stories.filter((s) => s.group === g).map((s) => (
                <a key={s.id} href={`#${s.id}`} className={nav.navRow} aria-current={s === picked ? "page" : undefined}
                  onClick={(e) => { e.preventDefault(); setPicked(s); }}>
                  <span className={nav.navText}>{s.title}</span>
                </a>
              ))}
            </section>
          ))}
        </div>
      </nav>
      <main className={shellCss.main}>
        <div className={pagesCss.page} style={{ display: "flex", flexDirection: "column", gap: 12, paddingBottom: 24 }}>
          <header className={pagesCss.pageHead} style={{ marginBottom: 0, alignItems: "center" }}>
            <div style={{ display: "grid", gap: 2, minWidth: 0 }}>
              <h1 style={{ margin: 0 }}>{picked.title}</h1>
              <span style={{ fontSize: vars.textMeta, color: vars.muted }}>{picked.group}</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 8, flex: "none" }}>
              <Segmented label="主题" value={look} onChange={setLook} options={[{ value: "light", label: "浅色" }, { value: "dark", label: "深色" }]} />
              <div style={{ width: 220 }}><Select label="设备" value={on.id} onChange={setWant} options={DEVICES.map((d) => ({ value: d.id, label: d.label, group: d.group }))} /></div>
              <Button variant="ghost" icon={ArrowUpRight} onClick={() => window.open(src, "_blank")}>单独打开</Button>
            </div>
          </header>
          <Screen on={on}>
            <iframe key={src} title={picked.title} src={src} style={{ width: "100%", height: "100%", border: 0, display: "block" }} />
          </Screen>
        </div>
      </main>
    </div>
  );
}

// A device's screen, zoomed out to fit what room there is (never in), with what the system draws over the page: the
// Mac window's buttons; a phone's status bar around its cutout, and its home indicator or navigation buttons.
function Screen({ on, children }: { on: Device; children: ReactNode }) {
  const room = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState(1);
  // The ground the screen stands on, to paint its corners in (the first painted one under it).
  const [ground, setGround] = useState("transparent");
  // Read after a frame: the theme is put on the page after this is drawn.
  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      for (let at: Element | null = room.current; at; at = at.parentElement) {
        const bg = getComputedStyle(at).backgroundColor;
        if (bg && bg !== "transparent" && !/rgba\(.*, 0\)$/.test(bg)) { setGround(bg); break; }
      }
    });
    return () => cancelAnimationFrame(frame);
  });
  useLayoutEffect(() => {
    const el = room.current!;
    const follow = () => setFit(Math.min(1, el.clientWidth / on.width, el.clientHeight / on.height));
    follow();
    const watch = new ResizeObserver(follow);
    watch.observe(el);
    return () => watch.disconnect();
  }, [on]);
  return (
    <div ref={room} style={{ flex: 1, minHeight: 0, display: "flex", justifyContent: "center", alignItems: "flex-start" }}>
      <div style={{ flex: "none", zoom: fit }}>
        <div style={{
          position: "relative", width: on.width, height: on.height,
          background: vars.canvas,
        }}>
          {children}
          <div aria-hidden style={{ position: "absolute", inset: 0, pointerEvents: "none", color: vars.text }}>
            <Corners radius={on.radius} ground={ground} />
            <div style={{ position: "absolute", inset: 0, borderRadius: on.radius, boxShadow: `inset 0 0 0 1px ${vars.lineStrong}` }} />
            {on.mac === "window" && <Lights />}
            {on.safe && <StatusBar on={on} />}
            {on.foot === "indicator" && (
              <div style={{ position: "absolute", left: "50%", bottom: on.os === "ios" ? 8 : 9, transform: "translateX(-50%)", width: on.os === "ios" ? 134 : 108, height: on.os === "ios" ? 5 : 4, borderRadius: 3, background: "currentColor" }} />
            )}
            {on.foot === "buttons" && <NavButtons height={on.safe!.bottom} />}
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * The screen's corners, painted over it in the ground it stands on (its edge a line drawn inside, over them) rather than cut: clipped round, an iframe has Chrome
 * draw the phone bar's frosted, clipped glass as a box.
 */
function Corners({ radius, ground }: { radius: number; ground: string }) {
  if (!radius) return null;
  const at = { "top left": { top: 0, left: 0 }, "top right": { top: 0, right: 0 }, "bottom left": { bottom: 0, left: 0 }, "bottom right": { bottom: 0, right: 0 } };
  return (
    <>
      {Object.entries(at).map(([corner, place]) => {
        const [v, h] = corner.split(" ");
        const centre = `${h === "left" ? "100%" : "0"} ${v === "top" ? "100%" : "0"}`;
        return <span key={corner} style={{ position: "absolute", ...place, width: radius, height: radius, background: `radial-gradient(circle at ${centre}, transparent ${radius - 0.5}px, ${ground} ${radius}px)` }} />;
      })}
    </>
  );
}

/** The Mac window's three buttons, where the app has macOS put them (12 across, 8 apart, from 16, 15). */
function Lights() {
  return (
    <div style={{ position: "absolute", left: 16, top: 15, display: "flex", gap: 8 }}>
      {["#ff5f57", "#febc2e", "#28c840"].map((c) => <span key={c} style={{ width: 12, height: 12, borderRadius: "50%", background: c, boxShadow: "inset 0 0 0 0.5px rgb(0 0 0 / .12)" }} />)}
    </div>
  );
}

/** A phone's status bar: the time, the cutout, signal, Wi-Fi and battery, in the top of its safe area. */
function StatusBar({ on }: { on: Device }) {
  const c = on.cutout;
  const ios = on.os === "ios";
  // iOS centres the bar on the cutout (or in 20 on a phone without one); Android's runs along the top.
  const band = c ? c.top * 2 + c.height : on.safe!.top;
  return (
    <>
      {c && (
        <div style={{
          position: "absolute", left: "50%", top: c.top, transform: "translateX(-50%)", width: c.width, height: c.height, background: "#000",
          borderRadius: c.kind === "notch" ? "0 0 20px 20px" : c.height / 2,
        }} />
      )}
      <div style={{
        position: "absolute", left: 0, right: 0, top: 0, height: ios ? band : on.safe!.top, display: "flex", alignItems: "center",
        justifyContent: "space-between", padding: ios ? `0 ${c ? 32 : 12}px` : "0 20px", boxSizing: "border-box",
        fontSize: ios ? 16 : 14, fontWeight: 600, fontFamily: "-apple-system, system-ui, sans-serif", letterSpacing: "-.01em",
      }}>
        <span style={{ width: c ? (on.width - c.width) / 2 - 40 : undefined, textAlign: ios && c ? "center" : "left" }}>9:41</span>
        <span style={{ display: "flex", alignItems: "center", gap: 5, width: c ? (on.width - c.width) / 2 - 40 : undefined, justifyContent: ios && c ? "center" : "flex-end" }}>
          <span style={{ display: "flex", alignItems: "flex-end", gap: 1.5, height: 11 }}>
            {[4, 6, 8, 11].map((h) => <span key={h} style={{ width: 3, height: h, borderRadius: 1, background: "currentColor" }} />)}
          </span>
          <span style={{ width: 15, height: 11, background: "currentColor", clipPath: "polygon(50% 100%, 0 30%, 15% 15%, 50% 0, 85% 15%, 100% 30%)" }} />
          <span style={{ display: "flex", alignItems: "center", gap: 1 }}>
            <span style={{ width: 22, height: 11, borderRadius: 3.5, boxShadow: "inset 0 0 0 1px currentColor", padding: 2, boxSizing: "border-box", display: "flex" }}>
              <span style={{ width: "80%", borderRadius: 1.5, background: "currentColor" }} />
            </span>
            <span style={{ width: 1.5, height: 4, borderRadius: 1, background: "currentColor", opacity: .5 }} />
          </span>
        </span>
      </div>
    </>
  );
}

/** Android's three navigation buttons: back, home, recents. */
function NavButtons({ height }: { height: number }) {
  return (
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height, display: "flex", alignItems: "center", justifyContent: "space-around", padding: "0 40px" }}>
      <span style={{ width: 0, height: 0, borderTop: "7px solid transparent", borderBottom: "7px solid transparent", borderRight: "12px solid currentColor", opacity: .8 }} />
      <span style={{ width: 14, height: 14, borderRadius: "50%", boxShadow: "inset 0 0 0 2px currentColor", opacity: .8 }} />
      <span style={{ width: 12, height: 12, borderRadius: 2, boxShadow: "inset 0 0 0 2px currentColor", opacity: .8 }} />
    </div>
  );
}
