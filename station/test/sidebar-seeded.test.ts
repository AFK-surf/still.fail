import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { makeStore } from "../src/read/store.ts";
import { chats, sharedChatRows } from "../src/read/views.ts";

// The sidebar over seeded stores (each seed one store, replayed the same every run): two viewers, chats of their own
// and from Slack, messages by either, the agents', where each read, what each pinned and kept, sessions archived. What
// a row says for a viewer is held to what the viewer did, as the station said it before it made the list once for
// everyone (#3793): 300 seeds gave the same rows, in the same order, with the same title, unread, mine, pin, kept, last
// message, connect, origin and agents for each viewer on dc3ac921b9^ and after it (2026-11-04).

const people = ["me@x.io", "ann@x.io"];
const viewerOf = (email: string) => ({ sub: email, email, name: email, role: "owner", workspace: "w", device: "d" }) as const;

function rng(seed: number) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

type World = {
  store: Store;
  said: Map<number, { n: number; kind: string; author: string; text: string }[]>;
  reads: Map<string, number>;
  pins: Set<string>;
  kept: Set<string>;
};

function world(seed: number): World {
  const r = rng(seed * 7919);
  const pick = <T>(xs: T[]): T => xs[Math.floor(r() * xs.length)]!;
  const store = Store.open(":memory:");
  let clock = 1000;
  const sessions: string[] = [];
  const threads: { id: number; session: string }[] = [];
  const n = 1 + Math.floor(r() * 5);
  for (let i = 0; i < n; i++) {
    const key = `ember:s${i}`;
    sessions.push(key);
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${i}`, token: key, createdAt: clock, lastActiveAt: clock + i, createdBy: pick([...people, null]), title: r() < 0.2 ? `会话${i}` : null });
    if (r() < 0.85) {
      const t = store.openThread("ember", "EMBER", `t${i}`, r() < 0.5 ? `对话${i}` : null, pick([...people, null])).id;
      store.joinThread(t, key, "ember");
      threads.push({ id: t, session: key });
    }
    if (r() < 0.35) {
      const t = store.openThread("slack", "C1", `17000${i}.1`, null, pick([...people, null])).id;
      store.joinThread(t, key, "slack-c");
      threads.push({ id: t, session: key });
    }
  }
  const said = new Map<number, { n: number; kind: string; author: string; text: string }[]>();
  for (const t of threads) {
    const list: { n: number; kind: string; author: string; text: string }[] = [];
    const m = Math.floor(r() * 7);
    for (let k = 0; k < m; k++) {
      clock += 10;
      const kind = r() < 0.5 ? "agent" : "person";
      const author = kind === "agent" ? t.session : pick(people);
      const text = r() < 0.1 ? "" : `话${k}`;
      const [at] = store.insertMessage({ thread: t.id, ts: `${clock}.0`, authorKind: kind as "agent" | "person", author, text, at: clock });
      list.push({ n: at, kind, author, text });
    }
    said.set(t.id, list);
  }
  const reads = new Map<string, number>();
  const pins = new Set<string>();
  const kept = new Set<string>();
  for (const v of people) {
    for (const t of threads) {
      if (r() < 0.6) {
        const upTo = Math.floor(r() * 8);
        store.setRead(v, t.id, upTo);
        reads.set(`${v} ${t.id}`, upTo);
      }
    }
    for (const s of sessions) if (r() < 0.2) { store.setPin(v, s, true); pins.add(`${v} ${s}`); }
    for (const t of threads) if (r() < 0.15) { store.keepChat(v, t.id); kept.add(`${v} ${t.id}`); }
  }
  for (const s of sessions) if (r() < 0.15) store.setArchived(s, true, "me@x.io");
  return { store, said, reads, pins, kept };
}

test("seeded stores: each viewer's sidebar is the one list with their own reads, pins and kept chats on it", () => {
  for (let seed = 1; seed <= 300; seed++) {
    const w = world(seed);
    try {
      const read = makeStore(w.store.db, "/no-station-config");
      const at = `seed ${seed}`;
      // One list for everyone: the same rows whoever asks.
      assert.deepEqual(sharedChatRows(read, viewerOf(people[1]!) as any, null, null), sharedChatRows(read, viewerOf(people[0]!) as any, null, null), at);
      for (const archived of [false, true]) {
        const lists = people.map((v) => chats(read, viewerOf(v) as any, archived));
        assert.deepEqual(lists[1]!.map((row) => row.id), lists[0]!.map((row) => row.id), `${at}: the same rows, in the same order`);
        for (const [i, v] of people.entries()) {
          for (const row of lists[i]!) {
            const where = `${at} ${v} ${archived ? "archive" : "list"} ${row.id}`;
            assert.equal(row.pinned !== null, w.pins.has(`${v} ${row.id}`), `${where}: pinned`);
            if (typeof row.thread !== "number" || archived) continue;
            const said = w.said.get(row.thread) ?? [];
            const upTo = w.reads.get(`${v} ${row.thread}`) ?? 0;
            // Unread: something said after where the viewer read that the viewer did not say.
            const unread = said.some((m) => m.n > upTo && !(m.kind === "person" && m.author === v));
            assert.equal(row.unread, unread, `${where}: unread (read to ${upTo}, said ${JSON.stringify(said)})`);
            assert.equal(row.archiveReminderDismissed, w.kept.has(`${v} ${row.thread}`), `${where}: kept`);
            const latest = said.at(-1);
            assert.equal(row.last?.text ?? null, latest === undefined ? null : latest.text, `${where}: its latest message`);
          }
        }
      }
    } finally { w.store.close(); }
  }
});
