// A chat opens by looking up what it shows, never by working out anything else the device holds (2026-10-31: on a phone,
// chats took 0.5-0.9 s to open, each time for another of the kind: a station's lists and archive read whole for a link,
// the workspace lock's signatures checked again, Markdown read as it was shown). Over an account the size of a person's
// who uses still.fail every day, the app started anew, opening a chat reads a few rows of what is on the device: no
// list or archive whole, no signature checked, no Markdown read, nothing asked of a station. What its making costs is
// counted, not timed: a check that fails says what was done that need not have been.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Core } from "../src/core.ts";
import { rowsRead } from "../src/data.ts";
import { readAfresh } from "../src/markdown.ts";
import { HostWire } from "../src/station/wire.ts";
import { verifies } from "../src/vault/verified.ts";
import { subscribe } from "./helpers.ts";
import { type Answers, base, entry, session, started, threadView } from "./station-fixture.ts";

const N = 2000;
const ST = "ws/st";
const reply = (n: number) =>
  `## 第 ${n} 步\n\n改了 \`src/a${n}.ts\`，**测试**过了。见 https://app.still.fail/o/ws/st/${(n % 40) + 100} 和 https://app.still.fail/o/ws/st/old-${n % 30}\n\n- 一\n- 二\n\n\`\`\`ts\nconst x = ${n};\n\`\`\``;

function account(): Answers {
  const answers = base();
  // (each chat its own agent but chat 7's, k1's, as a person's chats are)
  const threads = Array.from({ length: N }, (_, i) => {
    const t = threadView(i + 1, i + 1 === 7 ? 60 : 3);
    return i + 1 === 7 ? t : { ...t, sessions: [{ thread: i + 1, session: `s${i}`, connect: "ember", joinedAt: 1 }] };
  });
  answers["GET /threads"] = threads;
  answers["GET /chats"] = threads.map((t) => ({ id: String(t.id), thread: t.id, session: t.id === 7 ? "k1" : `s${t.id - 1}`, title: `第 ${t.id} 个对话`, agents: [], lastActiveAt: t.id }));
  answers["GET /chats?archived=1"] = Array.from({ length: N }, (_, i) => ({ id: `old-${i}`, thread: null, session: `old-${i}`, title: `归档 ${i}`, agents: [], lastActiveAt: 1, archived: { at: 1, by: "auto" } }));
  answers["GET /sessions"] = [session("k1"), ...Array.from({ length: N }, (_, i) => session(`s${i}`))];
  const said = Array.from({ length: 50 }, (_, i) => {
    const n = 11 + i;
    return n % 2 === 0 ? { ...entry(n, reply(n)), authorKind: "agent", author: "k1" } : entry(n, `第 ${n} 条`);
  });
  answers["GET /threads/7/entries?limit=50"] = { last: 60, entries: said };
  return answers;
}

test("a_chat_opens_by_what_it_shows_whatever_else_the_device_holds", async () => {
  const { host, core } = await started(account());
  // all of it on the device, as the sync brought it (the archive as its page once showed it); then the app started anew
  subscribe(core, core.connect(), 9, { topic: "archivedRows", station: ST });
  await host.time.pass(10_000, 100);
  await core.close();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  try {
    await host.time.pass(10_000, 100);
    host.takeEmitted();
    const ui = again.connect();
    const [rows, md, checked, asked] = [rowsRead.count, readAfresh.chars, verifies.count, host.requests.length];
    rowsRead.by = new Map();
    subscribe(again, ui, 1, { topic: "chat", station: ST, thread: 7, session: null });
    let value: any;
    for (let i = 0; i < 20 && value === undefined; i++) {
      await host.time.pass(10, 10);
      value = host.takeEmitted().map(([, m]) => m as any).find((m) => m.id === 1 && "value" in m)?.value;
    }
    const by = [...rowsRead.by.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([q, n]) => `${n} ${q.slice(0, 160)}`);
    rowsRead.by = undefined;
    const spent = { by, rows: rowsRead.count - rows, md: readAfresh.chars - md, checked: verifies.count - checked, asked: host.requests.slice(asked).map((r) => r.url) };
    assert.ok(value?.messages?.length === 50, JSON.stringify(spent));
    assert.ok(value.messages.some((m: any) => (m.chats ?? []).some((c: any) => c.archived)), "its links said, an archived one so");
    assert.deepEqual({ md: spent.md, checked: spent.checked, asked: spent.asked }, { md: 0, checked: 0, asked: [] }, JSON.stringify(spent));
    // (its window of entries, its row, its agents', the rows its links name: a few hundred at most, not the thousands
    // of the station's lists)
    assert.ok(spent.rows <= 300, JSON.stringify(spent));
  } finally {
    await again.close();
  }
});
