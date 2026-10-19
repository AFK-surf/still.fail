// Test vectors for mbui/core's delta applier (src/core/delta.mbt), written as a MoonBit test file: values shaped like
// the core's topics, their changes diffed by ember's core-ts (collections.ts `diffKeyed`: keyed ops where the topic's
// spec says, the plain ones elsewhere) and applied by it (`applyKeyed`), so the MoonBit applier is held to the core's
// own result; then ops that do not fit their value, which the core skips. Seeded, so the file is the same each time.
//   EMBER=<ember checkout> node core/delta-vectors.ts > src/core/vectors_test.mbt      (scripts/core.sh vectors)
const ember = process.env.EMBER;
if (!ember) throw new Error("EMBER: an ember checkout");
const { diffKeyed, applyKeyed, specOf } = await import(`${ember}/client/core-ts/src/collections.ts`);

type V = unknown;
const out: { name: string; old: V; ops: V[]; want: V }[] = [];

function diffed(name: string, topic: string, old: V, next: V) {
  const ops = diffKeyed(old, next, specOf({ topic }));
  const want = applyKeyed(old, ops);
  if (JSON.stringify(want) !== JSON.stringify(next)) throw new Error(`core-ts does not round-trip ${name}`);
  out.push({ name, old, ops, want });
}

function given(name: string, old: V, ops: V[]) {
  out.push({ name, old, ops, want: applyKeyed(old, ops) });
}

// ── values shaped like the topics ──

const account = (n: number) => ({ sub: `google-${n}`, email: `user${n}@example.com`, name: `用户 ${n}`, picture: "" });
diffed("accounts: the first sign-in", "accounts", [], [account(1)]);
diffed("accounts: another", "accounts", [account(1)], [account(1), account(2)]);
diffed("accounts: one signs out", "accounts", [account(1), account(2)], [account(2)]);
diffed("accounts: a name changes", "accounts", [account(1)], [{ ...account(1), name: "Ada 👋" }]);

const thread = (id: string, seq: number, text: string, unread = 0) => ({ id, title: `chat ${id}`, last: { seq, text, at: 1790000000000 + seq * 1000.5 }, unread, people: ["a", "b"] });
const threads = ["t1", "t2", "t3", "t4", "t5"].map((id, i) => thread(id, i, `第 ${i} 条`));
diffed("threads: one moves to the top", "threads", threads, [thread("t4", 9, "new"), ...threads.filter((t) => t.id !== "t4")]);
diffed("threads: one changes in place", "threads", threads, threads.map((t) => (t.id === "t2" ? { ...t, unread: 3 } : t)));
diffed("threads: a new one first", "threads", threads, [thread("t9", 10, "hello"), ...threads]);
diffed("threads: one gone", "threads", threads, threads.filter((t) => t.id !== "t3"));
diffed("threads: all of it at once", "threads", threads, [thread("t5", 11, "x", 1), thread("t9", 12, "y"), threads[0], { ...threads[2], title: "renamed" }, threads[1]]);

const msg = (seq: number, outgoing: boolean, text: string) => ({ seq, outgoing, text, at: seq * 60000 });
const chat = { draft: "写到一半", messages: [msg(1, false, "hi"), msg(2, true, "hello"), msg(3, false, "?")], outbox: [{ id: "o1", text: "sending" }] };
diffed("chat: a message comes", "chat", chat, { ...chat, messages: [...chat.messages, msg(4, false, "new")] });
diffed("chat: the outbox empties, the message lands", "chat", chat, { ...chat, outbox: [], messages: [...chat.messages, msg(4, true, "sending")] });
diffed("chat: an edit, and the draft gone", "chat", chat, { messages: chat.messages.map((m) => (m.seq === 2 ? { ...m, text: "edited" } : m)), outbox: chat.outbox });

const row = (station: string, id: string, title: string) => ({ station, id, title });
const chats = { days: [{ daysAgo: 0, items: [row("w/s1", "a", "A"), row("w/s2", "a", "A2")] }, { daysAgo: 1, items: [row("w/s1", "b", "B")] }] };
diffed("chats: a row moves to today", "chats", chats, { days: [{ daysAgo: 0, items: [row("w/s1", "b", "B!"), ...chats.days[0].items] }] });
diffed("chats: a day comes", "chats", chats, { days: [{ daysAgo: 0, items: [] }, ...chats.days.map((d) => ({ ...d, daysAgo: d.daysAgo + 1 }))] });

const live = { loaded: false, first: 800, timeline: [{ kind: "say", text: "a" }], usage: null, steps: [{ id: 1, ended: false }], phase: null };
diffed("live: the timeline grows", "live", live, { ...live, loaded: true, timeline: [...live.timeline, { kind: "tool", text: "b" }, { kind: "say", text: "c" }] });
diffed("live: a step ends, the phase starts", "live", live, { ...live, steps: [{ id: 1, ended: true }], phase: { phase: "requesting", since: 1790000000000 }, usage: { modelCalls: 3, cost: 0.0123 } });
diffed("live: a whole new value", "live", live, [1, 2, 3]);

