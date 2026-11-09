// A job's reads (`job`, `jobLog`) answered by the MoonBit reader (station/mb src/readops; read/pool.ts MOVED) as the
// worker answers them: jobs with and without notices, logs missing, empty, with CRLF, a byte order mark, bytes not
// UTF-8 and more than the 64 KB read, every kind of `lines`, and a job that is not there.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

test("the MoonBit reader answers a job's reads as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-jobs-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const logs: Record<string, string | Buffer | null> = {
    none: null, empty: "", crlf: "one\r\ntwo\r\nthree\r\n", bom: "﻿first\nsecond", bad: Buffer.from([0x61, 0xff, 0x0a, 0x62, 0xe2, 0x82]),
    big: Array.from({ length: 5000 }, (_, i) => `line ${i} ${"x".repeat(20)}`).join("\n"),
  };
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1, ws: null } as Parameters<Store["insertSession"]>[0]);
  for (const [name, text] of Object.entries(logs)) {
    const log = join(data, `${name}.log`);
    if (text !== null) writeFileSync(log, text);
    store.insertJob({ id: name, sessionKey: "s", name: `job ${name}`, command: "run", cwd: name === "crlf" ? "" : "/c",
      port: name === "big" ? 8080 : null, token: `t-${name}`, state: "running", pgid: 7, exitCode: null, startedAt: 10, endedAt: null,
      restarts: 1, log, watch: name === "bom" });
  }
  store.db.prepare("UPDATE jobs SET watch = 2 WHERE id = 'empty'").run();
  for (let i = 0; i < 25; i++) store.db.prepare("INSERT INTO job_notices (job_id, at, text) VALUES (?, ?, ?)").run("crlf", 100 + (i % 7), `notice ${i}`);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  try {
    for (const id of [...Object.keys(logs), "missing"]) {
      assert.deepEqual(await read(program, "job", { id }), await read(worker, "job", { id }), `job ${id}`);
      for (const lines of [undefined, "5", "+3", "0", "abc", "2000", 7, "", "18446744073709551616"])
        assert.deepEqual(await read(program, "jobLog", { id, lines }), await read(worker, "jobLog", { id, lines }), `log ${id} ${lines}`);
    }
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
