import assert from "node:assert/strict";
import { chmodSync, cpSync, mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

// Run the real rerecord entry with a small fake station and replay. This isolates its exit and restoration behavior
// without a live core; the real recording and replay are checked separately on a test station.
const scripts = dirname(fileURLToPath(import.meta.url));
function run(options = {}) {
  const root = mkdtempSync(join(tmpdir(), "rerecord-check-"));
  const app = join(root, "apps", "mbui");
  const put = (path, text, executable = false) => {
    const target = join(root, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, text);
    if (executable) chmodSync(target, 0o755);
  };
  try {
    mkdirSync(join(app, "scripts"), { recursive: true });
    for (const file of ["rerecord.sh", "e2e-paths.sh", "recording-privacy.mjs"]) {
      cpSync(join(scripts, file), join(app, "scripts", file));
    }
    put("bin/moon", "#!/bin/sh\nexit 0\n", true);
    put("apps/mbui/scripts/env.sh", `A="$(cd "$(dirname "${"${BASH_SOURCE[0]}"}")/.." && pwd)"
moon_tests() {
  if [ -n "${"${FLOW_EMIT:-}"}" ]; then printf '# flow complete\\n' > "$FLOW_EMIT"; return 0; fi
  printf 'replay\\n' >> "$RECORD_TEST_REPLAYS"
  printf 'Total tests: 1, passed: 1, failed: 0.\\n'
  if [ ! -f "$RECORD_TEST_SATISFIED" ]; then printf 'kept-answers-ask {"call":"markdown"}\\n'; fi
  if [ "$RECORD_TEST_REPLAY_FAIL" = 1 ]; then return 2; fi
  return 0
}
`);
    put("apps/mbui/scripts/e2e-local.sh", "#!/bin/sh\nexit 0\n", true);
    put("apps/mbui/e2e/run.sh", `#!/bin/sh
mkdir -p out/e2e/mac
printf 'DRIVE PASS\\n' > out/e2e/mac/01-demo.log
printf 'PASS demo\\n'
`, true);
    put("apps/mbui/scripts/trace", `#!/bin/sh
case "$1" in
  mark) exit 0 ;;
  maxbytes) echo 64 ;;
  make) printf '{"host":{"localStation":null},"which":"new"}\\n' > "$RECORD_TEST_APP/e2e/traces/$3.trace" ;;
  diff) exit 0 ;;
  *) exit 1 ;;
esac
`, true);
    put("apps/mbui/src/sfreplay/flows/demo_test.mbt", '@sfreplay.trace("demo")\n');
    const trace = join(app, "e2e/traces/demo.trace");
    const old = '{"host":{"localStation":null},"which":"old"}\n';
    put("apps/mbui/e2e/traces/demo.trace", old);
    put("client/core-ts/scripts/kept-answers.ts", `const fs = require("node:fs");
fs.appendFileSync(process.env.RECORD_TEST_GENERATIONS, "generate\\n");
if (process.env.RECORD_TEST_GENERATOR_FAIL === "1") process.exit(1);
if (process.env.RECORD_TEST_KEEP_MISSING !== "1") fs.writeFileSync(process.env.RECORD_TEST_SATISFIED, "ok");
`);
    const replays = join(root, "replays");
    const generations = join(root, "generations");
    const env = {
      ...process.env,
      PATH: `${join(root, "bin")}:${process.env.PATH}`,
      E2E_WORK: join(root, "work"),
      E2E_STATION: join(root, "station"),
      RECORD_TEST_APP: app,
      RECORD_TEST_REPLAYS: replays,
      RECORD_TEST_GENERATIONS: generations,
      RECORD_TEST_SATISFIED: join(root, "satisfied"),
      RECORD_TEST_GENERATOR_FAIL: options.generatorFail ? "1" : "0",
      RECORD_TEST_KEEP_MISSING: options.keepMissing ? "1" : "0",
      RECORD_TEST_REPLAY_FAIL: options.replayFail ? "1" : "0",
    };
    for (const name of ["E2E_PRIVATE_TERMS_FILE", "E2E_KEEP", "E2E_START", "FLOW_EMIT", "KEEP_NEW", "MAX_BYTES"]) delete env[name];
    if (options.keepNew) env.KEEP_NEW = "1";
    if (options.alreadyKept) writeFileSync(env.RECORD_TEST_SATISFIED, "ok");
    const result = spawnSync("bash", [join(app, "scripts/rerecord.sh"), "demo"], { cwd: app, env, encoding: "utf8" });
    const lines = (path) => { try { return readFileSync(path, "utf8").trim().split("\n").length; } catch { return 0; } };
    // (the take a failing replay leaves beside the run's logs, out/rerecord.*/demo.failed.trace: null where none)
    let failed = null;
    try {
      for (const dir of readdirSync(join(app, "out"))) {
        try { failed = readFileSync(join(app, "out", dir, "demo.failed.trace"), "utf8"); } catch {}
      }
    } catch {}
    return { status: result.status, output: result.stdout + result.stderr, trace: readFileSync(trace, "utf8"), old, failed, replays: lines(replays), generations: lines(generations) };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("rerecord fills missing answers and reruns even when the first replay exits zero", () => {
  const r = run();
  assert.equal(r.status, 0, r.output);
  assert.equal(r.replays, 2);
  assert.equal(r.generations, 1);
  assert.equal(JSON.parse(r.trace).which, "new");
});

test("rerecord keeps a successful replay without generating unnecessary answers", () => {
  const r = run({ alreadyKept: true });
  assert.equal(r.status, 0, r.output);
  assert.equal(r.replays, 1);
  assert.equal(r.generations, 0);
  assert.equal(JSON.parse(r.trace).which, "new");
});

test("rerecord restores the old trace when a replay fails without missing answers", () => {
  const r = run({ alreadyKept: true, replayFail: true });
  assert.notEqual(r.status, 0, r.output);
  assert.equal(r.generations, 0);
  assert.equal(r.trace, r.old);
});

test("rerecord keeps the take its replay fails over, beside the run's logs, and says where", () => {
  const r = run({ alreadyKept: true, replayFail: true });
  assert.notEqual(r.status, 0, r.output);
  assert.equal(r.trace, r.old);
  assert.equal(JSON.parse(r.failed).which, "new");
  assert.match(r.output, /the take that fails is kept: .*demo\.failed\.trace/);
});

test("rerecord keeps no failing take where the replay passes", () => {
  const r = run({ alreadyKept: true });
  assert.equal(r.status, 0, r.output);
  assert.equal(r.failed, null);
});

test("rerecord restores the old trace when generating answers fails", () => {
  const r = run({ generatorFail: true });
  assert.notEqual(r.status, 0, r.output);
  assert.equal(r.replays, 1);
  assert.equal(r.generations, 1);
  assert.equal(r.trace, r.old);
});

test("rerecord fails and restores the old trace when answers remain missing after retries", () => {
  const r = run({ keepMissing: true });
  assert.notEqual(r.status, 0, r.output);
  assert.equal(r.replays, 9);
  assert.equal(r.generations, 8);
  assert.equal(r.trace, r.old);
});

test("KEEP_NEW retains the new trace but still reports missing answers as a failure", () => {
  const r = run({ generatorFail: true, keepNew: true });
  assert.notEqual(r.status, 0, r.output);
  assert.equal(JSON.parse(r.trace).which, "new");
});