const many = Array.from({ length: 300 }, (_, i) => thread(`m${i}`, i, `${i}`));
diffed("threads: a long list loaded after its first screen", "threads", many.slice(0, 20), many);

// ── random changes to keyed lists, seeded ──

let seed = 12345;
const rand = (n: number) => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff), seed % n);
for (let round = 0; round < 40; round++) {
  const old = Array.from({ length: 1 + rand(12) }, (_, i) => thread(`r${i}`, i, `t${i}`, rand(3)));
  const next = old.slice();
  for (let k = 1 + rand(4); k > 0; k--) {
    const what = rand(4);
    if (what === 0 && next.length > 0) next.splice(rand(next.length), 1);
    else if (what === 1) next.splice(rand(next.length + 1), 0, thread(`n${round}-${k}`, 100 + k, "new"));
    else if (what === 2 && next.length > 1) next.splice(rand(next.length), 0, ...next.splice(rand(next.length), 1));
    else if (next.length > 0) {
      const i = rand(next.length);
      next[i] = { ...next[i], unread: next[i].unread + 1, last: { ...next[i].last, text: "changed" } };
    }
  }
  diffed(`threads: random ${round}`, "threads", old, next);
}

// ── ops that do not fit their value: skipped, as the core does ──

const obj = { a: { b: [1, 2, 3] }, s: "x" };
given("set: through a key not there", obj, [{ path: ["nope", "deeper"], set: 1 }]);
given("set: a key not there, last on the path", obj, [{ path: ["a", "c"], set: { new: true } }]);
given("set: an index past the end", obj, [{ path: ["a", "b", 3], set: 9 }]);
given("set: an index into an object", obj, [{ path: ["a", 0], set: 9 }]);
given("set: a key into an array", obj, [{ path: ["a", "b", "x"], set: 9 }]);
given("set: the whole value", obj, [{ path: [], set: null }]);
given("set: null at a key", obj, [{ path: ["s"], set: null }]);
given("append: to what is not an array", obj, [{ path: ["s"], append: [1] }]);
given("append: then set in it", obj, [{ path: ["a", "b"], append: [4, 5] }, { path: ["a", "b", 4], set: "five" }]);
given("remove: a key", obj, [{ path: ["a"], remove: true }]);
given("remove: a key not there", obj, [{ path: ["zz"], remove: true }]);
given("remove: at the root", obj, [{ path: [], remove: true }]);
given("remove: an index", obj, [{ path: ["a", "b", 0], remove: true }]);
const list = { items: [{ id: "a", v: 1 }, { id: "b", v: 2 }, { id: "c", v: 3 }] };
const k = { path: ["items"], key: ["id"] };
given("keyed: on what is not a list", list, [{ ...k, path: [], drop: "a" }]);
given("keyed: drop one not there", list, [{ ...k, drop: "zz" }]);
given("keyed: patch one not there", list, [{ ...k, patch: "zz", ops: [{ path: ["v"], set: 0 }] }]);
given("keyed: move one not there", list, [{ ...k, move: "zz", before: "a" }]);
given("keyed: move before one not there", list, [{ ...k, move: "a", before: "zz" }]);
given("keyed: move to the end", list, [{ ...k, move: "a", before: null }]);
given("keyed: put one there, in place", list, [{ ...k, put: { id: "b", v: 20 } }]);
given("keyed: put one there, before another", list, [{ ...k, put: { id: "c", v: 30 }, before: "a" }]);
given("keyed: put one there, at the end", list, [{ ...k, put: { id: "a", v: 10 }, before: null }]);
given("keyed: put a new one, no before", list, [{ ...k, put: { id: "d", v: 4 } }]);
given("keyed: patch, nested keyed", { rows: [{ id: "x", sub: [{ id: 1 }, { id: 2 }] }] }, [{ path: ["rows"], key: ["id"], patch: "x", ops: [{ path: ["sub"], key: ["id"], drop: 1 }] }]);
given("keyed: two fields, one missing", { rows: [{ s: "w/1", id: "a" }, { s: "w/1" }] }, [{ path: ["rows"], key: ["s", "id"], drop: ["w/1", null] }]);
given("keyed: an item not an object", { rows: [1, { id: null }] }, [{ path: ["rows"], key: ["id"], drop: null }]);

// ── as a MoonBit test file ──

const lines = [
  "// Generated by core/delta-vectors.ts from ember's core-ts (collections.ts diffKeyed, applyKeyed): do not edit.",
  "// `want` is what core-ts's applyKeyed makes of `old` and `ops`.",
  "",
];
for (const v of out) {
  lines.push("///|", `test ${JSON.stringify(`core-ts: ${v.name}`)} {`, "  let v =", `    #|${JSON.stringify(v)}`, "  check_vector(v)", "}", "");
}
process.stdout.write(lines.join("\n"));
