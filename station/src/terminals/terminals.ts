// The station's terminals: a person's shell on this machine, opened from the app (步骤 2b of the terminal; the user,
// 2026-11-14). Each is a runner's (`--pty`, link.ts), so it outlives the station restarting as an agent does; who may
// open one is who may make an agent run anything here: every member but a read-only one, who only looks (station
// AGENTS.md: no permission system; the user, 2026-11-14: 「所有成员都能开」). One view types into a terminal at a time,
// any number look, as a screen's (screens/hub.ts `drive`): asking 接管 takes it, and the one who had it is told.
//
// A view is a stream on a member's link (mesh/serve.ts, this part's `terminal` requests): its head line
// `{terminal: {cols, rows, control?, taken?, cwd?, chat?}}` on POST /admin/api/terminals/<id>/view (`new` opens one),
// answered 200 `application/x-stillfail-terminal`, then frames both ways as a screen's (mesh/screens.ts `frame`: a kind
// byte, its payload's length in 4 bytes, the payload). Station → client: `screen` (VT that makes the screen as it is in
// a new terminal of its size, first, and again as the size changes), `out` (what the program wrote since), `state`
// (JSON: the terminal's id, size and folder, whether this view types, who does, who looks, its exit once it ended). Client →
// station: `input` (bytes typed, as its terminal encodes them), `resize` (JSON `{cols, rows}`: the typing view's alone).
import { frame } from "../mesh/screens.ts";
import { readOnly, type Viewer } from "../mesh/credential.ts";
import type { Stream } from "../mesh/native.ts";
import { writeLine } from "../mesh/wire.ts";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { type Ended, type Out, type TerminalLink, pastScreen } from "./link.ts";

export const TERMINAL_TYPE = "application/x-stillfail-terminal";
export const KIND = { screen: 1, out: 2, state: 3, input: 16, resize: 17 } as const;
/// A client's frame: what is typed at once, or a size.
export const MAX_IN = 64 * 1024;
/// A terminal's size, in cells.
export const SIZE = { cols: [2, 1000], rows: [1, 500] } as const;
/// How many terminals a station keeps at once.
export const MOST = 16;
const PATH = /^\/admin\/api\/terminals\/([^/?]+)\/view$/;

/// What a terminal is said to be, to every member (GET /terminals, `terminals` on the event stream).
export type TerminalShown = {
  id: string;
  /// Who opened it, and when (ms).
  by: string;
  at: number;
  cwd: string;
  /// The chat it was opened from, if one.
  chat?: string;
  /// Who types into it now, and who looks.
  typing: string | null;
  looking: string[];
  /// Its program's exit, once it ended.
  ended?: Ended | null;
};

/// What opens a terminal: where its runner starts it, as whom, how large.
/// `workspace`: the opener's; only its members see the terminal (workspaces are kept apart, station AGENTS.md).
export type Opening = { cols: number; rows: number; cwd?: string; chat?: string; by: string; workspace: string };
/// What the station gives the terminals: how one is started (its runner, its link), the folder one opens in when none is
/// asked, what is told as they change.
/// What is kept of a terminal beside its runner, so a station after this one says the same of it.
export type TerminalMeta = { by: string; at: number; cwd: string; chat?: string; workspace: string };
export type TerminalDeps = {
  /// Starts its runner, keeps its meta, and links to it.
  start(id: string, o: Opening & { cwd: string }, meta: TerminalMeta): Promise<TerminalLink>;
  home: string;
  /// A chat's folder, if it is one of this station's.
  chatDir(chat: string): string | undefined;
  changed(): void;
  /// It left the list (ended, and no view is left on it): what was kept of it goes.
  gone(id: string): void;
  newId(): string;
};

/// `again`: gives it the screen anew (the size changed: its own terminal is made that size from it).
type View = { id: number; name: string; device: string; types: boolean; tell(state: Record<string, unknown>): void; again(): Promise<void> };

