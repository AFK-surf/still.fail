// The dock (docs/desktop-dock.md): on macOS, a half circle of Liquid Glass on the screen's right edge with the chats
// that want the person, drawn by a SwiftUI helper (apps/desktop/dock, prebuilt: scripts/native.ts `dock`). This side
// starts it, follows the core for what to show and does what is asked of it there; the helper only draws and says
// which button was pressed. One JSON object a line each way (dock/Sources/StillfailDock/main.swift).
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync } from "node:fs";
import { release } from "node:os";
import { createInterface } from "node:readline";

/** What the dock shows of a chat (Model.swift `Item`). */
export interface DockItem {
  id: string;
  key: string;
  title: string;
  station: string;
  tone: "wait" | "alert" | "done";
  who?: string;
  text: string;
  ask?: string;
  options?: { label: string; recommended?: boolean }[];
  at: number;
}

/** Where an item's chat is and what it is at: for opening it, reading it and answering its card. */
interface Place { url: string; station: string; thread?: number; seq?: number; card?: number }

export interface DockHost {
  /** Holds a topic of the core's (the app's own link); the value each time it changes. Returns the letting go. */
  subscribe(topic: Record<string, unknown>, onValue: (value: unknown) => void): () => void;
  call(name: string, params: unknown): Promise<unknown>;
  /** Brings the app's window to the front on a page of it. */
  open(path: string): void;
  words(): Record<string, string>;
  /** The person turned the dock off from it (its menu). */
  turnedOff(): void;
}

// The shapes of what the core sends that the dock reads (web/src/core/shapes.ts ChatsView, ChatItem, DecisionsView).
interface ChatRow {
  id: string; session?: string; thread?: number; title?: string; station: string; stationName?: string; unread?: boolean;
  tone?: string; lastActiveAt?: number; last?: { seq?: number; text?: string; preview?: string; createdAt?: number; by?: { name?: string } };
}
interface Decision {
  station: string; stationName?: string; session: string; thread: number; seq: number; title?: string; question?: string; text?: string;
  options?: { label: string; recommended?: boolean }[]; card?: { type?: string }; message?: { createdAt?: number; by?: { name?: string }; text?: string }; deferred?: boolean;
}

const encode = (s: string) => encodeURIComponent(s);
/** A message as the dock's card shows it: one paragraph, and not more than it can hold (seven lines). */
const oneLine = (s: string | undefined) => {
  const text = (s ?? "").replace(/\s+/g, " ").trim();
  return text.length > 400 ? `${text.slice(0, 400)}…` : text;
};

/** The workspace's chats that want the person, as the dock shows them, with where each is. */
export function dockItems(workspace: string, chats: unknown, decisions: unknown): { item: DockItem; place: Place }[] {
  const out = new Map<string, { item: DockItem; place: Place }>();
  const days = (chats as { days?: { items?: ChatRow[] }[] } | undefined)?.days ?? [];
  const asked = (decisions as { items?: Decision[] } | undefined)?.items ?? [];
  const url = (station: string, session: string) => `/o/${workspace}/${station.split("/").pop()}/${encode(session)}`;
  // A card waiting on the person: its question and options, to answer right there (only option cards; a text card is
  // answered in the chat).
  for (const d of asked) {
    if (d.deferred) continue;
    const id = `${d.station}|${d.session}`;
    const options = d.card?.type === "options" || d.card === undefined ? (d.options ?? []).map((o) => ({ label: o.label, ...(o.recommended ? { recommended: true } : {}) })) : [];
    out.set(id, {
      item: {
        id, key: `${id}#card${d.seq}`, title: d.title ?? "", station: d.stationName ?? "", tone: "wait",
        ...(d.message?.by?.name ? { who: d.message.by.name } : {}),
        text: oneLine(d.message?.text) || oneLine(d.text), ask: d.question ?? d.text?.replace(/^奏 · /, "") ?? "",
        ...(options.length ? { options } : {}), at: d.message?.createdAt ?? Date.now(),
      },
      place: { url: url(d.station, d.session), station: d.station, thread: d.thread, card: d.seq },
    });
  }
  for (const day of days) {
    for (const c of day.items ?? []) {
      const session = c.session ?? c.id;
      const id = `${c.station}|${session}`;
      if (out.has(id)) continue;
      // Something not read: red when it failed. Read, it is the sidebar's; waiting on someone else is not the person's.
      const tone = !c.unread ? null : c.tone === "alert" ? "alert" : "done";
      if (!tone) continue;
      out.set(id, {
        item: {
          id, key: `${id}#${c.last?.seq ?? c.lastActiveAt ?? 0}${tone}`, title: c.title ?? "", station: c.stationName ?? "", tone,
          ...(c.last?.by?.name ? { who: c.last.by.name } : {}), text: oneLine(c.last?.text ?? c.last?.preview),
          at: c.last?.createdAt ?? c.lastActiveAt ?? 0,
        },
        place: { url: url(c.station, session), station: c.station, ...(c.thread !== undefined ? { thread: c.thread } : {}), ...(c.last?.seq !== undefined ? { seq: c.last.seq } : {}) },
      });
    }
  }
  return [...out.values()];
}

