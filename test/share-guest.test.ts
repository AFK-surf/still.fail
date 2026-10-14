import assert from "node:assert/strict";
import { test } from "node:test";
import { GuestError, STREAMS, ask, guestFiles, parseSnapshot, readShared, shownAtOnce, type GuestConnection, type Progress, type Snapshot } from "../web/src/share/guest.ts";

// Reading a published chat from its station (web/src/share/guest.ts) over streams in memory: a request a stream, a JSON
// line, then exactly as many bytes as it said, however many; refusals; what is not an answer; a file the preview opens,
// read from what the page has or on a visit of its own. Each answer comes cut at several sizes.

const encode = (s: string) => new TextEncoder().encode(s);
const link = { station: "00".repeat(32), id: "AbCdEfGhIjKlMn_-", key: "k".repeat(43) };

/** An answer as a station writes it: its head line, then its bytes (and what a test puts after them). */
const answer = (head: unknown, body: Uint8Array = new Uint8Array(0), after = new Uint8Array(0)) => {
  const line = encode(`${JSON.stringify(head)}\n`);
  const out = new Uint8Array(line.length + body.length + after.length);
  out.set(line);
  out.set(body, line.length);
  out.set(after, line.length + body.length);
  return out;
};

/**
 * A station in memory: `serve` answers each request (its line, parsed) with bytes, handed out `cut` at a time. What
 * each stream was sent, whether it was finished, how many streams were being read at once at most.
 */
function station(serve: (request: Record<string, unknown>) => Uint8Array, cut: number) {
  const sent: string[] = [];
  let open = 0;
  let most = 0;
  const conn: GuestConnection = {
    openBi: async () => {
      open++;
      most = Math.max(most, open);
      let written = new Uint8Array(0);
      let finished = false;
      let out: Uint8Array | null = null;
      let at = 0;
      let done = false;
      return {
        write: async (bytes) => { written = Uint8Array.from([...written, ...bytes]); },
        finish: async () => {
          finished = true;
          const line = new TextDecoder().decode(written);
          sent.push(line);
          assert.ok(line.endsWith("\n"), "a request is one line");
          out = serve(JSON.parse(line));
        },
        read: async () => {
          assert.ok(finished, "the request is finished before its answer is read");
          await Promise.resolve();
          if (at >= out!.length) {
            if (!done) { done = true; open--; }
            return null;
          }
          const part = out!.subarray(at, at + cut);
          at += part.length;
          // Read to its end: no longer being read.
          if (at >= out!.length && !done) { done = true; open--; }
          return part;
        },
      };
    },
  };
  return { conn, sent, most: () => most };
}

const CUTS = [1, 3, 16, 1 << 16];

test("an answer is its head and exactly as many bytes as it says, however it comes cut", async () => {
  const body = Uint8Array.from({ length: 300 }, (_, i) => i % 256);
  for (const cut of CUTS) {
    // What comes after its bytes is not its: not taken, not waited for.
    const s = station(() => answer({ ok: true, size: body.length, type: "image/png" }, body, encode("more")), cut);
    const heard: Progress[] = [];
    const got = await ask(s.conn, { get: link.id, key: link.key, file: "f0" }, { progress: (p) => heard.push(p) });
    assert.equal(got.type, "image/png", `cut ${cut}`);
    assert.deepEqual(got.bytes, body, `cut ${cut}`);
    assert.deepEqual(s.sent, [`{"get":"${link.id}","key":"${link.key}","file":"f0"}\n`]);
    // How far it has come, as it comes: never back, all of it at the end.
    assert.ok(heard.length >= 1 && heard.every((p, i) => p.total === body.length && (i === 0 || p.loaded >= heard[i - 1]!.loaded)), `cut ${cut}: ${JSON.stringify(heard)}`);
    assert.equal(heard.at(-1)!.loaded, body.length);
    // Nothing: none.
    const empty = station(() => answer({ ok: true, size: 0 }), cut);
    assert.deepEqual(await ask(empty.conn, { get: link.id, key: link.key }), { type: "application/octet-stream", bytes: new Uint8Array(0) });
  }
});

test("an answer is taken however big it is: nothing caps what a station publishes", async () => {
  // Past the 10 MB an attachment could once be, and the 20 MB a snapshot could.
  const body = new Uint8Array(24 * 1024 * 1024);
  for (let i = 0; i < body.length; i += 4093) body[i] = i % 251;
  for (const cut of [1 << 16, 1 << 20]) {
    const got = await ask(station(() => answer({ ok: true, size: body.length, type: "application/pdf" }, body), cut).conn, { get: link.id, key: link.key, file: "f0" });
    assert.equal(got.bytes.length, body.length, `cut ${cut}`);
    assert.ok(Buffer.from(got.bytes).equals(Buffer.from(body)), `cut ${cut}`);
  }
});

