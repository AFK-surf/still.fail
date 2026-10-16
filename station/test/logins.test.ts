// The station's logins to command-line tools (src/logins/; docs/remote-login.md): what a login command's output and
// page say, and logins run for real with stand-in login commands in a temp HOME (shell and Node scripts in a pseudo-
// terminal, as the station runs them), the browser's callback relayed to a loopback port the stand-in listens on (only
// [::1], only 127.0.0.1, a form posted), and refused when it is not the one it waits for. Time is a TestClock: what waits
// on output going quiet waits for the test to move it. Every command is ended and every server closed before a test
// ends.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { Logins, type Login, Refused } from "../src/logins/index.ts";
import type { Callback } from "../src/logins/relay.ts";
import { commandWords, deviceCodeIn, deviceUrls, loopbackOf, plainText, urlsIn } from "../src/logins/parse.ts";
import { QUIET_MS, TIMEOUT_MS } from "../src/logins/run.ts";
import { routes } from "../src/api/routes/logins.ts";
import { WINDOWS, platform } from "../src/platform/index.ts";
import { approval, script, temp, upon } from "./accounts-fakes.ts";
import { settle, testClock } from "./hub-fakes.ts";

type Json = any;

// ── what output and pages say ──

test("pages, loopback callbacks and device codes are read as the CLIs say them", () => {
  assert.equal(plainText("\u001b]11;?\u001b\\\u001b[0;1;92m? \u001b[0mAuthenticate\r\nok\rnext"), "? Authenticate\nok\nnext");
  assert.deepEqual(urlsIn("Login at:\nhttps://www.npmjs.com/login?next=/login/cli/abc.\nPress ENTER (see https://x.io/a))"), ["https://www.npmjs.com/login?next=/login/cli/abc", "https://x.io/a"]);
  // gcloud: localhost, a port, the root path; its state.
  const g = loopbackOf("https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=x&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2F&scope=openid&state=Ab1&code_challenge=c");
  assert.deepEqual(g, { host: "localhost", port: 8085, path: "/", state: "Ab1", post: false });
  // codex and aws: 127.0.0.1 with a path; Claude Code: [::1] is said as localhost; az: a form posted to the root.
  assert.deepEqual(loopbackOf("https://auth.openai.com/oauth/authorize?redirect_uri=http://127.0.0.1:1455/auth/callback&state=s"), { host: "127.0.0.1", port: 1455, path: "/auth/callback", state: "s", post: false });
  assert.deepEqual(loopbackOf("https://login.microsoftonline.com/x/oauth2/v2.0/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A41234&response_mode=form_post&state=q"), { host: "localhost", port: 41234, path: "/", state: "q", post: true });
  assert.deepEqual(loopbackOf("https://x.com/a?redirect_uri=http://[::1]:9/cb&state=z")?.host, "[::1]");
  // One level inside another page's parameter (a sign-in page handing on).
  assert.equal(loopbackOf(`https://sso.example.com/login?next=${encodeURIComponent("https://idp.example.com/authorize?redirect_uri=http://localhost:9005&state=7")}`)?.port, 9005);
  // Not a loopback: another host, no port, https.
  for (const u of ["https://x.com/a?redirect_uri=https://sdk.cloud.google.com/authcode.html", "https://x.com/a?redirect_uri=http://localhost/cb", "https://x.com/a?redirect_uri=http://example.com:80/cb", "not a url"]) assert.equal(loopbackOf(u), null, u);
  // Device codes as each tool says them; a described pattern's group first.
  assert.equal(deviceCodeIn("! First copy your one-time code: 1A2B-C3D4\nPress Enter to open https://github.com/login/device"), "1A2B-C3D4");
  assert.equal(deviceCodeIn("Your one-time device confirmation code is: WXYZ-1234"), "WXYZ-1234");
  assert.equal(deviceCodeIn("open the page https://login.microsoft.com/device and enter the code GQGFJ2QXM to authenticate."), "GQGFJ2QXM");
  assert.equal(deviceCodeIn("open the page and enter the code GQGFJ2QXM to authenticate.", "enter the code ([A-Z0-9]{8,10})"), "GQGFJ2QXM");
  assert.equal(deviceCodeIn("Then enter the code:\n\nKXQB-RMTD\n"), "KXQB-RMTD");
  assert.equal(deviceCodeIn("Press ENTER to open in the browser..."), null);
  assert.equal(deviceCodeIn("Authenticate Git with your GitHub credentials? (Y/n)"), null);
  assert.deepEqual(deviceUrls(["https://vercel.com/oauth/device?user_code=ABCD-EFGH"], "ABCD-EFGH"), { url: "https://vercel.com/oauth/device?user_code=ABCD-EFGH", codeUrl: "https://vercel.com/oauth/device?user_code=ABCD-EFGH" });
  assert.deepEqual(deviceUrls(["https://docs.github.com/x", "https://github.com/login/device"], "AB12-CD34"), { url: "https://github.com/login/device", codeUrl: null });
  assert.deepEqual(commandWords(`vercel login --scope "my team" 'a b' c\\ d`), ["vercel", "login", "--scope", "my team", "a b", "c d"]);
  assert.equal(commandWords(`gh "open`), null);
  assert.deepEqual(commandWords("  "), []);
});

