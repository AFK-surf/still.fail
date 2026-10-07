// Components (src/components): real processes in temporary data directories. Each test has its own directory and its
// own Components; what one leaves running is killed after. Waits are for a condition, with a deadline, never a fixed time.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { Components, parseDeclaration, specOf } from "../src/components/components.ts";
import { groupAlive, pidAlive, signalGroup } from "../src/jobs/group.ts";

const dirs: string[] = [];
const groups = new Set<number>();
const open: Components[] = [];
after(async () => {
  for (const c of open) await c.close().catch(() => undefined);
  for (const pgid of groups) signalGroup(pgid, "SIGKILL");
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function data(): string {
  const d = mkdtempSync(join(tmpdir(), "components-test-"));
  dirs.push(d);
  return d;
}

function components(dir: string): Components {
  const c = new Components({ data: dir });
  open.push(c);
  return c;
}

/// A component that says it started (its pid, a line in `mark`) and then runs until ended, or ends with `code`.
function declare(dir: string, name: string, mark: string, options: { code?: number; version?: string } = {}) {
  mkdirSync(join(dir, "components"), { recursive: true });
  const end = options.code === undefined ? "exec sleep 600" : `exit ${options.code}`;
  const declaration = { command: "/bin/sh", args: ["-c", `echo "$$ $GREETING" >> "${mark}"; ${end}`], env: { GREETING: "hi" }, version: options.version };
  writeFileSync(join(dir, "components", `${name}.json`), JSON.stringify(declaration));
}

function starts(mark: string): string[] {
  try {
    return readFileSync(mark, "utf8").trim().split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

async function until<T>(what: string, look: () => T | undefined | null | false, ms = 10_000): Promise<T> {
  const deadline = Date.now() + ms;
  for (;;) {
    const seen = look();
    if (seen) return seen;
    if (Date.now() > deadline) throw new Error(`not so within ${ms} ms: ${what}`);
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

function state(c: Components, name: string) {
  return c.list().find((s) => s.name === name) ?? null;
}

function running(c: Components, name: string) {
  const s = state(c, name);
  if (s?.state !== "running" || s.pgid === null) return null;
  groups.add(s.pgid);
  return s;
}

describe("declarations", () => {
  test("a declaration is checked", () => {
    assert.equal(parseDeclaration("{").ok, false);
    assert.deepEqual(parseDeclaration(JSON.stringify({ command: "rel/path" })), { ok: false, error: "command is not an absolute path" });
    assert.deepEqual(parseDeclaration(JSON.stringify({ command: "/bin/true", args: [1] })), { ok: false, error: "args is not a list of strings" });
    assert.deepEqual(parseDeclaration(JSON.stringify({ command: "/bin/true", env: { A: 1 } })), { ok: false, error: "env is not an object of strings" });
    const ok = parseDeclaration(JSON.stringify({ command: "/bin/true" }));
    assert.deepEqual(ok, { ok: true, declaration: { command: "/bin/true", args: [], env: {}, cwd: null, version: null } });
  });

  test("the same declaration is the same spec, whatever the order of its environment", () => {
    const a = { command: "/bin/true", args: [], env: { A: "1", B: "2" }, cwd: null, version: "1" };
    const b = { ...a, env: { B: "2", A: "1" } };
    assert.equal(specOf(a), specOf(b));
    assert.notEqual(specOf(a), specOf({ ...a, version: "2" }));
  });
});

describe("components", () => {
  test("a declared component runs, with its environment, in a group of its own", async () => {
    const dir = data();
    const mark = join(dir, "mark");
    declare(dir, "connector", mark);
    const c = components(dir);
    await c.start();
    const s = await until("running", () => running(c, "connector"));
    const [line] = await until("started", () => starts(mark).length === 1 && starts(mark));
    assert.match(line, / hi$/);
    assert.ok(groupAlive(s.pgid!));
    assert.notEqual(s.pgid, process.pid);
  });

  test("one that ends is started again", async () => {
    const dir = data();
    const mark = join(dir, "mark");
    declare(dir, "flaky", mark, { code: 3 });
    const c = components(dir);
    await c.start();
    await until("started twice", () => starts(mark).length >= 2, 15_000);
    const s = await until("its end recorded", () => state(c, "flaky")?.lastExit?.code === 3 && state(c, "flaky"));
    assert.ok(s.restarts >= 1);
  });

  test("a changed declaration replaces it; a removed one ends it", async () => {
    const dir = data();
    const mark = join(dir, "mark");
    declare(dir, "connector", mark, { version: "1" });
    const c = components(dir);
    await c.start();
    const first = await until("running", () => running(c, "connector"));
    declare(dir, "connector", mark, { version: "2" });
    const second = await until("replaced", () => running(c, "connector")?.version === "2" && running(c, "connector"));
    assert.notEqual(second.pgid, first.pgid);
    await until("the first ended", () => !groupAlive(first.pgid!));
    rmSync(join(dir, "components", "connector.json"));
    await until("ended", () => !groupAlive(second.pgid!) && state(c, "connector") === null);
  });

  test("a declaration that cannot be run says why", async () => {
    const dir = data();
    mkdirSync(join(dir, "components"), { recursive: true });
    writeFileSync(join(dir, "components", "broken.json"), JSON.stringify({ command: "sh" }));
    const c = components(dir);
    await c.start();
    const s = await until("invalid", () => state(c, "broken")?.state === "invalid" && state(c, "broken"));
    assert.equal(s.error, "command is not an absolute path");
  });

  test("components outlive the station: the next one takes up the group still running", async () => {
    const dir = data();
    const mark = join(dir, "mark");
    declare(dir, "connector", mark);
    const one = components(dir);
    await one.start();
    const s = await until("running", () => running(one, "connector"));
    await one.close();
    assert.ok(pidAlive(s.pgid!), "it goes on without the station");
    const two = components(dir);
    await two.start();
    const taken = await until("taken up", () => running(two, "connector"));
    assert.equal(taken.pgid, s.pgid);
    assert.equal(starts(mark).length, 1, "not started again");
    // Followed by the new station: an end there is started again.
    signalGroup(s.pgid!, "SIGKILL");
    await until("started again", () => starts(mark).length === 2, 15_000);
  });
});