test("a refusal says why: gone or busy; anything else that is not an answer is broken", async () => {
  const kind = async (bytes: Uint8Array, cut: number, most?: number) => {
    const err = await ask(station(() => bytes, cut).conn, { get: link.id, key: link.key }, most === undefined ? {} : { most }).then(() => null, (e: unknown) => e);
    assert.ok(err instanceof GuestError, String(err));
    return err.kind;
  };
  for (const cut of CUTS) {
    assert.equal(await kind(answer({ error: "no such snapshot", code: "gone" }), cut), "gone");
    assert.equal(await kind(answer({ error: "busy", code: "busy" }), cut), "busy");
    assert.equal(await kind(answer({ error: "what", code: "teapot" }), cut), "broken");
    assert.equal(await kind(new Uint8Array(0), cut), "broken", "nothing said");
    assert.equal(await kind(encode("{\"ok\":true,\"size\":3}"), cut), "broken", "no end to its head");
    assert.equal(await kind(encode("not json\n"), cut), "broken");
    assert.equal(await kind(answer([1, 2]), cut), "broken");
    assert.equal(await kind(answer({ ok: true }), cut), "broken", "no size");
    assert.equal(await kind(answer({ ok: true, size: -1 }), cut), "broken");
    assert.equal(await kind(answer({ ok: true, size: 1.5 }), cut), "broken");
    assert.equal(await kind(answer({ ok: true, size: 5 }, encode("abc")), cut), "broken", "ended short");
    assert.equal(await kind(answer({ ok: true, size: 101 }, new Uint8Array(101)), cut, 100), "broken", "more than it was asked to take");
    assert.equal(await kind(encode("x".repeat(20 * 1024)), cut), "broken", "a head that never ends");
  }
});

const snapshot: Snapshot = {
  v: 1, title: "Fix the login page", station: "studio", at: 1760500000000, by: "Alice", redacted: 2,
  entries: [
    { n: 1, at: 1760400000000, authorKind: "person", author: "Alice", text: "see ![](own.png)", files: [{ k: "f0", name: "own.png", size: 10, type: "image/png" }, { k: "f1", name: "notes.html", size: 20, type: "text/html" }] },
    { n: 2, at: 1760400001000, authorKind: "agent", author: "ember", text: "Here: ![](a.png) and\n\n[chart](chart.html)\n\nlog in [the log](run.log)", files: [
      { k: "f2", name: "a.png", size: 30, type: "image/png", width: 800, height: 600, thumbhash: "abc" },
      { k: "f3", name: "chart.html", size: 40, type: "text/html" },
      { k: "f4", name: "run.log", size: 50, type: "text/plain" },
      { k: "f5", name: "unplaced.html", size: 60, type: "text/html" },
      { k: "f6", name: "b.svg", size: 70, type: "image/svg+xml" },
    ] },
    { n: 3, at: 1760400002000, authorKind: "agent", author: "ember", text: "more", files: [1, 2, 3, 4].map((i) => ({ k: `f${6 + i}`, name: `shot${i}.jpg`, size: 5, type: "image/jpeg" })) },
  ],
};

test("a snapshot is read as the station writes it; what it lacks is nothing, a format it does not know broken", () => {
  assert.deepEqual(parseSnapshot(encode(JSON.stringify(snapshot))), snapshot);
  const sparse = parseSnapshot(encode(JSON.stringify({ v: 1, entries: [{ text: "hi", files: [{ k: "f0", name: "x.png" }, { name: "no k" }, null] }, "nonsense"], extra: true })));
  assert.deepEqual(sparse, { v: 1, title: "", station: "", at: 0, by: "", redacted: 0, entries: [{ n: 0, at: 0, authorKind: "person", author: "", text: "hi", files: [{ k: "f0", name: "x.png", size: 0, type: "application/octet-stream" }] }] });
  for (const bad of ["", "[]", "null", JSON.stringify({ ...snapshot, v: 2 }), JSON.stringify({ entries: [] })]) {
    assert.throws(() => parseSnapshot(encode(bad)), (e: unknown) => e instanceof GuestError && e.kind === "broken", bad);
  }
});