// ── logins run for real ──

/// A machine for logins: a temp HOME, a bin/ for the stand-ins, Node on PATH (for the stand-ins written in it), the
/// system's tools; a Logins on a TestClock.
function machine() {
  const home = temp("logins");
  const bin = join(home, "bin");
  mkdirSync(bin, { recursive: true });
  const env = { HOME: home, PATH: `${bin}:${dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`, LANG: "en_US.UTF-8" };
  const time = testClock();
  const logins = new Logins({ data: join(home, "data"), env: () => env, clock: time.clock, lang: () => "zh" });
  const changed = (wake: () => void) => logins.changes(wake);
  /// Waits until the login is so (each change looked at).
  const until = (id: string, ok: (l: Login) => boolean, what: string) => upon(changed, () => { const l = logins.get(id); return l && ok(l) ? l : undefined; }, what);
  /// Waits until its screen shows `text` on the cursor's line; then its output has gone quiet (the clock moved on).
  const quietAt = async (id: string, text: string) => {
    await upon((wake) => logins.follow(id, wake), () => {
      let shown = "";
      const stop = logins.follow(id, (s) => (shown = s.rows[s.cursor.y] ?? ""));
      stop();
      return shown.includes(text);
    }, text);
    await settle(5);
    await time.adjust(QUIET_MS);
  };
  const screen = (id: string) => {
    let rows: string[] = [];
    logins.follow(id, (s) => (rows = s.rows))();
    return rows.join("\n");
  };
  const by = { by: { email: "a@x.com", name: "张三" }, workspace: "w1" };
  return { home, bin, env, time, logins, until, quietAt, screen, by };
}

/// A service described for a stand-in: logged in once `<home>/.fake-logged` says who.
function describeFake(m: ReturnType<typeof machine>, id: string, login: string[], more: Json = {}) {
  script(join(m.bin, `${id}-status`), `#!/bin/sh\n[ -f "$HOME/.fake-logged" ] || { echo "not logged in"; exit 1; }\necho "Logged in to example.com account $(cat "$HOME/.fake-logged")"\n`);
  return m.logins.describe({ id, name: `Fake ${id}`, bin: login[0]!.split("/").at(-1), status: { command: [`${id}-status`], in: { exit: 0 }, account: "account (\\S+)" }, login: { command: login, flow: "device", ...more } });
}

const skipped = WINDOWS && "logins run in a pseudo-terminal: script is Unix's";