class Terminal {
  readonly views = new Map<number, View>();
  typing: number | null = null;
  /// Its size, as the typing view last made it (one taken up from before: a usual one till a view says).
  size = { cols: 80, rows: 24 };
  readonly id: string;
  readonly link: TerminalLink;
  readonly by: string;
  readonly at: number;
  readonly cwd: string;
  readonly chat: string | undefined;
  readonly workspace: string;
  constructor(id: string, link: TerminalLink, by: string, at: number, cwd: string, chat: string | undefined, workspace: string) {
    this.id = id;
    this.link = link;
    this.by = by;
    this.at = at;
    this.cwd = cwd;
    this.chat = chat;
    this.workspace = workspace;
  }

  shown(): TerminalShown {
    const typing = this.typing === null ? null : (this.views.get(this.typing)?.name ?? null);
    const looking = [...this.views.values()].filter((v) => v.id !== this.typing).map((v) => v.name);
    return { id: this.id, by: this.by, at: this.at, cwd: this.cwd, ...(this.chat ? { chat: this.chat } : {}), typing, looking, ...(this.link.over ? { ended: this.#ended } : {}) };
  }

  #ended: Ended | null = null;
  setEnded(e: Ended | null) {
    this.#ended = e;
  }
}

export class Terminals {
  readonly #deps: TerminalDeps;
  readonly #terminals = new Map<string, Terminal>();
  #views = 0;

  constructor(deps: TerminalDeps) {
    this.#deps = deps;
  }

  /// A workspace's (its members see them).
  list(workspace: string): TerminalShown[] {
    return [...this.#terminals.values()].filter((t) => t.workspace === workspace).map((t) => t.shown());
  }

  /// The workspaces that have one, for what is told as they change.
  workspaces(): string[] {
    return [...new Set([...this.#terminals.values()].map((t) => t.workspace))];
  }

  /// One a runner kept from before this station (adopted as it starts).
  keep(id: string, link: TerminalLink, meta: TerminalMeta) {
    this.#add(new Terminal(id, link, meta.by, meta.at, meta.cwd, meta.chat, meta.workspace));
  }

  #add(t: Terminal) {
    this.#terminals.set(t.id, t);
    t.link.ended((e) => {
      t.setEnded(e);
      log.info("terminal", "ended", { id: t.id, code: e?.code ?? null, signal: e?.signal ?? null });
      for (const v of t.views.values()) v.tell(this.#state(t, v));
      // Its views say how it ended; it leaves the list once none is left.
      if (t.views.size === 0) this.#drop(t);
      this.#deps.changed();
    });
    this.#deps.changed();
  }

  async open(o: Opening): Promise<Terminal> {
    if ([...this.#terminals.values()].filter((t) => !t.link.over).length >= MOST) throw new TerminalRefused(429, `a station keeps ${MOST} terminals at most: end one first`);
    const cwd = o.cwd ?? (o.chat ? this.#deps.chatDir(o.chat) : undefined) ?? this.#deps.home;
    const id = this.#deps.newId();
    const at = wall.now();
    const link = await this.#deps.start(id, { ...o, cwd }, { by: o.by, at, cwd, ...(o.chat ? { chat: o.chat } : {}), workspace: o.workspace });
    const t = new Terminal(id, link, o.by, at, cwd, o.chat, o.workspace);
    t.size = { cols: o.cols, rows: o.rows };
    log.info("terminal", "opened", { id, by: o.by, cwd, ...(o.chat ? { chat: o.chat } : {}) });
    this.#add(t);
    return t;
  }

  /// Ends it (its program and what it started), whoever asks.
  end(id: string, by: string, workspace: string): boolean {
    const t = this.#terminals.get(id);
    if (t === undefined || t.workspace !== workspace) return false;
    log.info("terminal", "ended by a member", { id, by });
    if (t.link.over) this.#drop(t), this.#deps.changed();
    else t.link.kill();
    return true;
  }

  #drop(t: Terminal) {
    if (this.#terminals.get(t.id) === t) {
      this.#terminals.delete(t.id);
      this.#deps.gone(t.id);
    }
  }

  /// The station stops or hands over: every runner keeps its terminal for the next one.
  detach() {
    for (const t of this.#terminals.values()) t.link.detach();
  }

  #state(t: Terminal, v: View): Record<string, unknown> {
    const s = t.shown();
    return { id: t.id, types: t.typing === v.id, typing: s.typing, looking: s.looking, cwd: t.cwd, cols: t.size.cols, rows: t.size.rows, ...(t.link.over ? { ended: s.ended ?? null } : {}) };
  }

  #tellAll(t: Terminal) {
    for (const v of t.views.values()) v.tell(this.#state(t, v));
    this.#deps.changed();
  }

  /// A view of a terminal, for as long as its stream lasts.
  async answer(stream: Stream, carry: Buffer, head: any, viewer: Viewer): Promise<void> {
    const refuse = async (status: number, error: string) => {
      await writeLine(stream, { status, headers: { "content-type": "application/json" } });
      await stream.write(Buffer.from(JSON.stringify({ error })));
      await stream.finish();
    };
    const method = typeof head.method === "string" ? head.method.toUpperCase() : "GET";
    const found = PATH.exec(typeof head.path === "string" ? head.path : "");
    if (found === null || method !== "POST") return refuse(404, "a terminal is viewed with POST /admin/api/terminals/<id>/view");
    const ask = asked(head.terminal);
    if (ask === null) return refuse(400, `terminal: {cols ${SIZE.cols.join("-")}, rows ${SIZE.rows.join("-")}}`);
    const name = viewer.name || viewer.email;
    const looksOnly = readOnly(viewer);
    let t: Terminal | undefined;
    if (found[1] === "new") {
      if (looksOnly) return refuse(403, "a read-only member does not open a terminal");
      try {
        t = await this.open({ cols: ask.cols, rows: ask.rows, ...(ask.cwd ? { cwd: ask.cwd } : {}), ...(ask.chat ? { chat: ask.chat } : {}), by: name, workspace: viewer.workspace });
      } catch (error) {
        return refuse(error instanceof TerminalRefused ? error.status : 503, (error as Error).message);
      }
    } else {
      t = this.#terminals.get(decodeURIComponent(found[1]!));
      if (t !== undefined && t.workspace !== viewer.workspace) t = undefined;
      if (t === undefined) return refuse(404, "no such terminal: it ended, or the station was set up anew");
    }
    const terminal = t;
    // Whether it types: asked and let (not read-only); it takes the terminal from another only when asked to (接管), or
    // where none types now.
    const types = ask.control && !looksOnly && (ask.taken || terminal.typing === null);
    const writes: Promise<void>[] = [];
    let chain: Promise<void> = Promise.resolve();
    let broken = false;
    const send = (kind: number, payload: Buffer) => {
      chain = chain.then(() => (broken ? undefined : stream.write(frame(kind, payload)))).catch(() => void (broken = true));
      writes.push(chain);
    };
    const view: View = { id: ++this.#views, name, device: viewer.device, types, tell: (state) => send(KIND.state, Buffer.from(JSON.stringify(state))), again: async () => {} };
    try {
      await writeLine(stream, { status: 200, headers: { "content-type": TERMINAL_TYPE } });
    } catch {
      return;
    }
    // What comes before the screen is answered is kept, and given past where the screen is.
    let pending: Out[] | null = [];
    let shownAt = 0;
    const unlisten = terminal.link.listen((out) => {
      if (pending !== null) pending.push(out);
      else {
        const past = pastScreen(out, shownAt);
        if (past) send(KIND.out, past);
      }
    });
    const giveScreen = async () => {
      pending = pending ?? [];
      try {
        const shown = await terminal.link.screen();
        shownAt = shown.at;
        send(KIND.screen, shown.data);
      } catch {
        // Ended meanwhile: its state says so.
      }
      for (const out of pending.splice(0)) {
        const past = pastScreen(out, shownAt);
        if (past) send(KIND.out, past);
      }
      pending = null;
    };
    view.again = giveScreen;
    const took = types && terminal.typing !== null && terminal.typing !== view.id ? terminal.views.get(terminal.typing) : undefined;
    const others = [...terminal.views.values()];
    terminal.views.set(view.id, view);
    if (types) {
      terminal.typing = view.id;
      if (took) log.info("terminal", "taken over", { id: terminal.id, by: name, from: took.name });
      // The size is the typing view's: those already on it are given the screen at that size.
      terminal.size = { cols: ask.cols, rows: ask.rows };
      terminal.link.resize(ask.cols, ask.rows);
      for (const v of others) void v.again();
    }
    this.#tellAll(terminal);
    // (its typing is read meanwhile: the screen is the runner's to answer, after what it was asked before)
    void giveScreen();
    const ended = terminal.link.ended(() => this.#tellAll(terminal));
    try {
      const frames = new FrameIn(stream, carry);
      for (;;) {
        const f = await frames.next();
        if (f === null) break;
        const typing = terminal.typing === view.id;
        if (f.kind === KIND.input && typing) terminal.link.type(f.payload);
        else if (f.kind === KIND.resize && typing) {
          const size = sizeOf(f.payload);
          if (size === null) continue;
          terminal.size = size;
          terminal.link.resize(size.cols, size.rows);
          this.#tellAll(terminal);
          // Every view is given the screen again at the new size (its own terminal made that size from it).
          for (const v of terminal.views.values()) void v.again();
        }
      }
    } catch {
      // A frame too large, the stream broken: the view ends.
    } finally {
      unlisten();
      ended();
      terminal.views.delete(view.id);
      if (terminal.typing === view.id) terminal.typing = null;
      if (terminal.link.over && terminal.views.size === 0) this.#drop(terminal);
      this.#tellAll(terminal);
      await Promise.allSettled(writes);
      await stream.finish().catch(() => undefined);
    }
  }
}

export class TerminalRefused extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const within = (n: unknown, [lo, hi]: readonly [number, number]): n is number => Number.isInteger(n) && (n as number) >= lo && (n as number) <= hi;

/// A view's head (`terminal`): its size, whether it asks to type and to take the terminal, where a new one opens.
export function asked(v: any): { cols: number; rows: number; control: boolean; taken: boolean; cwd?: string; chat?: string } | null {
  if (v === null || typeof v !== "object" || !within(v.cols, SIZE.cols) || !within(v.rows, SIZE.rows)) return null;
  const text = (x: unknown) => (typeof x === "string" && x !== "" && x.length <= 4096 ? x : undefined);
  const cwd = text(v.cwd), chat = text(v.chat);
  return { cols: v.cols, rows: v.rows, control: v.control !== false, taken: v.taken === true, ...(cwd ? { cwd } : {}), ...(chat ? { chat } : {}) };
}

/// A `resize` frame's size, or null when it is none.
export function sizeOf(payload: Buffer): { cols: number; rows: number } | null {
  try {
    const v = JSON.parse(payload.toString("utf8"));
    return within(v?.cols, SIZE.cols) && within(v?.rows, SIZE.rows) ? { cols: v.cols, rows: v.rows } : null;
  } catch {
    return null;
  }
}

/// Frames from a client, after what came with the head line (mesh/screens.ts FrameIn, with a terminal's bound).
class FrameIn {
  #carry: Buffer;
  readonly #stream: Stream;
  constructor(stream: Stream, carry: Buffer) {
    this.#stream = stream;
    this.#carry = carry;
  }
  async next(): Promise<{ kind: number; payload: Buffer } | null> {
    for (;;) {
      if (this.#carry.length >= 5) {
        const length = this.#carry.readUInt32BE(1);
        if (length > MAX_IN) throw new Error("terminal frame too large");
        if (this.#carry.length >= 5 + length) {
          const kind = this.#carry[0]!;
          const payload = this.#carry.subarray(5, 5 + length);
          this.#carry = this.#carry.subarray(5 + length);
          return { kind, payload };
        }
      }
      const more = await this.#stream.read();
      if (more === null) {
        if (this.#carry.length === 0) return null;
        throw new Error("stream ended inside a terminal frame");
      }
      this.#carry = this.#carry.length === 0 ? more : Buffer.concat([this.#carry, more]);
    }
  }
}