/** The helper, where the app has it: its Resources when packed, build/ run from the source. */
export function dockHelper(resources: string): string | null {
  if (process.platform !== "darwin" || process.arch !== "arm64") return null;
  // SwiftUI's Observation: macOS 14 (Darwin 23) or later; Liquid Glass from macOS 26, a material before.
  if (Number(release().split(".")[0]) < 23) return null;
  const path = `${resources}/dock/StillfailDock`;
  return existsSync(path) ? path : null;
}

export class Dock {
  #child: ChildProcessWithoutNullStreams | null = null;
  #held: (() => void)[] = [];
  #perWorkspace = new Map<string, { chats?: unknown; decisions?: unknown; letGo: () => void }>();
  #places = new Map<string, Place>();
  #restarts = 0;
  #on = false;

  readonly path: string;
  readonly host: DockHost;

  constructor(path: string, host: DockHost) {
    this.path = path;
    this.host = host;
  }

  start(): void {
    if (this.#on) return;
    this.#on = true;
    this.#spawn();
    this.follow();
  }

  stop(): void {
    this.#on = false;
    this.#letGo();
    this.#child?.stdin.end();
    this.#child?.kill();
    this.#child = null;
  }

  /** The core's topics, held again on a new link (main.ts dropOwnLink). */
  follow(): void {
    if (!this.#on) return;
    this.#letGo();
    this.#held.push(this.host.subscribe({ topic: "workspaces" }, (value) => this.#workspaces(value)));
  }

  /** The app's language changed. */
  words(): void {
    this.#send({ type: "words", words: this.host.words() });
  }

  #letGo(): void {
    for (const letGo of this.#held) letGo();
    this.#held = [];
    for (const w of this.#perWorkspace.values()) w.letGo();
    this.#perWorkspace.clear();
  }

  /** Every workspace of every account: each one's chats and cards. */
  #workspaces(value: unknown): void {
    const ids = new Set<string>();
    for (const account of (value as { workspaces?: { id: string }[] }[] | undefined) ?? []) for (const w of account.workspaces ?? []) ids.add(w.id);
    for (const [id, w] of this.#perWorkspace) if (!ids.has(id)) { w.letGo(); this.#perWorkspace.delete(id); }
    for (const id of ids) {
      if (this.#perWorkspace.has(id)) continue;
      const w: { chats?: unknown; decisions?: unknown; letGo: () => void } = { letGo: () => {} };
      const chats = this.host.subscribe({ topic: "chats", scope: id, mine: true }, (v) => { w.chats = v; this.#items(); });
      const decisions = this.host.subscribe({ topic: "decisions", workspace: id }, (v) => { w.decisions = v; this.#items(); });
      w.letGo = () => { chats(); decisions(); };
      this.#perWorkspace.set(id, w);
    }
    this.#items();
  }

  #items(): void {
    const all: DockItem[] = [];
    this.#places.clear();
    for (const [id, w] of this.#perWorkspace) {
      for (const { item, place } of dockItems(id, w.chats, w.decisions)) {
        all.push(item);
        this.#places.set(item.id, place);
      }
    }
    this.#send({ type: "items", items: all });
  }

  #spawn(): void {
    const child = spawn(this.path, [], { stdio: ["pipe", "pipe", "pipe"] });
    this.#child = child;
    child.stdin.on("error", () => {});
    child.stderr.on("data", (data: Buffer) => console.warn("dock:", data.toString().trim()));
    createInterface({ input: child.stdout }).on("line", (line) => this.#heard(line));
    child.on("exit", (code) => {
      if (this.#child !== child) return;
      this.#child = null;
      // Gone by itself: back after a moment, a few times; then the app runs without it until it starts again.
      if (this.#on && this.#restarts++ < 5) setTimeout(() => { if (this.#on && !this.#child) { this.#spawn(); this.words(); this.#items(); } }, 2000);
      else if (code !== 0) console.warn("the dock stopped", code);
    });
    this.words();
  }

  #send(message: unknown): void {
    if (this.#child?.stdin.writable) this.#child.stdin.write(JSON.stringify(message) + "\n");
  }

  #heard(line: string): void {
    let m: { type?: string; id?: string; option?: string };
    try { m = JSON.parse(line); } catch { return; }
    if (m.type === "off") { this.host.turnedOff(); return; }
    const place = m.id ? this.#places.get(m.id) : undefined;
    if (!place) return;
    const done = (what: string) => (e: Error) => console.warn(`dock: ${what} failed`, e.message);
    if (m.type === "open") this.host.open(place.url);
    else if (m.type === "read" && place.thread !== undefined && place.seq !== undefined) {
      void this.host.call("chat.read", { station: place.station, thread: place.thread, seq: place.seq }).catch(done("chat.read"));
    } else if (m.type === "answer" && m.option && place.thread !== undefined && place.card !== undefined) {
      void this.host.call("decision.answer", { station: place.station, thread: place.thread, seq: place.card, option: m.option }).catch(done("decision.answer"));
    }
  }
}
