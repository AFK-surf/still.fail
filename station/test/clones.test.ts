// Repositories cloned from git into the repository cache (src/sessions/clones.ts, POST /presets/clone): answered at
// once, git run by a fake here, the clone put in place whole once done, a failure said and cleaned up.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type GitRun, Clones, NoCloneUrl, cloneUrl, safeUrl } from "../src/sessions/clones.ts";
import { candidates, originOf } from "../src/sessions/presets.ts";
import { routes } from "../src/api/routes/presets.ts";
import { Presets } from "../src/sessions/presets.ts";
import { settle } from "./hub-fakes.ts";

/// A fake git: each run held until the test ends it, as git would (the clone's directory made where it succeeds).
function fakeGit() {
  const runs: { args: string[]; env: NodeJS.ProcessEnv; end: (ok: boolean, stderr?: string) => void; killed: boolean }[] = [];
  const run: GitRun = (args, env) => {
    let end!: (ok: boolean, stderr?: string) => void;
    const done = new Promise<{ ok: boolean; stderr: string }>((resolve) => {
      end = (ok, stderr = "") => {
        const [url, to] = args.slice(-2) as [string, string];
        mkdirSync(join(to, ".git"), { recursive: true });
        if (ok) writeFileSync(join(to, ".git", "config"), `[remote "origin"]\n\turl = ${url}\n`);
        resolve({ ok, stderr });
      };
    });
    const held = { args, env, end, killed: false };
    runs.push(held);
    return { done, kill: () => ((held.killed = true), end(false, "killed")) };
  };
  return { runs, run };
}

function rig() {
  const repos = join(realpathSync(mkdtempSync(join(tmpdir(), "clones-"))), "repos");
  const git = fakeGit();
  let told = 0;
  const clones = new Clones({ reposDir: () => repos, now: () => 1000, run: git.run });
  return { repos, git, clones, changed: () => void told++, told: () => told };
}

test("a clone answers at once, runs git so that it asks nobody, and comes into the cache whole once done", async () => {
  const { repos, git, clones, changed, told } = rig();
  // (one a station that stopped mid-clone left)
  mkdirSync(join(repos, ".cloning-old", ".git"), { recursive: true });
  const started = await clones.start("ws", "acme/app", "a@x.com", changed);
  assert.deepEqual(started, { id: (started as { id: string }).id, url: "https://github.com/acme/app.git", repo: "github.com/acme/app", name: "app", state: "cloning", by: "a@x.com", startedAt: 1000 });
  assert.equal(told(), 1);
  await settle();
  assert.equal(git.runs.length, 1);
  const [run] = git.runs;
  assert.deepEqual(run!.args.slice(0, 8), ["-c", "protocol.ext.allow=never", "-c", "protocol.file.allow=never", "clone", "--quiet", "--", "https://github.com/acme/app.git"]);
  assert.match(run!.args[8]!, /\/\.cloning-c-[0-9a-f]+$/);
  assert.equal(run!.env.GIT_TERMINAL_PROMPT, "0");
  assert.equal(run!.env.GIT_SSH_COMMAND, "ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new");
  assert.ok(!existsSync(join(repos, ".cloning-old")), "what a stopped station left is removed");
  assert.deepEqual(clones.list("ws").map((c) => c.state), ["cloning"]);
  assert.deepEqual(clones.list("other"), [], "each workspace its own");
  // Half made: no candidate yet.
  run!.args.slice(-1).forEach((to) => mkdirSync(join(to, ".git"), { recursive: true }));
  assert.deepEqual(await candidates(repos, []), []);

  run!.end(true);
  await settle();
  assert.deepEqual(readdirSync(repos), ["app"]);
  assert.equal(originOf(join(repos, "app")), "github.com/acme/app");
  assert.deepEqual(clones.list("ws"), []);
  assert.equal(told(), 2);
  assert.deepEqual((await candidates(repos, [])).map((c) => [c.name, c.repo]), [["app", "github.com/acme/app"]]);
  // Asked again: there already, nothing started.
  assert.deepEqual(await clones.start("ws", "https://github.com/acme/app", "a@x.com", changed), { state: "there", path: join(repos, "app"), repo: "github.com/acme/app", name: "app" });
  assert.equal(git.runs.length, 1);
});

test("a failed clone says git's last words without a credential, and leaves nothing behind", async () => {
  const { repos, git, clones, changed, told } = rig();
  const started = await clones.start("ws", "https://bob:s3cret@git.example.com/team/lib.git", "a@x.com", changed);
  assert.equal((started as { url: string }).url, "https://git.example.com/team/lib.git", "kept without its name and password");
  assert.equal((started as { repo: string }).repo, "git.example.com/team/lib");
  await settle();
  assert.equal(git.runs[0]!.args[7], "https://bob:s3cret@git.example.com/team/lib.git", "git is given them");
  git.runs[0]!.end(false, "remote: Repository not found.\nfatal: repository 'https://bob:s3cret@git.example.com/team/lib.git/' not found\n\n");
  await settle();
  const [failed] = clones.list("ws");
  assert.equal(failed!.state, "failed");
  assert.equal(failed!.error, "remote: Repository not found.\nfatal: repository 'https://git.example.com/team/lib.git/' not found");
  assert.ok(!JSON.stringify(clones.list("ws")).includes("s3cret"));
  assert.deepEqual(readdirSync(repos), [], "its temporary directory removed");
  assert.equal(told(), 2);
  // Started again: in its place; dropped: gone.
  await clones.start("ws", "https://git.example.com/team/lib.git", "a@x.com", changed);
  await settle();
  assert.deepEqual(clones.list("ws").map((c) => c.state), ["cloning"]);
  git.runs[1]!.end(false, "x".repeat(1000));
  await settle();
  assert.equal(clones.list("ws")[0]!.error!.length, 300);
  assert.equal(clones.drop("ws", clones.list("ws")[0]!.id), true);
  assert.deepEqual(clones.list("ws"), []);
  assert.equal(clones.drop("ws", "c-none"), false);
});

