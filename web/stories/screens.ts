// A station's screens for the stories (docs/remote-screens.md): the demo station's list (the core's `screens` topic,
// as client/core-ts/src/screens.ts puts it together), and its views (`screen.view`) in each phase the core says, the
// live ones drawing real frames made here (a desktop with a browser asking to sign in: JPEG, or H.264 where the browser
// encodes it), so the canvas is drawn as a station's would be. 只看/控制 switches as the core would, at once.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ScreensView, ScreenViewState } from "../src/core/shapes.ts";

const LINK = "/w/demo/s/local/screen";

/** The demo station's screens: its desktop, and a tab of its browser someone else is on. */
export const SCREENS: ScreensView = {
  screens: [
    { id: "desktop", kind: "desktop", title: "桌面", width: 3024, height: 1890, viewers: [], line: "桌面 · 3024×1890", link: `${LINK}/desktop` },
    { id: "browser:7F3A9C", kind: "browser", title: "登录 · GitHub", width: 1600, height: 1000, viewers: ["张三"], line: "浏览器标签页 · 1600×1000 · 张三 在看", link: `${LINK}/browser%3A7F3A9C` },
  ],
  outdated: false, control: true, known: true,
};
/** What the station lacks, as it says it (macOS grants): to drive the desktop (Accessibility), to see it (Screen Recording). */
const NO_CONTROL = { capture: true, control: false, message: "在 辅助功能 里打开 stillfail-station", app: "stillfail-station" };
const NO_CAPTURE = { capture: false, control: false, message: "在 屏幕录制 里打开 stillfail-station", app: "stillfail-station" };
/** The same screens, the desktop not to be driven until Accessibility is turned on for the station. */
export const SCREENS_LACKING: ScreensView = { ...SCREENS, screens: SCREENS.screens.map((s) => (s.id === "desktop" ? { ...s, access: NO_CONTROL, line: NO_CONTROL.message } : s)) };
/** A station from before screens. */
export const OUTDATED: ScreensView = { screens: [], outdated: true, control: true, known: true, note: "这台 station 需要更新才能远程看屏幕" };

/** How a story's view goes: live (driving, or a read-only member's), or the phase it ends up in. */
export type ViewStory = "connecting" | "live" | "readOnly" | "undrivable" | "reconnecting" | "ended" | "outdated" | "gone" | "denied" | "failed";

const MESSAGES: Partial<Record<ViewStory, string>> = {
  reconnecting: "连接断了，正在重连",
  ended: "张三 关掉了这个标签页",
  outdated: "这台 station 需要更新才能远程看屏幕",
  gone: "这个屏幕已经不在了",
  denied: "现在看不了这个屏幕",
  failed: "连不上这个屏幕",
};

const W = 1600;
const H = 1000;

