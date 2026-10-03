// What the core is waiting on, for the one place a UI says so (the `status` topic; status.rs): requests under way to the
// stations and to still.fail cloud, connections being opened, still.fail cloud's events sockets that are down, and how
// fast bytes come in. Only what has taken a while (SLOW_MS) or is down is worth a word. Each workspace has its own
// waits; the device's are apart. While anything is waited on, the topic is computed again each second.
import * as brand from "./brand.ts";
import { said } from "./format.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import type { Runner } from "./runtime.ts";

export const SLOW_MS = 2_000;
const RATE_WINDOW_MS = 3_000;
const TICK_MS = 1_000;

/// Where a wait is: still.fail cloud, the relay, or a station by its address.
export type Place = { cloud: true } | { relay: true } | { station: string };
export const CLOUD: Place = { cloud: true };
export const RELAY: Place = { relay: true };

function samePlace(a: Place, b: Place): boolean {
  if ("cloud" in a) return "cloud" in b;
  if ("relay" in a) return "relay" in b;
  return "station" in b && a.station === b.station;
}

/// Station names by address, for what is said; null says "station".
export type NameOf = (address: string) => string | null;
/// The waits of a workspace, by its id.
export type StatusOf = (workspace: string) => Status;

/// What of a set of waits a status value takes: all of it, or, of the device's in a workspace's, the sockets of the
/// accounts given and the relay opened for no station.
export type Take = "all" | { for: string[] };

type Wait = { place: Place; what: string; connecting: boolean; since: number; bytes: number };
type Down = { since: number; retryAt: number; message: string; tries: number };