test("the same repository twice is one clone; one under way dropped is stopped", async () => {
  const { repos, git, clones, changed } = rig();
  const a = await clones.start("ws", "git@github.com:acme/app.git", "a@x.com", changed);
  const b = await clones.start("ws", "https://github.com/acme/app", "b@x.com", changed);
  assert.equal((b as { id: string }).id, (a as { id: string }).id);
  await settle();
  assert.equal(git.runs.length, 1);
  assert.equal(clones.drop("ws", (a as { id: string }).id), true);
  assert.equal(git.runs[0]!.killed, true);
  await settle();
  assert.deepEqual(clones.list("ws"), []);
  assert.deepEqual(readdirSync(repos), [], "its temporary directory removed");
});

test("a clone whose name is taken goes in as its owner's", async () => {
  const { repos, git, clones, changed } = rig();
  mkdirSync(join(repos, "app"), { recursive: true });
  await clones.start(null, "acme/app", "a@x.com", changed);
  await settle();
  git.runs[0]!.end(true);
  await settle();
  assert.deepEqual(readdirSync(repos).sort(), ["acme-app", "app"]);
  assert.equal(originOf(join(repos, "acme-app")), "github.com/acme/app");
  mkdirSync(join(repos, "other-app"));
  await clones.start(null, "https://gitlab.com/other/app.git", "a@x.com", changed);
  await settle();
  git.runs[1]!.end(true);
  await settle();
  assert.deepEqual(readdirSync(repos).sort(), ["acme-app", "app", "other-app", "other-app-2"]);
});

test("only git addresses are cloned", () => {
  for (const bad of ["", "  ", "-x", "--upload-pack=touch /tmp/x", "file:///etc", "/abs/path", "./x", "../x/y", "~/code/app", "ext::sh -c touch% /tmp/pwned", "ext::sh", "fd::3", "https://github.com/a b/c", "https://github.com/a/b\nc", "a/b/c", "C:/repos/app", "./app"]) {
    assert.throws(() => cloneUrl(bad), NoCloneUrl, bad);
  }
  assert.equal(cloneUrl(" acme/app "), "https://github.com/acme/app.git");
  assert.equal(cloneUrl("acme/app.git"), "https://github.com/acme/app.git");
  for (const good of ["https://github.com/acme/app.git", "http://git.local/x/y", "ssh://git@host.com:2222/acme/app.git", "git://host/acme/app", "git@github.com:acme/app.git"]) assert.equal(cloneUrl(good), good);
  assert.equal(safeUrl("https://x-access-token:ghp_abc@github.com/a/b.git"), "https://github.com/a/b.git");
  assert.equal(safeUrl("https://ghp_abc@github.com/a/b.git"), "https://github.com/a/b.git");
  assert.equal(safeUrl("ssh://git:pw@host/a/b"), "ssh://git@host/a/b");
  assert.equal(safeUrl("git@github.com:a/b.git"), "git@github.com:a/b.git");
});

test("POST /presets/clone answers at once, refuses in the asker's words and a read-only member, and GET /presets lists it", async () => {
  const { repos, git, clones } = rig();
  let told = 0;
  const home = mkdtempSync(join(tmpdir(), "clones-home-"));
  const table = routes({ presets: new Presets(() => home, () => 1), reposDir: () => repos, clones, changed: () => void told++ });
  const ask = async (method: string, path: string, body: unknown, over: Record<string, unknown> = {}) => {
    const route = table.find((r) => r.method === method && r.pattern.test(path))!;
    const match = route.pattern.exec(path)!;
    const r = { method, path, query: [], headers: {}, body: Buffer.from(body === null ? "" : JSON.stringify(body)), lang: "zh", viewer: { workspace: "ws", email: "a@x.com", role: "member" }, ...over } as never;
    const answer = await route.handle(r, match.slice(1));
    return { status: answer.status, json: JSON.parse(answer.body.toString()) };
  };
  const bad = await ask("POST", "/presets/clone", { url: "file:///etc" });
  assert.deepEqual(bad, { status: 400, json: { error: "不是能克隆的 Git 地址" } });
  assert.equal((await ask("POST", "/presets/clone", { url: "-x" }, { lang: "en" })).json.error, "Not a Git address that can be cloned");
  const viewer = await ask("POST", "/presets/clone", { url: "acme/app" }, { viewer: { workspace: "ws", email: "v@x.com", role: "viewer" } });
  assert.equal(viewer.status, 403);
  const made = await ask("POST", "/presets/clone", { url: "acme/app" });
  assert.equal(made.status, 200);
  assert.equal(made.json.state, "cloning");
  assert.equal(told, 1);
  const listed = await ask("GET", "/presets", null);
  assert.deepEqual(listed.json.clones.map((c: { id: string }) => c.id), [made.json.id]);
  await settle();
  git.runs[0]!.end(false, "fatal: could not read Username for 'https://github.com': terminal prompts disabled");
  await settle();
  assert.equal(told, 2);
  assert.equal((await ask("DELETE", `/presets/clones/${made.json.id}`, null)).json.ok, true);
  assert.equal(told, 3);
  assert.equal((await ask("DELETE", `/presets/clones/${made.json.id}`, null)).status, 404);
});