test("a device-code login: Enter pressed where the description says so, the page it opens and its code told, done with the account", { skip: skipped }, async () => {
  const m = machine();
  const approved = approval(m.home);
  script(join(m.bin, "fakegh"), `#!/bin/sh
printf '? Authenticate Git with your GitHub credentials? (Y/n) '
read answer
echo "answered [$answer]"
echo "! First copy your one-time code: 1A2B-C3D4"
printf "Press Enter to open https://github.com/login/device in your browser... "
read go
"$BROWSER" https://github.com/login/device
echo "Waiting for the browser"
read ok < '${approved.path}'
echo octocat > "$HOME/.fake-logged"
echo "Logged in as octocat"
`);
  describeFake(m, "fakegh", ["fakegh", "auth", "login"], { enter: true, code: "\\b([A-Z0-9]{4}-[A-Z0-9]{4})\\b", answers: [{ match: "Authenticate Git", text: "" }] });
  try {
    await m.logins.refresh();
    assert.equal(m.logins.service("fakegh")!.state, "out");
    const started = await m.logins.start({ service: "fakegh" }, m.by);
    assert.deepEqual([started.service, started.name, started.by], ["fakegh", "Fake fakegh", m.by.by]);
    // One under way for the service is given rather than another.
    assert.equal((await m.logins.start({ service: "fakegh" }, m.by)).id, started.id);
    assert.equal(m.logins.service("fakegh")!.login, started.id);
    await m.quietAt(started.id, "Authenticate Git");
    const device = await m.until(started.id, (l) => l.step === "device" && l.url !== undefined, "device");
    assert.equal(device.code, "1A2B-C3D4");
    assert.ok(m.screen(started.id).includes("answered []"), "the prompt answered with the tool's default");
    await m.quietAt(started.id, "Press Enter to open");
    // Enter pressed: the page goes to the station's BROWSER, not a browser on this machine.
    await upon((w) => m.logins.follow(started.id, w), () => m.screen(started.id).includes("Waiting for the browser"), "opened");
    const opened = m.logins.get(started.id)!;
    assert.deepEqual([opened.state, opened.step, opened.url, opened.domain, opened.code], ["code", "device", "https://github.com/login/device", "github.com", "1A2B-C3D4"]);
    await approved.approve();
    const done = await m.until(started.id, (l) => l.state === "done", "done");
    assert.equal(done.account, "octocat");
    const service = m.logins.service("fakegh")!;
    assert.deepEqual([service.state, service.account, service.by, service.login], ["in", "octocat", m.by.by, undefined]);
    const kept = JSON.parse(readFileSync(join(m.home, "data", "logins", "state.json"), "utf8"));
    assert.equal(kept.fakegh.account, "octocat");
    // A read-only member sees how it stands, not its page or code.
    const limited = Logins.limited(opened);
    assert.deepEqual([limited.url, limited.code, limited.domain, limited.state], [undefined, undefined, "github.com", "code"]);
  } finally {
    await m.logins.close();
  }
});

test("a login waiting on prompts: its terminal answers the program's queries, takes typing, and says when the input is a password", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "fakeprompt"), `#!/usr/bin/env node
const { execFileSync } = require("node:child_process");
const out = (s) => process.stdout.write(s);
// What gh does first: ask the terminal where its cursor is, and wait for the answer.
process.stdin.setRawMode(true);
out("\\u001b]11;?\\u001b\\\\\\u001b[6n");
let buf = "";
const lines = [];
let want = null;
process.stdin.on("data", (d) => {
  buf += d.toString();
  if (want === null) {
    if (!buf.includes("R")) return;
    out("cursor " + JSON.stringify(buf.slice(buf.indexOf("\\u001b["), buf.indexOf("R") + 1)) + "\\r\\n");
    buf = "";
    process.stdin.setRawMode(false);
    want = "user";
    out("Username: ");
    return;
  }
  if (!buf.includes("\\n")) return;
  const line = buf.slice(0, buf.indexOf("\\n")).trim();
  buf = "";
  if (want === "user") {
    lines.push(line);
    want = "password";
    execFileSync("stty", ["-echo"], { stdio: ["inherit", "ignore", "ignore"] });
    out("Password: ");
  } else {
    execFileSync("stty", ["echo"], { stdio: ["inherit", "ignore", "ignore"] });
    out("\\r\\nwelcome " + lines[0] + "\\r\\n");
    process.exit(lines[0] === "alice" && line === "s3cret" ? 0 : 1);
  }
});
`);
  try {
    const login = await m.logins.start({ command: "fakeprompt --user" }, m.by);
    assert.deepEqual(login.command, ["fakeprompt", "--user"]);
    await m.quietAt(login.id, "Username:");
    const waiting = await m.until(login.id, (l) => l.waiting, "waiting");
    assert.deepEqual([waiting.state, waiting.step], ["input", "terminal"]);
    assert.match(m.screen(login.id), /cursor "\\u001b\[\d+;\d+R"/, "the cursor's place was answered");
    let echo: boolean | null = null;
    const stop = m.logins.follow(login.id, (s) => (echo = s.echo));
    assert.equal(echo, true);
    m.logins.input(login.id, { text: "alice" });
    m.logins.input(login.id, { key: "Enter" });
    await m.quietAt(login.id, "Password:");
    await upon((w) => m.logins.follow(login.id, w), () => echo === false, "no echo");
    m.logins.input(login.id, { text: "s3cret\r" });
    const done = await m.until(login.id, (l) => l.state === "done", "done");
    assert.equal(done.service, undefined);
    assert.ok(m.screen(login.id).includes("welcome alice"));
    assert.ok(!m.screen(login.id).includes("s3cret"), "the password was not echoed");
    stop();
    assert.throws(() => m.logins.input(login.id, { text: "x" }), (e: unknown) => e instanceof Refused && e.status === 409);
  } finally {
    await m.logins.close();
  }
});