/** One frame of the made-up desktop, `typed` dots in its password field. */
function scene(typed: number): OffscreenCanvas {
  const c = new OffscreenCanvas(W, H);
  const g = c.getContext("2d")!;
  const font = (size: number, weight = 400) => `${weight} ${size}px -apple-system, "PingFang SC", "Inter Variable", sans-serif`;
  const round = (x: number, y: number, w: number, h: number, r: number) => { g.beginPath(); g.roundRect(x, y, w, h, r); };
  // The wallpaper, the menu bar.
  const sky = g.createLinearGradient(0, 0, W, H);
  sky.addColorStop(0, "#3a6186");
  sky.addColorStop(1, "#89253e");
  g.fillStyle = sky;
  g.fillRect(0, 0, W, H);
  g.fillStyle = "rgba(255, 255, 255, .55)";
  g.fillRect(0, 0, W, 30);
  g.fillStyle = "#1d1d1f";
  g.font = font(15, 600);
  g.fillText("Google Chrome", 44, 20);
  g.font = font(15);
  g.fillText("文件    编辑    显示    历史记录    书签    窗口    帮助", 170, 20);
  g.fillText("周五 10:24", W - 110, 20);
  // The browser's window.
  const x = 150, y = 70, w = 1300, h = 820;
  g.save();
  g.shadowColor = "rgba(0, 0, 0, .35)";
  g.shadowBlur = 40;
  g.shadowOffsetY = 12;
  g.fillStyle = "#ffffff";
  round(x, y, w, h, 12);
  g.fill();
  g.restore();
  g.save();
  round(x, y, w, h, 12);
  g.clip();
  g.fillStyle = "#e8eaed";
  g.fillRect(x, y, w, 84);
  for (const [i, colour] of ["#ff5f57", "#febc2e", "#28c840"].entries()) {
    g.fillStyle = colour;
    g.beginPath();
    g.arc(x + 22 + i * 20, y + 22, 6, 0, Math.PI * 2);
    g.fill();
  }
  g.fillStyle = "#ffffff";
  round(x + 90, y + 8, 240, 34, 8);
  g.fill();
  g.fillStyle = "#202124";
  g.font = font(14);
  g.fillText("登录 · GitHub", x + 106, y + 30);
  g.fillStyle = "#ffffff";
  round(x + 90, y + 48, w - 120, 28, 14);
  g.fill();
  g.fillStyle = "#5f6368";
  g.fillText("github.com/login", x + 110, y + 67);
  // The page: signing in.
  g.fillStyle = "#f6f8fa";
  g.fillRect(x, y + 84, w, h - 84);
  const cx = x + w / 2;
  g.fillStyle = "#1f2328";
  g.beginPath();
  g.arc(cx, y + 160, 24, 0, Math.PI * 2);
  g.fill();
  g.font = font(26, 300);
  g.textAlign = "center";
  g.fillText("Sign in to GitHub", cx, y + 240);
  g.fillStyle = "#ffffff";
  g.strokeStyle = "#d0d7de";
  round(cx - 170, y + 270, 340, 270, 8);
  g.fill();
  g.stroke();
  g.textAlign = "left";
  g.fillStyle = "#1f2328";
  g.font = font(15);
  g.fillText("Username or email address", cx - 150, y + 305);
  g.fillText("Password", cx - 150, y + 385);
  for (const [i, value] of ["lin@acme.dev", "•".repeat(typed)].entries()) {
    g.fillStyle = "#ffffff";
    g.strokeStyle = i === 1 ? "#0969da" : "#d0d7de";
    g.lineWidth = i === 1 ? 2 : 1;
    round(cx - 150, y + 318 + i * 80, 300, 36, 6);
    g.fill();
    g.stroke();
    g.fillStyle = "#1f2328";
    g.font = font(15);
    g.fillText(value, cx - 140, y + 342 + i * 80);
  }
  g.lineWidth = 1;
  g.fillStyle = "#1f883d";
  round(cx - 150, y + 470, 300, 38, 6);
  g.fill();
  g.fillStyle = "#ffffff";
  g.font = font(15, 600);
  g.textAlign = "center";
  g.fillText("Sign in", cx, y + 494);
  g.restore();
  // The dock.
  g.fillStyle = "rgba(255, 255, 255, .35)";
  round(W / 2 - 230, H - 82, 460, 70, 20);
  g.fill();
  for (const [i, colour] of ["#4285f4", "#34a853", "#fbbc05", "#ea4335", "#7e57c2", "#26a69a"].entries()) {
    g.fillStyle = colour;
    round(W / 2 - 215 + i * 74, H - 72, 54, 50, 12);
    g.fill();
  }
  return c;
}

/** The frames a view sends, as a station would: what they are (`config`, the avcC for H.264) and each one's bytes. */
interface Sent { codec: "h264" | "jpeg"; description?: Uint8Array; frames: { key: boolean; ts: number; bytes: Uint8Array }[] }

const TYPED = [0, 4, 8];
const tsOf = (typed: number) => typed * 100_000;

async function asJpeg(): Promise<Sent> {
  const frames: Sent["frames"] = [];
  for (const typed of TYPED) {
    const blob = await scene(typed).convertToBlob({ type: "image/jpeg", quality: 0.86 });
    frames.push({ key: true, ts: tsOf(typed), bytes: new Uint8Array(await blob.arrayBuffer()) });
  }
  return { codec: "jpeg", frames };
}

/** The same as H.264 (Baseline, AVCC: length-prefixed NALs, the avcC beside the config), where the browser encodes it. */
async function asH264(): Promise<Sent | null> {
  const config: VideoEncoderConfig = { codec: "avc1.42E032", width: W, height: H, avc: { format: "avc" }, bitrate: 3_000_000, framerate: 10, latencyMode: "realtime" };
  if (typeof VideoEncoder === "undefined" || !(await VideoEncoder.isConfigSupported(config).catch(() => null))?.supported) return null;
  const sent: Sent = { codec: "h264", frames: [] };
  let failed: unknown = null;
  const encoder = new VideoEncoder({
    output: (chunk, meta) => {
      const description = meta?.decoderConfig?.description;
      if (description && !sent.description) {
        sent.description = ArrayBuffer.isView(description)
          ? new Uint8Array(description.buffer, description.byteOffset, description.byteLength).slice()
          : new Uint8Array(description as ArrayBuffer).slice();
      }
      const bytes = new Uint8Array(chunk.byteLength);
      chunk.copyTo(bytes);
      sent.frames.push({ key: chunk.type === "key", ts: chunk.timestamp, bytes });
    },
    error: (e) => { failed = e; },
  });
  encoder.configure(config);
  for (const typed of TYPED) {
    const picture = new VideoFrame(scene(typed), { timestamp: tsOf(typed) });
    encoder.encode(picture, { keyFrame: typed === 0 });
    picture.close();
  }
  await encoder.flush().catch((e: unknown) => { failed = e; });
  encoder.close();
  return failed || !sent.description || sent.frames.length !== TYPED.length ? null : sent;
}

