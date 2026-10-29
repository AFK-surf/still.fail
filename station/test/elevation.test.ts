// Running a Windows station as administrator from its page (elevation/elevation.ts): what the overview says, a change
// whose prompt is refused or never answered leaving the station as it was, one that restarted it said done or put back,
// and the scripts that do it elevated. Windows' side is a fake PowerShell; a temporary data directory.
import assert from "node:assert/strict";
import type { ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import type { Request } from "../src/api/request.ts";
import { ASK_MS, Elevation, applyScript, askScript, restartScript } from "../src/elevation/elevation.ts";
import { elevationRoutes } from "../src/elevation/module.ts";

/// A station's data and app, as install.ps1 leaves them (its hidden launcher there).
function installed(windows?: unknown) {
  const data = realpathSync(mkdtempSync(join(tmpdir(), "stillfail-elevation-")));
  const app = join(data, "app");
  mkdirSync(join(app, "mesh", "target", "release"), { recursive: true });
  writeFileSync(join(app, "mesh", "target", "release", "stillfail-station-w.exe"), "");
  mkdirSync(join(data, "run"));
  if (windows !== undefined) writeFileSync(join(data, "windows.json"), JSON.stringify(windows));
  return { data, app };
}

/// A PowerShell that ends as it is told.
function fakeShell() {
  const ran: { script: string; child: ChildProcess & EventEmitter; killed: boolean }[] = [];
  const run = (script: string) => {
    const child = new EventEmitter() as ChildProcess & EventEmitter;
    const one = { script, child, killed: false };
    (child as any).kill = () => ((one.killed = true), true);
    ran.push(one);
    return child;
  };
  return { ran, run };
}

async function station(o: { windows?: unknown; elevated?: boolean; admin?: boolean; data?: { data: string; app: string } }) {
  const paths = o.data ?? installed(o.windows);
  const shell = fakeShell();
  let changes = 0;
  const e = new Elevation({ ...paths, now: () => Date.now(), changed: () => void changes++, probe: async () => ({ elevated: o.elevated ?? false, admin: o.admin ?? true }), run: shell.run });
  await e.start();
  return { e, shell, paths, changes: () => changes };
}

const elevated = (data: string, step: string, want = true) => writeFileSync(join(data, "run", "elevation.json"), JSON.stringify({ want, at: 1, step }));

test("the overview says the setting, how it runs and whether its user can be elevated", async () => {
  const a = await station({ windows: { admin: true }, elevated: true });
  assert.deepEqual(a.e.view(true), { on: true, elevated: true, canElevate: true, manage: true });
  const b = await station({ admin: false });
  assert.deepEqual(b.e.view(false), { on: false, elevated: false, canElevate: false, manage: false });
  assert.throws(() => b.e.change(true), { key: "notAdmin" });
  assert.equal(b.shell.ran.length, 0);
});

test("switched on: Windows asks in a PowerShell of the station's, which a refusal ends with the station as it was", async () => {
  const s = await station({ windows: { task: "apart" } });
  s.e.change(true);
  assert.equal(s.shell.ran.length, 1);
  assert.match(s.shell.ran[0]!.script, /-Verb RunAs/);
  assert.equal(s.e.view(true).step, "asking");
  assert.throws(() => s.e.change(false), { key: "busy" }, "one change at a time");
  // The scripts it runs elevated name the station's own task (windows.json's).
  const apply = readFileSync(join(s.paths.data, "run", "elevation-apply.ps1"), "utf8");
  assert.match(apply, /Level 'apart' 'Highest'/);
  assert.match(apply, /Register-ScheduledTask -TaskName 'apart elevation'/);
  s.shell.ran[0]!.child.emit("exit", 4);
  const v = s.e.view(true);
  assert.equal(v.failed, "declined");
  assert.equal(v.step, undefined);
  assert.equal(v.on, false, "nothing changed");
  s.e.stop();
});

test("a prompt nobody answers (the secure desktop no remote screen shows) is given up, the station as it was", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] });
  const s = await station({});
  s.e.change(true);
  t.mock.timers.tick(ASK_MS - 1);
  assert.equal(s.e.view(true).step, "asking");
  t.mock.timers.tick(1);
  assert.equal(s.shell.ran[0]!.killed, true);
  assert.equal(s.e.view(true).failed, "unanswered");
  // Answered after all, late: the elevated side does nothing past the deadline it was given.
  const apply = readFileSync(join(s.paths.data, "run", "elevation-apply.ps1"), "utf8");
  const deadline = Number(/-gt (\d+)\) \{ exit 3 \}/.exec(apply)![1]);
  assert.equal(deadline, Date.now());
  assert.ok(apply.indexOf("exit 3") < apply.indexOf("Level 'still.fail station'"), "checked before anything is changed");
  s.e.stop();
});