/// A stand-in that logs in by a loopback callback, as gcloud, aws, Claude Code and az do: it listens on `host` (only
/// there), names the port in the page it opens (BROWSER), and takes one callback: the right state ends it 0, a wrong one
/// ends it 1 (as most real ones do). `mode` post: the callback is a form posted to its root (az).
const LOOPBACK = `#!/usr/bin/env node
const http = require("node:http");
const { execFileSync } = require("node:child_process");
const [host, mode] = process.argv.slice(2);
const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    const url = new URL(req.url, "http://x");
    const state = mode === "post" ? new URLSearchParams(body).get("state") : url.searchParams.get("state");
    process.stdout.write("got " + req.method + " " + req.url + " " + body + " host=" + req.headers.host + "\\r\\n");
    if (state !== "s3cret") { res.writeHead(400); res.end("bad state"); server.close(); return process.exit(1); }
    res.writeHead(200, { "content-type": "text/html", "x-fake": "1" });
    res.end("<h1>signed in</h1>", () => server.close(() => process.exit(0)));
  });
});
server.listen(0, host, () => {
  const port = server.address().port;
  const back = "http://localhost:" + port + (mode === "post" ? "" : "/callback");
  const page = "https://accounts.example.com/o/oauth2/auth?client_id=x&redirect_uri=" + encodeURIComponent(back) + "&state=s3cret" + (mode === "post" ? "&response_mode=form_post" : "");
  execFileSync(process.env.BROWSER, [page]);
  process.stdout.write("Your browser has been opened to visit:\\r\\n\\r\\n    " + page.replace("s3cret", "printed") + "\\r\\n");
});
`;

for (const [host, mode] of [["::1", "get"], ["127.0.0.1", "get"], ["127.0.0.1", "post"]] as const) {
  test(`a loopback login listening on ${host} only: its callback (${mode === "post" ? "a form posted" : "GET"}) relayed once, the right one only`, { skip: skipped }, async () => {
    const m = machine();
    script(join(m.bin, "fakeloop"), LOOPBACK);
    try {
      const login = await m.logins.start({ command: ["fakeloop", host, mode] }, m.by);
      const waiting = await m.until(login.id, (l) => l.step === "loopback", "loopback");
      // The page it opened, not the one it printed.
      assert.ok(waiting.url!.includes("state=s3cret"), waiting.url);
      const back = waiting.callback!;
      assert.deepEqual([back.host, back.path, back.state, back.post, waiting.domain, waiting.state], ["localhost", mode === "post" ? "/" : "/callback", "s3cret", mode === "post", "accounts.example.com", "browser"]);
      const form = (state: string) => Buffer.from(`code=c0de&state=${state}`).toString("base64");
      const request = (state: string): Callback =>
        mode === "post"
          ? { method: "POST", path: "/", headers: { host: `localhost:${back.port}`, "content-type": "application/x-www-form-urlencoded" }, body: form(state) }
          : { method: "GET", path: `/callback?code=c0de&state=${state}`, headers: { host: `localhost:${back.port}` } };
      // Not the one it waits for: refused here, never sent (one wrong request ends the command).
      for (const wrong of [request("guess"), { ...request("s3cret"), path: mode === "post" ? "/other" : "/other?state=s3cret" }, { ...request("s3cret"), method: mode === "post" ? "GET" : "POST" }]) {
        await assert.rejects(m.logins.callback(login.id, wrong), (e: unknown) => e instanceof Refused && e.status === 400, JSON.stringify(wrong));
      }
      assert.ok(!m.screen(login.id).includes("got "), "nothing reached the command");
      const answered = await m.logins.callback(login.id, request("s3cret"));
      assert.equal(answered.status, 200);
      assert.equal(Buffer.from(answered.body, "base64").toString(), "<h1>signed in</h1>");
      assert.equal(answered.headers["x-fake"], "1");
      // Once only.
      await assert.rejects(m.logins.callback(login.id, request("s3cret")), (e: unknown) => e instanceof Refused && e.status === 409);
      const done = await m.until(login.id, (l) => l.state === "done", "done");
      assert.equal(done.service, undefined);
      assert.match(m.screen(login.id), mode === "post" ? /got POST \/ code=c0de&state=s3cret host=localhost:\d+/ : /got GET \/callback\?code=c0de&state=s3cret  host=localhost:\d+/);
    } finally {
      await m.logins.close();
    }
  });
}

