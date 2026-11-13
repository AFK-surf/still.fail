// A warm Android release builds a copy of apps/mbui, but vendored Java lives outside that copy in the checkout.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";

const script = readFileSync(new URL("../apps/mbui/scripts/beta.sh", import.meta.url), "utf8");
const marker = "| python3 -c '";
const start = script.indexOf(marker, script.indexOf("mirror() {")) + marker.length;
const end = script.indexOf("' \"$1\" \"$2\"", start);
assert.ok(start >= marker.length && end > start);
const copy = script.slice(start, end);

test("a warm release keeps external Java roots in the checkout and local roots in its copy", () => {
  const dir = mkdtempSync(join(tmpdir(), "stillfail-java-sources-"));
  try {
    const repo = join(dir, "checkout");
    const app = join(repo, "apps/mbui");
    const work = join(dir, "cache/work");
    const vendor = join(repo, "vendor/jzlib/src");
    const configs = ["android/apk.json"] as const;
    const files = [...configs, "android/app/src/main/java/App.java"] as const;
    const put = (path: string, text: string) => {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, text);
    };
    put(join(vendor, "Deflater.java"), "class Deflater {}");
    put(join(app, files[1]), "class App {}");
    for (const name of configs) {
      put(join(app, name), JSON.stringify({ java: ["app/src/main/java", "../../../vendor/jzlib/src"] }));
    }
    const git = spawnSync("git", ["init", "--quiet", repo], { encoding: "utf8" });
    assert.equal(git.status, 0, git.stderr);
    const run = () => {
      const result = spawnSync(process.platform === "win32" ? "python" : "python3", ["-c", copy, app, work], {
        cwd: app, input: files.join(String.fromCharCode(0)) + String.fromCharCode(0), encoding: "utf8",
      });
      assert.equal(result.status, 0, result.stderr);
    };
    const original = configs.map((name) => readFileSync(join(app, name), "utf8"));
    run();
    for (const [i, name] of configs.entries()) {
      const cached = join(work, name);
      const cfg = JSON.parse(readFileSync(cached, "utf8"));
      assert.equal(cfg.java[0], "app/src/main/java");
      assert.equal(resolve(dirname(cached), cfg.java[1]), resolve(vendor));
      assert.ok(existsSync(join(resolve(dirname(cached), cfg.java[1]), "Deflater.java")));
      assert.equal(readFileSync(join(app, name), "utf8"), original[i]);
    }
    assert.ok(existsSync(join(work, files[1])));
    // Unchanged sources keep their times; the cache's generated output stays too.
    const cached = join(work, configs[0]);
    utimesSync(cached, 100, 100);
    const keptTime = statSync(cached).mtimeMs;
    put(join(work, "out/generated"), "kept");
    put(join(work, "android/gone.java"), "obsolete");
    run();
    assert.equal(statSync(cached).mtimeMs, keptTime);
    assert.equal(readFileSync(join(work, "out/generated"), "utf8"), "kept");
    assert.equal(existsSync(join(work, "android/gone.java")), false);
  } finally {
    assert.equal(dirname(dir), tmpdir());
    rmSync(dir, { recursive: true, force: true });
  }
});
