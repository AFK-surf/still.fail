// What the chats' people hear about while no client of theirs runs (admin/notify.rs and the station process's
// notify.rs, docs/notifications.md): noticed from the store's changes as they come, worked out by the readers
// (src/read/notices.ts), gathered over a second and posted to still.fail cloud's `/v1/stations/notify`, signed with the
// station's key, which pushes them to people's devices. Only what happens from now on is noticed. A batch that cannot be
// sent is dropped; an older cloud (404) has no pushes.
import { stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Readers } from "../read/pool.ts";
import type { Notice } from "../read/notices.ts";
import type { Store } from "../store/store.ts";
import type { StationKey } from "./key.ts";
import { signedPost } from "./signed.ts";
import type { Cloud } from "./state.ts";

/// Notices wait this long to go out together; at most this many in one post (the cloud takes no more).
const GATHER_MS = 1_000;
const MAX_BATCH = 50;

export class Notifier {
  private since = Date.now();
  /// Each session's last turn noticed (when it ended), so one turn is noticed once.
  private ended = new Map<string, number>();
  private waiting: Notice[] = [];
  private timer: ReturnType<typeof setTimeout> | null = null;
  private stop: () => void;
  private readers: Readers;
  private store: Store;
  private cloud: Cloud;
  private key: StationKey;
  /// Where a batch goes (tests give their own); still.fail cloud's by default.
  post: (notices: Notice[]) => Promise<void>;

  constructor(store: Store, readers: Readers, cloud: Cloud, key: StationKey) {
    this.store = store;
    this.readers = readers;
    this.cloud = cloud;
    this.key = key;
    this.post = (notices) => this.send(notices);
    this.stop = store.subscribe((change) => {
      if (change.type === "session") this.sessionChanged(change.key);
      else if (change.type === "thread") this.said(change.id, change.entries);
    });
  }

  close() {
    this.stop();
    if (this.timer) clearTimeout(this.timer);
  }

  /// A turn that ended since the last look: its chats hear how. Looked at here first, so most changes ask nothing.
  private sessionChanged(key: string) {
    const ended = this.store.lastTurn(key)?.endedAt;
    if (typeof ended !== "number" || ended < this.since || this.ended.get(key) === ended) return;
    this.ended.set(key, ended);
    this.ask("turnNotices", { key, since: this.since, ended: null, lang: stationLang() });
  }

  /// People's messages and the station's ⚠️ in its own chats.
  private said(thread: number, entries: { kind: string; authorKind: string; text: string | null; at: number }[]) {
    const worth = entries.some((e) => e.kind === "message" && e.at >= this.since && (e.authorKind === "person" || (e.authorKind === "ember" && (e.text ?? "").startsWith("⚠️"))));
    if (worth) this.ask("saidNotices", { thread, entries, since: this.since, lang: stationLang() });
  }

  private ask(op: string, args: unknown) {
    void this.readers.read(op, args, stationLang()).then(
      (text) => {
        const answer = JSON.parse(text);
        this.queue(Array.isArray(answer) ? answer : answer.notices);
      },
      (error) => log.warn("notify", "a notice could not be made", { error: (error as Error).message }),
    );
  }

  private queue(notices: Notice[]) {
    if (notices.length === 0) return;
    this.waiting.push(...notices);
    this.timer ??= setTimeout(() => {
      this.timer = null;
      const batch = this.waiting.splice(0, MAX_BATCH);
      if (this.waiting.length > 0) this.queue(this.waiting.splice(0));
      if (this.cloud.removed() || this.cloud.state === null) return;
      this.post(batch).then(
        () => log.info("notify", "notices sent", { n: batch.length }),
        (error) => log.warn("notify", "notices dropped", { n: batch.length, error: (error as Error).message }),
      );
    }, GATHER_MS);
  }

  /// One batch, signed over "ember-station-notify-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>", its headers
  /// under both names.
  private async send(notices: Notice[]) {
    await signedPost(this.cloud, this.key, "/v1/stations/notify", "ember-station-notify-v1", { notices }, true);
  }
}