test("a callback is refused when the port is not the command's, or the command has ended", { skip: skipped }, async () => {
  const m = machine();
  // Another program on the port the page names (the stand-in itself listens nowhere).
  let reached = 0;
  const other = createServer((_req, res) => (reached++, res.end("not the login")));
  await new Promise<void>((resolve) => other.listen(0, "127.0.0.1", resolve));
  const port = (other.address() as AddressInfo).port;
  script(join(m.bin, "fakeport"), `#!/bin/sh\n"$BROWSER" "https://idp.example.com/auth?redirect_uri=http%3A%2F%2F127.0.0.1%3A${port}%2Fcb&state=s1"\necho waiting\nread forever\n`);
  script(join(m.bin, "fakegone"), `#!/bin/sh\n"$BROWSER" "https://idp.example.com/auth?redirect_uri=http%3A%2F%2F127.0.0.1%3A${port}%2Fcb&state=s1"\necho bye\nexit 3\n`);
  try {
    const taken = await m.logins.start({ command: ["fakeport"] }, m.by);
    await m.until(taken.id, (l) => l.step === "loopback", "loopback");
    await assert.rejects(
      m.logins.callback(taken.id, { method: "GET", path: "/cb?state=s1&code=x", headers: { host: `127.0.0.1:${port}` } }),
      (e: unknown) => e instanceof Refused && e.status === 409 && e.message.includes(`does not listen on port ${port}`),
    );
    assert.equal(reached, 0, "the code never went to the other program");
    const cancelled = m.logins.cancel(taken.id);
    assert.equal(cancelled.state, "cancelled");
    const gone = await m.logins.start({ command: ["fakegone"] }, m.by);
    const failed = await m.until(gone.id, (l) => l.state === "failed", "failed");
    assert.ok(failed.error!.includes("bye"), failed.error);
    await assert.rejects(m.logins.callback(gone.id, { method: "GET", path: "/cb?state=s1", headers: {} }), (e: unknown) => e instanceof Refused && e.status === 409);
    assert.equal(reached, 0);
    await assert.rejects(m.logins.callback("nope", { method: "GET", path: "/", headers: {} }), (e: unknown) => e instanceof Refused && e.status === 404);
  } finally {
    await m.logins.close();
    await new Promise<void>((resolve) => other.close(() => resolve()));
  }
});

test("a login not finished in time ends, its command with it; one that cannot run says why", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "fakeslow"), `#!/bin/sh\necho "Visit https://example.com/activate"\nread forever\n`);
  try {
    const slow = await m.logins.start({ command: ["fakeslow"] }, m.by);
    await m.until(slow.id, (l) => l.step === "open", "open");
    await m.time.adjust(TIMEOUT_MS);
    const ended = await m.until(slow.id, (l) => l.state === "failed", "timed out");
    assert.equal(ended.error, "15 分钟内没有完成登录，已结束");
    assert.equal((await m.logins.list()).logins[0]!.id, slow.id);
    const none = await m.logins.start({ command: ["no-such-login-command"] }, m.by);
    const failed = await m.until(none.id, (l) => l.state === "failed", "cannot run");
    assert.ok(failed.error !== undefined && failed.error !== "", JSON.stringify(failed));
    await assert.rejects(m.logins.start({ service: "nope" }, m.by), (e: unknown) => e instanceof Refused && e.status === 404);
    await assert.rejects(m.logins.start({ command: "gh 'open" }, m.by), (e: unknown) => e instanceof Refused && e.status === 400);
  } finally {
    await m.logins.close();
  }
});

