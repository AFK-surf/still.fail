// A file a session's message names, read by the MoonBit reader (station/mb src/readops/place.mbt; read/pool.ts MOVED)
// as the worker reads it (read/sessions.ts `sessionPlace`), on the same directories: absolute, under the working
// directory, `~/`, found by the end of its path in a repository there (`...` and `…` for any directories, a directory
// of one, the shortest of several) or in the station's clones (the one last fetched), through links (into the session's
// directories and out of them), in the agents' home, outside every root, in a folder macOS protects, not there, a
// session not there, and what is no path; in both languages.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const put = (path: string, text = "x") => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };
const repo = (dir: string, files: string[]) => {
  for (const f of files) put(join(dir, f), f);
  execFileSync("git", ["init", "-q", dir]);
  execFileSync("git", ["-C", dir, "add", "-A"]);
};

test("the MoonBit reader finds a file a session names as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-session-place-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ agentHome: "agents-home" }));
  const w = join(data, "w");
  const cwd = join(w, "sub");
  repo(join(w, "cue"), ["apps/x/lib/ifc/a.ex", "apps/y/lib/ifc/a.ex", "apps/x/lib/b.md", "docs/pic.PNG", "data.json", "lib/ifc/a.ex"]);
  repo(join(w, "two", "deep"), ["deep/only.txt"]);
  put(join(cwd, "here.txt"));
  put(join(w, "notes.md"), "# notes");
  mkdirSync(join(w, "node_modules", "pkg"), { recursive: true });
  repo(join(w, "node_modules", "pkg"), ["hidden.ts"]);
  // the station's clones: two with the same file, the one fetched later named longer
  repo(join(data, "repos", "a"), ["src/main.ts"]);
  repo(join(data, "repos", "new"), ["src/main.ts"]);
  put(join(data, "repos", "a", ".git", "FETCH_HEAD"), "");
  put(join(data, "repos", "new", ".git", "FETCH_HEAD"), "");
  utimesSync(join(data, "repos", "a", ".git", "FETCH_HEAD"), 1000, 1000);
  utimesSync(join(data, "repos", "new", ".git", "FETCH_HEAD"), 2000, 2000);
  put(join(data, "agents-home", "MEMORY.md"), "memory");
  const away = mkdtempSync(join(tmpdir(), "mb-reader-place-away-"));
  put(join(away, "secret.txt"));
  symlinkSync(join(away, "secret.txt"), join(w, "out-link"));
  symlinkSync(join(w, "notes.md"), join(cwd, "in-link.md"));
  symlinkSync("../notes.md", join(cwd, "rel-link.md"));
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "own", workspace: w, cwd, token: "s", createdAt: 1, lastActiveAt: 1, ws: null } as Parameters<Store["insertSession"]>[0]);
  store.insertSession({ key: "plain", connect: "ember", runtime: "claude", profile: "own", workspace: w, token: "p", createdAt: 1, lastActiveAt: 1, ws: null } as Parameters<Store["insertSession"]>[0]);
  const paths: unknown[] = [
    join(w, "notes.md"), "here.txt", "  here.txt  ", "../notes.md", "ifc/a.ex", "lib/ifc/a.ex", "apps/.../a.ex", "apps/…/b.md", "x/lib",
    "deep/only.txt", "only.txt", "hidden.ts", "src/main.ts", "main.ts", "nothing/at/all.ts", "docs/pic.PNG", "data.json", w, cwd,
    join(cwd, "in-link.md"), "rel-link.md", join(w, "out-link"), join(away, "secret.txt"), join(data, "agents-home", "MEMORY.md"),
    "~/surely-not-here-mb", "~", "", "   ", "a\0b", join(homedir(), "Documents", "none.txt"), "/Volumes/none/x", "/", "..", ".",
    join(w, "cue", "apps", "x", "lib"), 7, null, undefined,
  ];
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (r: Readers, args: unknown, lang: "zh" | "en") => r.read("sessionPlace", args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en", undefined] as const)
      for (const key of ["s", "plain"]) for (const path of paths) out.push(await read(r, { key, path, lang }, lang ?? "zh"));
    out.push(await read(r, { key: "missing", path: "here.txt", lang: "en" }, "en"));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    // again: from the listings each keeps
    assert.deepEqual(await all(program), await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["apps/x/lib/ifc/a.ex", "repos/new/src/main.ts", "\"dir\":true", "image/png", "text/markdown", "\"status\":403", "\"status\":404", "unknown session missing", "MEMORY.md"])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
    rmSync(away, { recursive: true, force: true });
  }
});
