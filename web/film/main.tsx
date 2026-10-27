// One pane of the promo film (?pane=phone|home|studio|win|cloud): the site's demo app as the whole page, playing the
// film's world (story.ts) and showing the pane's chat. record.mjs opens each on its own clock and films it frame by
// frame; compose.ts puts the panes together.
import "../src/styles/index.ts";
import { extendDemo, mountDemo } from "../src/demo/mount.tsx";
import { outgoing } from "../src/demo/fixtures.ts";
import { demoCore } from "../src/demo/mount.tsx";
import type { ChatsView, ChatView } from "../src/core/shapes.ts";
import { tabsOf } from "../../client/core-ts/src/chat-tabs.ts";
import { MACHINE, MACHINES, MAIN, PANE_CHAT } from "./story.ts";
import android from "./shots/android.png?url";
import windows from "./shots/windows.png?url";
import mac from "./shots/mac.png?url";
import all from "./shots/all.png?url";

const query = new URLSearchParams(location.search);
const pane = query.get("pane") ?? "home";
document.documentElement.dataset.theme = query.get("theme") ?? "light";
if (pane === "phone") {
  document.documentElement.style.setProperty("--safe-top", "54px");
  document.documentElement.style.setProperty("--safe-bottom", "26px");
}

const withHistory = (v: ChatView): ChatView => {
  const session = v.agents[0]?.session.key;
  return session ? { ...v, tabs: tabsOf({ tabs: [session], active: session }, v.agents, false, session) } : v;
};

const shots: Record<string, Uint8Array> = {};
await Promise.all(Object.entries({ android, windows, mac, all }).map(async ([k, url]) => { shots[k] = new Uint8Array(await (await fetch(url)).arrayBuffer()); }));
const shotOf = (name: string) => shots[name.startsWith("android") ? "android" : name.startsWith("windows") ? "windows" : name.startsWith("mac") ? "mac" : "all"]!;
/** The machine this pane's chat is on: the demo calls its one station Studio everywhere. */
const machine = MACHINE[PANE_CHAT[pane] ?? MAIN] ?? "Studio";
/** What people and agents wrote stays as written. */
const WRITTEN = new Set(["messages", "items", "outbox", "text", "md", "line"]);
const renamed = (v: unknown): unknown => typeof v === "string" ? v.replaceAll("Studio", machine)
  : Array.isArray(v) ? v.map(renamed)
  : v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, WRITTEN.has(k) ? x : renamed(x)])) : v;

extendDemo({
  then: (t, value) => {
    if (!value || typeof value !== "object") return undefined;
    // A computer's chat with its agent's work open beside it, as one opens it (its 执行 panel).
    const shown = t.topic === "chat" && query.has("history") ? withHistory(value as ChatView) : value;
    if (t.topic !== "chats") return machine === "Studio" ? shown : renamed(shown);
    const v = value as ChatsView;
    return {
      ...v,
      stations: MACHINES.map((name, i) => ({ id: i ? `m${i}` : "local", station: `demo/${i ? `m${i}` : "local"}`, name, state: "online" })),
      days: v.days.map((d) => ({ ...d, items: d.items.map((item) => ({ ...item, stationName: MACHINE[item.id] ?? item.stationName })) })),
    };
  },
  call: (name, p) => {
    if (query.get("debug")) console.log("call", name, JSON.stringify(p).slice(0, 200));
    const chat = demoCore.chats.find((c) => c.key === MAIN)!;
    // Sent from the phone: on its way at once; the world says it arrived (story.ts).
    if (name === "chat.send" && typeof p.text === "string") {
      chat.outbox = [outgoing(p.text)];
      setTimeout(demoCore.publish, 0);
      return { more: false };
    }
    if (name === "decision.answer") {
      chat.messages = chat.messages.map((m) => (m.card && !m.decision?.resolved ? { ...m, asked: false, decision: { resolved: true, chosen: "合并", answeredBy: "你", text: "你 选了「合并」" } } : m));
      chat.outbox = [outgoing("合并")];
      setTimeout(demoCore.publish, 0);
      return null;
    }
    if (name === "station.file" || name === "station.file.part") {
      const bytes = shotOf(String(p.name));
      return { type: "image/png", total: bytes.length, bytes };
    }
    return undefined;
  },
});

const root = document.getElementById("app")!;
root.style.cssText = "position:fixed;inset:0";
mountDemo(root);
(window as unknown as { filmReady: boolean }).filmReady = true;