test("the services: built in, an agent's description winning over one of the same id, not installed said so", { skip: skipped }, async () => {
  const m = machine();
  try {
    const services = m.logins.services();
    for (const id of ["gh", "gcloud", "npm", "docker", "aws", "az", "vercel", "wrangler", "firebase", "fly", "huggingface"]) assert.ok(services.some((s) => s.id === id && s.builtin), id);
    // None of them is on this PATH.
    assert.deepEqual([m.logins.service("gh")!.installed, m.logins.service("gh")!.state], [false, "out"]);
    await assert.rejects(m.logins.start({ service: "gh" }, m.by), (e: unknown) => e instanceof Refused && e.status === 409);
    script(join(m.bin, "gh"), `#!/bin/sh\necho "  ✓ Logged in to github.com account mona (keyring)"\n`);
    await m.logins.refresh();
    assert.deepEqual([m.logins.service("gh")!.installed, m.logins.service("gh")!.state, m.logins.service("gh")!.account], [true, "in", "mona"]);
    const own = describeFake(m, "gh", ["gh", "auth", "login", "--hostname", "ghe.example.com"]);
    assert.deepEqual([own.name, own.builtin], ["Fake gh", true]);
    assert.deepEqual(m.logins.description("gh")!.login.command.at(-1), "ghe.example.com");
    assert.throws(() => m.logins.describe({ id: "Bad Id", name: "x", bin: "x", status: { command: ["x"] }, login: { command: ["x"] } }), /id:/);
    assert.throws(() => m.logins.describe({ id: "x", name: "x", bin: "x", status: { command: ["x"] }, login: { command: ["x"], code: "(" } }), /login.code/);
  } finally {
    await m.logins.close();
  }
});

test("the routes: a read-only member's list has no pages or codes; what a request lacks is refused", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "fakecode"), `#!/bin/sh\necho "Open https://example.com/device and enter WXYZ-1234"\nread forever\n`);
  const [list, start, , cancel] = routes(() => m.logins);
  const ask = (route: (typeof list), role: string, body: Json = {}, args: string[] = []) =>
    route.handle({ method: route.method, path: "/machine-logins", query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), viewer: { sub: "s", email: "a@x.com", name: "张三", role, workspace: "w1", device: "d" }, lang: "zh" }, args);
  const read = async (answer: Promise<{ status: number; body: unknown }>) => {
    const a = await answer;
    return { status: a.status, body: JSON.parse((a.body as Buffer).toString()) };
  };
  try {
    const started = await read(ask(start, "member", { command: "fakecode" }));
    assert.equal(started.status, 200);
    await m.until(started.body.id, (l) => l.step === "device", "device");
    const member = await read(ask(list, "member"));
    const viewer = await read(ask(list, "viewer"));
    const mine = member.body.logins.find((l: Json) => l.id === started.body.id);
    const theirs = viewer.body.logins.find((l: Json) => l.id === started.body.id);
    assert.deepEqual([mine.code, mine.url], ["WXYZ-1234", "https://example.com/device"]);
    assert.deepEqual([theirs.code, theirs.url, theirs.step, theirs.domain], [undefined, undefined, "device", "example.com"]);
    assert.equal((await read(ask(start, "member", {}))).status, 400);
    assert.equal((await read(ask(cancel, "member", {}, [started.body.id]))).body.state, "cancelled");
  } finally {
    await m.logins.close();
  }
});

test("a machine's lsof says where a process listens", { skip: WINDOWS && "lsof is Unix's" }, async () => {
  const server = createServer(() => {});
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  try {
    assert.deepEqual(await platform.listening([process.pid], port), ["127.0.0.1"]);
    assert.deepEqual(await platform.listening([process.pid], port + 1 > 65535 ? 1 : port + 1), []);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