test("answered: what the elevated side says is shown; nothing heard from it in a minute, the change is over", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] });
  const s = await station({});
  s.e.change(true);
  s.shell.ran[0]!.child.emit("exit", 0);
  elevated(s.paths.data, "applying");
  t.mock.timers.tick(1000);
  assert.equal(s.e.view(true).step, "applying");
  t.mock.timers.tick(60_000);
  assert.equal(s.e.view(true).failed, "error");
  // Said restarting: left so for the station that comes up.
  const r = await station({});
  r.e.change(true);
  r.shell.ran[0]!.child.emit("exit", 0);
  elevated(r.paths.data, "restarting");
  t.mock.timers.tick(120_000);
  assert.equal(r.e.view(true).step, "restarting");
});

test("after the restart: running as wanted is done; not, it is said not to have started so", async () => {
  const ok = installed({ admin: true });
  elevated(ok.data, "restarting");
  const a = await station({ data: ok, elevated: true });
  assert.deepEqual(a.e.view(true), { on: true, elevated: true, canElevate: true, manage: true });
  const put = installed();
  elevated(put.data, "restarting");
  const b = await station({ data: put, elevated: false });
  assert.equal(b.e.view(true).failed, "notStarted");
  assert.equal(b.e.view(true).want, true);
  // A change of a process gone (its prompt never answered) is over.
  const gone = installed();
  elevated(gone.data, "asking");
  assert.deepEqual((await station({ data: gone })).e.view(true).step, undefined);
});

test("an elevated station goes back without a prompt, and one already running as wanted is not restarted", async () => {
  const s = await station({ windows: { admin: true }, elevated: true });
  s.e.change(false);
  assert.doesNotMatch(s.shell.ran[0]!.script, /RunAs/);
  const apply = readFileSync(join(s.paths.data, "run", "elevation-apply.ps1"), "utf8");
  assert.match(apply, /Level 'still\.fail station' 'Limited'/);
  assert.match(apply, /Start-ScheduledTask/);
  s.e.stop();
  const same = await station({ elevated: true });
  same.e.change(true);
  assert.doesNotMatch(readFileSync(join(same.paths.data, "run", "elevation-apply.ps1"), "utf8"), /Start-ScheduledTask/);
  same.e.stop();
});

test("the scripts: a refused prompt exits 4; the restart puts the task back when the station does not come up", () => {
  assert.match(askScript("C:\\d\\run\\elevation-apply.ps1", true), /NativeErrorCode -eq 1223\) \{ exit 4 \}/);
  const apply = applyScript({ run: "C:\\d\\run", data: "C:\\d", task: "still.fail station", on: true, deadline: 5, restart: true, runner: "C:\\d\\run\\w.exe" });
  assert.ok(apply.startsWith("\uFEFF"));
  // A failure puts the RunLevel and windows.json back as they were.
  assert.match(apply, /if \(\$was\) \{ try \{ Level 'still\.fail station' \$was \} catch \{\}; Keep \(\$was -eq 'Highest'\) \}/);
  const restart = restartScript({ run: "C:\\d\\run", data: "C:\\d", app: "C:\\d\\app", task: "still.fail station", on: true });
  assert.match(restart, /if \(-not \(Restart\)\) \{\r\n  try \{ Level \$task 'Limited' \} catch \{\}\r\n  Keep \$false\r\n  Note @\{ failed = 'notStarted' \}\r\n  Restart \| Out-Null/);
  // Its own task is removed at the end, whatever happened.
  assert.match(restart, /Unregister-ScheduledTask -TaskName 'still\.fail station elevation'/);
  for (const script of [apply, restart]) assert.doesNotMatch(script, /undefined|NaN/);
});

test("PUT /elevation: the workspace's owners and admins only; refused while a change is under way", async () => {
  const s = await station({});
  const [route] = elevationRoutes(s.e);
  const put = async (body: unknown, role = "owner") => {
    const r: Request = {
      method: "PUT", path: "/elevation", query: [], headers: {}, lang: "en", body: Buffer.from(JSON.stringify(body)),
      viewer: { sub: "s", email: "m@x.com", name: "M", role, workspace: "ws", device: "d" },
    };
    const a = await route!.handle(r, []);
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  assert.equal((await put({ on: true }, "member"))[0], 403);
  assert.equal((await put({ on: "yes" }))[0], 400);
  const [status, view] = await put({ on: true });
  assert.equal(status, 200);
  assert.equal(view.step, "asking");
  assert.equal((await put({ on: false }))[0], 409);
  s.e.stop();
});