/** What the view drew with, and the frames it acknowledged (test/browser/screen-input.mjs reads them). */
const seen = { codec: "", acks: [] as number[] };
(globalThis as { screenSeen?: typeof seen }).screenSeen = seen;

const cancelled = () => Object.assign(new Error("cancelled"), { code: "cancelled" });
const wait = (ms: number, signal: AbortSignal) => new Promise<void>((done, fail) => {
  const timer = setTimeout(done, ms);
  signal.addEventListener("abort", () => { clearTimeout(timer); fail(cancelled()); }, { once: true });
});
const forever = (signal: AbortSignal) => new Promise<never>((_, fail) => signal.addEventListener("abort", () => fail(cancelled()), { once: true }));

/** What the views were told to do, in order (`window.screenInputs`: test/browser/screen-input.mjs reads it). */
const heard: unknown[] = [];
(globalThis as { screenInputs?: unknown[] }).screenInputs = heard;

/** The views open now, by their names: what 只看/控制 changes. */
const views = new Map<string, { state: ScreenViewState; say: () => void }>();
const lineOf = (s: ScreenViewState) => `${s.control ? "控制" : "只看"}${s.others.length ? ` · ${s.others.join("、")} 也在看` : ""}`;

async function play(story: ViewStory, h264: boolean, params: Record<string, unknown>, emit: (value: unknown, bytes?: Uint8Array) => void, signal: AbortSignal): Promise<null> {
  const may = story !== "readOnly";
  const browser = String(params.screen).startsWith("browser:");
  const state: ScreenViewState = {
    phase: "connecting", title: browser ? "登录 · GitHub" : "桌面", kind: browser ? "browser" : "desktop",
    control: may && params.control !== false, may, others: ["张三"], line: "",
  };
  const say = () => { state.line = lineOf(state); emit({ state: { ...state, others: [...state.others] } }); };
  const name = String(params.view);
  views.set(name, { state, say });
  signal.addEventListener("abort", () => views.delete(name), { once: true });
  say();
  if (story === "connecting") return forever(signal);
  // Over before it began: the core says why, and answers.
  if (story === "outdated" || story === "gone" || story === "denied" || story === "failed") {
    await wait(300, signal);
    Object.assign(state, { phase: story, message: MESSAGES[story], ...(story === "denied" ? { access: NO_CAPTURE } : {}) });
    say();
    views.delete(name);
    return null;
  }
  // Live: the config, then frames (here: a few, the password being typed), in H.264 where both ends have it.
  await wait(200, signal);
  const codecs = Array.isArray(params.codecs) ? params.codecs : ["jpeg"];
  const sent = (h264 && codecs.includes("h264") ? await asH264() : null) ?? await asJpeg();
  if (signal.aborted) throw cancelled();
  seen.codec = sent.codec;
  emit({ config: { codec: sent.codec, width: W, height: H } }, sent.description);
  for (const [i, f] of sent.frames.entries()) {
    emit({ frame: { key: f.key, ts: f.ts } }, f.bytes);
    if (i === 0) {
      Object.assign(state, { phase: "live", codec: sent.codec, width: W, height: H, cursor: { x: 0.5, y: 0.565, shape: "default" } });
      // Seen, but not driven: the station lacks Accessibility.
      if (story === "undrivable") Object.assign(state, { control: false, access: NO_CONTROL });
      say();
    }
    await wait(250, signal);
  }
  if (story === "reconnecting") {
    Object.assign(state, { phase: "reconnecting", message: MESSAGES.reconnecting });
    say();
  } else if (story === "ended") {
    Object.assign(state, { phase: "ended", message: MESSAGES.ended });
    delete state.cursor;
    say();
    views.delete(name);
    return null;
  }
  return forever(signal);
}

/** The demo with the station's screens (or `list` as said), and its views going as `story` says; `h264` sends H.264 where the browser encodes it. */
export function screensDemo(story: ViewStory = "live", list: ScreensView = SCREENS, h264 = false): DemoExtension {
  return {
    topic: (t) => (t.topic === "screens" ? list : undefined),
    call: (name, p) => {
      if (name === "screen.control") {
        const v = views.get(String(p.view));
        if (v && v.state.may) { v.state.control = p.control === true && v.state.access?.control !== false; v.say(); }
        return null;
      }
      if (name === "screen.input") { heard.push(p.input); return null; }
      if (name === "screen.ack") { seen.acks.push(Number(p.ts)); return null; }
      return name === "screen.keyframe" ? null : undefined;
    },
    stream: (name, params, emit, signal) => (name === "screen.view" ? play(story, h264, params, emit, signal) : undefined),
  };
}
