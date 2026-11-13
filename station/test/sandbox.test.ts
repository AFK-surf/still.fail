// Sandboxes as targets of station_task (src/agents/sandbox.ts): what is the same every run. config.json's `sandboxes`,
// how a task's command is made, and what station_list says of one. Running a task there, against a stand-in ssh of
// real processes, is the side run's (side/sandbox.test.ts).
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { BRIDGE, checkSandboxes, sandboxCommand, sandboxDescribed, sandboxOf, sandboxesOf } from "../src/agents/sandbox.ts";
import { sandboxName } from "../src/agents/sandbox-name.ts";

/// The bridge specs a command made by sandboxCommand runs, in order.
function specs(command: string): any[] {
  const words = [...command.matchAll(/'((?:[^']|'\\'')*)'/g)].map((m) => m[1]!.replaceAll(`'\\''`, "'"));
  const out: any[] = [];
  for (let i = 0; i < words.length; i++) if (words[i] === BRIDGE && words[i + 1] === "host") out.push(JSON.parse(words[i + 2]!));
  return out;
}

describe("sandboxes", () => {
  test("config.json's sandboxes: a name, a front door with {name} where each sandbox's name goes, a size of its operator's", () => {
    const raw = { sandboxes: [{ name: "l4es-large", target: "{name}.team@l4es.afk.surf", size: "large" }, { name: "l4es", target: "{name}.team@l4es.afk.surf", identity: "/k" }] };
    checkSandboxes(raw);
    assert.deepEqual(sandboxesOf(raw), raw.sandboxes);
    assert.deepEqual(sandboxesOf({}), []);
    assert.throws(() => checkSandboxes({ sandboxes: {} }), /a list/);
    assert.throws(() => checkSandboxes({ sandboxes: [{ name: "x", target: "dev@l4es.afk.surf" }] }), /front door/);
    assert.throws(() => checkSandboxes({ sandboxes: [{ name: "x", target: "{name}.t@h", size: "Large 2" }] }), /size/);
    assert.throws(() => checkSandboxes({ sandboxes: [{ name: "x", target: "{name}.t@h", identity: "k" }] }), /identity/);
    assert.throws(() => checkSandboxes({ sandboxes: [{ name: "a b", target: "{name}.t@h" }] }), /name/);
    assert.throws(() => checkSandboxes({ sandboxes: [{ name: "x", target: "{name}.t@h" }, { name: "X", target: "{name}.u@h" }] }), /named twice/);
    // One not well formed is left out where the file has it anyway.
    assert.deepEqual(sandboxesOf({ sandboxes: [{ name: "x", target: "nope" }, { name: "y", target: "{name}.t@h" }] }).map((s) => s.name), ["y"]);
  });

  test("each chat has a sandbox of its own there, its name one the front door takes", () => {
    const d = { name: "l4es", target: "{name}.team@host" };
    assert.notEqual(sandboxOf(d, "s1"), sandboxOf(d, "s2"));
    assert.equal(sandboxOf(d, "s1"), sandboxName("l4es|s1"));
    assert.match(sandboxOf(d, "s1"), /^[a-z][a-z0-9-]{0,30}$/);
  });

  test("a task's command makes its sandbox of the size, copies its directory there and runs it; then brings back what it names", () => {
    const d = { name: "l4es", target: "{name}.team@host", size: "large" };
    const name = sandboxOf(d, "s1");
    const [run, back, ...rest] = specs(sandboxCommand("/data", d, { sandbox: "l4es", session: "s1", back: ["out", "logs/a.txt"] }, "make test", "/data/remote/w/src", [4750], "/data/jobs/exit/j.lost", "node"));
    assert.equal(rest.length, 0);
    assert.equal(run.ssh.at(-1), `${name}.team@host`);
    assert.deepEqual(run.create.slice(-4), ["create", name, "--size", "large"]);
    assert.equal(run.create.at(-5), "_.team@host");
    assert.ok(run.ssh.includes("BatchMode=yes") && run.ssh.includes("/data/run/sandbox/id_ed25519"));
    assert.deepEqual(run.root, { path: "/data" });
    assert.deepEqual(run.sync, [{ path: "/data/remote/w/src", mode: "whole", back: false, dir: true }]);
    assert.deepEqual([run.program, run.args, run.cwd, run.ports, run.lostFile], ["/bin/sh", ["-c", "make test"], "/data/remote/w/src", [4750], "/data/jobs/exit/j.lost"]);
    // What it brings back, after: nothing pushed, file or directory.
    assert.equal(back.program, undefined);
    assert.deepEqual(back.sync.map((e: any) => [e.path, e.push, e.dir]), [["/data/remote/w/src/out", false, false], ["/data/remote/w/src/logs/a.txt", false, false]]);
    // Nothing to bring back: the one bridge alone; no create without a size (its first connection makes one); a key given.
    const plain = specs(sandboxCommand("/data", { name: "l4es", target: "{name}.team@host", identity: "/keys/l4es" }, { sandbox: "l4es", session: "s1", back: [] }, "true", "/w", [], "/l", "node"));
    assert.equal(plain.length, 1);
    assert.equal(plain[0].create, undefined);
    assert.ok(plain[0].ssh.includes("/keys/l4es"));
  });

  test("station_list says a sandbox takes tasks and synced directories, and has no chats of its own", () => {
    const said = sandboxDescribed({ name: "l4es", target: "{name}.team@host", size: "large" }) as any;
    assert.equal(said.kind, "sandbox");
    assert.equal(said.size, "large");
    assert.equal(said.tasks, true);
    assert.equal(said.sync, 1);
    assert.equal(said.chats, false);
  });
});