test("a visit reads the snapshot, then its images and the HTML its agents place, a few at a time", async () => {
  assert.deepEqual(shownAtOnce(snapshot).map((f) => f.k), ["f0", "f2", "f3", "f6", "f7", "f8", "f9", "f10"]);
  for (const cut of CUTS) {
    const bodies = new Map(shownAtOnce(snapshot).map((f) => [f.k, encode(`bytes of ${f.k}`)]));
    const s = station((r) => {
      if (r.get !== link.id || r.key !== link.key) return answer({ error: "no", code: "gone" });
      if (r.file === undefined) {
        const json = encode(JSON.stringify(snapshot));
        return answer({ ok: true, size: json.length, type: "application/json" }, json);
      }
      // One of them is refused: the others still come.
      if (r.file === "f7") return answer({ error: "busy", code: "busy" });
      const body = bodies.get(String(r.file))!;
      return answer({ ok: true, size: body.length, type: "image/png" }, body);
    }, cut);
    const heard: string[] = [];
    const read = await readShared(s.conn, link, {
      snapshot: (got) => heard.push(`snapshot ${got.entries.length}`),
      file: (k, got) => heard.push(got ? `${k} ${new TextDecoder().decode(got.bytes)}` : `${k} none`),
    });
    assert.deepEqual(read, snapshot);
    assert.equal(heard[0], "snapshot 3", "the snapshot first, alone");
    assert.deepEqual(heard.slice(1).sort(), ["f0 bytes of f0", "f10 bytes of f10", "f2 bytes of f2", "f3 bytes of f3", "f6 bytes of f6", "f7 none", "f8 bytes of f8", "f9 bytes of f9"]);
    // One request a stream, never the files not shown (run.log, the HTML no one placed, a person's HTML).
    assert.equal(s.sent.length, 9);
    assert.ok(!s.sent.some((line) => /"f(1|4|5)"/.test(line)), s.sent.join(""));
    assert.ok(s.most() <= STREAMS && s.most() > 1, `${s.most()} streams at once, cut ${cut}`);
  }
});

test("a visit whose snapshot is refused fails as it was refused, asking nothing more", async () => {
  for (const code of ["gone", "busy"] as const) {
    const s = station(() => answer({ error: "refused", code }), 16);
    const err = await readShared(s.conn, link, { snapshot: () => assert.fail("no snapshot"), file: () => assert.fail("no file") }).then(() => null, (e: unknown) => e);
    assert.ok(err instanceof GuestError && err.kind === code, String(err));
    assert.equal(s.sent.length, 1);
  }
});

test("the preview's files: what the page has read as it is, any other on a visit of its own, closed once read", async () => {
  const have = new Map([["f2", { type: "image/png", bytes: encode("png bytes") }]]);
  for (const cut of CUTS) {
    const visits: { closed: boolean; sent: string[] }[] = [];
    const log = encode("vitest run\n ✓ 16 passed\n");
    const files = guestFiles(link, (k) => have.get(k), async () => {
      const s = station((r) => {
        if (r.get !== link.id || r.key !== link.key) return answer({ error: "no", code: "gone" });
        if (r.file === "f4") return answer({ ok: true, size: log.length, type: "text/plain" }, log);
        if (r.file === "f7") return answer({ error: "busy", code: "busy" });
        return answer({ error: "no such file", code: "gone" });
      }, cut);
      const visit = { closed: false, sent: s.sent };
      visits.push(visit);
      return { conn: s.conn, close: async () => { visit.closed = true; } };
    });
    // An image the page has: no visit.
    const image = await files.file(link.id, { path: "f2" }, true);
    assert.equal(image.type, "image/png");
    assert.equal(await image.text(), "png bytes");
    assert.equal(visits.length, 0, `cut ${cut}`);
    // A log it has not: one visit, the one request, closed once read; how far it came, said.
    const heard: Progress[] = [];
    const read = await files.file(link.id, { path: "f4" }, false, (p) => heard.push(p));
    assert.equal(read.type, "text/plain");
    assert.deepEqual(new Uint8Array(await read.arrayBuffer()), log);
    assert.equal(visits.length, 1);
    assert.deepEqual(visits[0]!.sent, [`{"get":"${link.id}","key":"${link.key}","file":"f4"}\n`]);
    assert.ok(visits[0]!.closed, "the visit closed once read");
    assert.deepEqual(heard.at(-1), { loaded: log.length, total: log.length });
    // Refused: it says why, and the visit closes all the same.
    const err = await files.file(link.id, { path: "f7" }, false).then(() => null, (e: unknown) => e);
    assert.ok(err instanceof GuestError && err.kind === "busy", String(err));
    assert.equal(visits.length, 2);
    assert.ok(visits[1]!.closed, "a refused visit closed too");
  }
});

test("the preview's file from a station out of reach fails as the visit did, with nothing to close", async () => {
  const files = guestFiles(link, () => undefined, async () => { throw new Error("no answer"); });
  await assert.rejects(files.file(link.id, { path: "f4" }, false), /no answer/);
  // One the page could not read (null) is read again, not taken as read.
  let visited = 0;
  const again = guestFiles(link, () => null, async () => {
    visited++;
    return { conn: station(() => answer({ ok: true, size: 2, type: "image/png" }, encode("ok")), 16).conn, close: () => {} };
  });
  assert.equal(await (await again.file(link.id, { path: "f7" }, false)).text(), "ok");
  assert.equal(visited, 1);
});
