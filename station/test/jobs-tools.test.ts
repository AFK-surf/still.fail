// The jobs' and the peer stations' MCP tools are the Rust station's, word for word: names, descriptions and input
// schemas read from jobs.rs and remote.rs and compared (key order too: serde_json there keeps it).
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { Jobs } from "../src/jobs/jobs.ts";
import { Store } from "../src/store/store.ts";
import { jobTools } from "../src/tools/jobs.ts";
import { STATION_TOOLS } from "../src/tools/remote.ts";

const jobsRs = readRust("jobs.rs");
const remoteRs = readRust("remote.rs");

function readRust(name: string): string {
  return readFileSync(new URL(`../../mesh/app/src/${name}`, import.meta.url), "utf8");
}

/// A json! macro's body as JSON: its trailing commas gone.
const jsonOf = (body: string) => JSON.parse(body.replace(/,(\s*[}\]])/g, "$1"));
const rustString = (raw: string) => JSON.parse(`"${raw}"`);

const dir = mkdtempSync(join(tmpdir(), "jobs-tools-"));
const store = Store.open(":memory:");
const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
after(async () => {
  await jobs.shutdown();
  store.close();
  rmSync(dir, { recursive: true, force: true });
});

test("job_start, job_list, job_log and job_stop are the Rust station's", () => {
  const rust = [
    ...jobsRs.matchAll(/Tool \{\s*name: "(\w+)"\.into\(\),\s*description: "((?:[^"\\]|\\.)*)"\.into\(\),\s*input_schema: json!\(([\s\S]*?)\),\s*run:/g),
  ].map((m) => ({ name: m[1], description: rustString(m[2]), inputSchema: jsonOf(m[3]) }));
  assert.equal(rust.length, 4);
  const ours = jobTools(jobs, () => null).map(({ name, description, inputSchema }) => ({ name, description, inputSchema }));
  assert.deepEqual(ours, rust);
  // Byte for byte as tools/list sends them.
  assert.equal(JSON.stringify(ours), JSON.stringify(rust));
});

test("station_list, station_task and station_file are the Rust station's", () => {
  const rust = [...remoteRs.matchAll(/\(\s*"(station_\w+)",\s*"((?:[^"\\]|\\.)*)",\s*json!\((.*?)\),\s*\)/g)].map((m) => ({
    name: m[1], description: rustString(m[2]), inputSchema: jsonOf(m[3]),
  }));
  assert.equal(rust.length, 3);
  assert.equal(JSON.stringify(STATION_TOOLS), JSON.stringify(rust));
});
