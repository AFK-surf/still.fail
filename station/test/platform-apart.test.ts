// The station's platform makes nothing of the agents' side (docs/station-modules.md, 进程内的部分): the mesh, the drive,
// the modules beside it, the services and the admin API take what they need of it through the platform's services
// (AgentsSide, MeshSide, Parts), never by importing it. Only main.ts, the composition root, and the parts name it.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const src = fileURLToPath(new URL("../src/", import.meta.url));
const files = (dir: string): string[] => readdirSync(join(src, dir), { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(join(dir, e.name)) : e.name.endsWith(".ts") ? [join(dir, e.name)] : []));

test("the platform imports nothing of the agents' side but its types", () => {
  const platform = [...files("mesh"), ...files("drive"), ...files("modules"), "services.ts", "api/admin.ts"];
  const wrong = platform.filter((f) => /^import (?!type )[^;]*from "[./]*\/?sessions\/agents\.ts"/m.test(readFileSync(join(src, f), "utf8")));
  assert.deepEqual(wrong, []);
});

/// The parts: a directory with a module.ts (its layer); the drive's is its transfers, the drive itself the platform's.
const parts = readdirSync(src, { withFileTypes: true }).filter((e) => e.isDirectory() && e.name !== "drive" && readdirSync(join(src, e.name)).includes("module.ts")).map((e) => e.name);
/// Those of `files` that import a part but for its types.
const importingParts = (files: string[]) => {
  const named = new RegExp(`^import (?!type )[^;]*from "[./]*/?(${parts.join("|")})/`, "m");
  return files.filter((f) => named.test(readFileSync(join(src, f), "utf8")));
};

test("the platform imports none of the parts but their types", () => {
  assert.deepEqual(importingParts([...files("mesh"), ...files("modules"), "services.ts", "api/admin.ts"]), []);
});

test("the agents' side and what the parts share import none of the parts but their types", () => {
  // The readers (read/) are a worker's, its reads a table of its own: a part's are there, with what of the part they read.
  const shared = ["sessions", "agents", "jobs", "accounts", "updates", "tools", "cloud", "store", "ops", "screens", "helper", "platform", "share", "xshare", "device", "connects"];
  assert.deepEqual(importingParts(shared.flatMap(files)), []);
});