/// A wait under way; `end` it (it ends once, whichever way).
export class Waiting {
  readonly #status: Status;
  readonly #id: number;
  #ended = false;
  constructor(status: Status, id: number) {
    this.#status = status;
    this.#id = id;
  }
  /// `n` bytes of its answer came.
  received(n: number): void {
    if (!this.#ended) this.#status.received(this.#id, n);
  }
  end(): void {
    if (this.#ended) return;
    this.#ended = true;
    this.#status.end(this.#id);
  }
}

export class Status {
  readonly #host: Host;
  readonly #runner: Runner;
  #next = 0;
  readonly #waits = new Map<number, Wait>();
  #received: [number, number][] = [];
  readonly #sockets = new Map<string, Down>();
  #ticking = false;
  #changed: (() => void) | null = null;
  #nameOf: NameOf | null = null;
  /// Added to the host's clock: tests move time on.
  skew = 0;

  constructor(host: Host, runner: Runner) {
    this.#host = host;
    this.#runner = runner;
  }

  onChange(changed: () => void): void {
    this.#changed = changed;
  }

  setNames(nameOf: NameOf): void {
    this.#nameOf = nameOf;
  }

  /// Moves this clock on (tests).
  skip(ms: number): void {
    this.skew += ms;
  }

  now(): number {
    return this.#host.nowMs() + this.skew;
  }

  changed(): void {
    this.#changed?.();
  }

  /// Whether something at `place` is waited on as `what` now.
  waits(place: Place, what: string): boolean {
    for (const w of this.#waits.values()) if (samePlace(w.place, place) && w.what === what) return true;
    return false;
  }

  /// A request (or, `connecting`, a connection being opened) starts.
  begin(place: Place, what: string, connecting: boolean): Waiting {
    const id = ++this.#next;
    this.#waits.set(id, { place, what, connecting, since: this.now(), bytes: 0 });
    this.#tick();
    return new Waiting(this, id);
  }

  /// Bytes came: of a wait still under way, or of a stream already open (null).
  received(id: number | null, n: number): void {
    const now = this.now();
    if (id !== null) {
      const w = this.#waits.get(id);
      if (w) w.bytes += n;
    }
    this.#received.push([now, n]);
    while (this.#received.length > 0 && now - this.#received[0][0] > RATE_WINDOW_MS) this.#received.shift();
  }

  end(id: number): void {
    const w = this.#waits.get(id);
    this.#waits.delete(id);
    if (w && this.now() - w.since >= SLOW_MS) this.changed();
  }

  /// An account's events socket failed to open or dropped; it is tried again at `retryAt`.
  socketDown(account: string, message: string, retryAt: number): void {
    const before = this.#sockets.get(account);
    this.#sockets.set(account, { since: before?.since ?? this.now(), retryAt, message, tries: (before?.tries ?? 0) + 1 });
    this.changed();
    this.#tick();
  }

  /// An account's events socket is open, or no longer wanted.
  socketUp(account: string): void {
    if (this.#sockets.delete(account)) this.changed();
  }

  #tick(): void {
    if (this.#ticking || (this.#waits.size === 0 && this.#sockets.size === 0)) return;
    this.#ticking = true;
    this.#runner.spawn(async () => {
      for (;;) {
        await this.#runner.sleep(TICK_MS);
        const now = this.now();
        const busy = this.#waits.size > 0 || this.#sockets.size > 0;
        const shown = this.#sockets.size > 0 || [...this.#waits.values()].some((w) => now - w.since >= SLOW_MS);
        if (shown) this.changed();
        if (!busy) {
          this.#ticking = false;
          return;
        }
      }
    });
  }

  #placeName(place: Place): string | null {
    if ("cloud" in place) return `${brand.name()} cloud`;
    if ("relay" in place) return "relay";
    const name = this.#nameOf?.(place.station) ?? null;
    return name === null || name === "" ? null : name;
  }

  /// The `status` topic's value of these waits alone.
  value(): unknown {
    return value([[this, "all"]]);
  }

  gather(take: Take, into: Gathered): void {
    const now = this.now();
    const wanted = (sub: string) => take === "all" || take.for.includes(sub);
    for (const sub of [...this.#sockets.keys()].sort()) {
      const d = this.#sockets.get(sub)!;
      if (wanted(sub) && now - d.since >= SLOW_MS) into.downs.push({ retryIn: d.retryAt - now, message: d.message, tries: d.tries });
    }
    for (const id of [...this.#waits.keys()].sort((a, b) => a - b)) {
      const w = this.#waits.get(id)!;
      if (now - w.since < SLOW_MS) continue;
      if (take !== "all" && !("relay" in w.place)) continue;
      into.slow.push({ place: this.#placeName(w.place), what: w.what, connecting: w.connecting, age: now - w.since, bytes: w.bytes });
    }
    if (this.#received.length > 0) into.window = Math.max(into.window, Math.min(Math.max(now - this.#received[0][0], 1_000), RATE_WINDOW_MS));
    into.recent += this.#received.filter(([at]) => now - at <= RATE_WINDOW_MS).reduce((s, [, n]) => s + n, 0);
  }
}

type Shown = { retryIn: number; message: string; tries: number };
type Slow = { place: string | null; what: string; connecting: boolean; age: number; bytes: number };
export type Gathered = { downs: Shown[]; slow: Slow[]; recent: number; window: number };

/// The `status` topic's value (StatusView) of these sets of waits.
export function value(parts: [Status, Take][]): Record<string, unknown> {
  const all: Gathered = { downs: [], slow: [], recent: 0, window: 0 };
  for (const [status, take] of parts) status.gather(take, all);
  const items: Record<string, unknown>[] = [];
  // The first of the smallest (Rust's min_by keeps the first of equals).
  let down: Shown | null = null;
  for (const d of all.downs) if (down === null || d.retryIn < down.retryIn) down = d;
  if (down) {
    const wait = Math.max(Math.ceil(down.retryIn / 1000), 0);
    const when = wait > 0 ? t("core-logic.status.down.retry_in", { n: wait }) : t("core-logic.status.down.retrying");
    const tries = down.tries > 1 ? t("core-logic.status.down.tries", { n: down.tries }) : "";
    const detail = down.message === "" ? t("core-logic.status.down.paused") : t("core-logic.status.down.paused_why", { why: down.message });
    items.push({ state: "trouble", text: t("core-logic.status.down", { brand: brand.name(), when, tries }), detail });
  }
  // The connections first (the requests wait on them), the oldest first; a stable sort as Rust's.
  const slow = [...all.slow].sort((a, b) => (a.connecting === b.connecting ? b.age - a.age : a.connecting ? -1 : 1));
  for (const w of slow) {
    const secs = Math.floor(w.age / 1000);
    const text = w.connecting ? t("core-logic.status.connecting", { place: w.place ?? "station" }) : w.place !== null ? t("core-logic.status.at", { place: w.place, what: w.what }) : w.what;
    const detail = w.connecting
      ? t("core-logic.status.waited", { secs })
      : w.bytes === 0
        ? t("core-logic.status.waited_nothing", { secs })
        : t("core-logic.status.received", { size: size(w.bytes), secs });
    items.push({ state: "slow", text, detail });
  }
  if (items.length === 0) return { state: null, text: null, items: [] };
  const window = all.window > 0 ? all.window : RATE_WINDOW_MS;
  const rate = Math.trunc(all.recent / (window / 1000));
  const state = down ? "trouble" : "slow";
  let text = String(items[0].text);
  if (slow.length > 0 && !down) text += ` · ${t("core-logic.status.seconds", { n: Math.floor(slow[0].age / 1000) })}`;
  if (items.length > 1) text += ` · ${t("core-logic.status.count", { n: items.length })}`;
  if (slow.length > 0 && rate > 0) text += ` · ${size(rate)}/s`;
  return { state, text, items };
}

/// Bytes in words: "820 B", "12 KB", "1.4 MB".
export function size(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/// What a station request does, in words, by its method and path (without `/admin/api`).
export function stationWhat(method: string, path: string): string {
  const parts = path.split("?")[0].split("/").filter((p) => p !== "");
  const get = method.toUpperCase() === "GET";
  const [a, b, c] = parts;
  if (get && parts.length === 1 && a === "events") return said("core-logic.status.what.events");
  if (get && parts.length === 3 && a === "threads" && c === "entries") return said("core-logic.status.what.thread");
  if (get && a === "threads") return said("core-logic.status.what.threads");
  if (get && parts.length === 1 && a === "chats") return said("core-logic.status.what.chats");
  if (get && parts.length === 3 && a === "sessions" && c === "files") return said("core-logic.status.what.files");
  if (get && parts.length >= 2 && a === "sessions") return said("core-logic.status.what.session");
  if (get && parts.length === 1 && a === "sessions") return said("core-logic.status.what.sessions");
  if (get && parts.length === 1 && a === "overview") return said("core-logic.status.what.overview");
  if (a === "preview") return said("core-logic.status.what.preview");
  if (!get && parts.length === 1 && a === "uploads") return said("core-logic.status.what.upload");
  void b;
  return get ? said("core-logic.status.what.read") : said("core-logic.status.what.write");
}

/// What a still.fail cloud request does, in words.
export function cloudWhat(method: string, path: string): string {
  const p = path.split("?")[0];
  const get = method.toUpperCase() === "GET";
  if (p.endsWith("/credential")) return said("core-logic.status.what.credential");
  if (!get) return said("core-logic.status.what.write");
  if (p === "/v1/me") return said("core-logic.status.what.me");
  if (p.startsWith("/v1/workspaces/")) return said("core-logic.status.what.workspace");
  return said("core-logic.status.what.read");
}
