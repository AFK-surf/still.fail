// The station's logins to command-line tools (src/logins/; docs/remote-login.md): what a login command's output and
// page say, and logins run for real with stand-in login commands in a temp HOME (shell and Node scripts in a pseudo-
// terminal, as the station runs them), the browser's callback relayed to a loopback port the stand-in listens on (only
// [::1], only 127.0.0.1, a form posted), and refused when it is not the one it waits for. Time is a TestClock: what waits
// on output going quiet waits for the test to move it. Every command is ended and every server closed before a test
// ends.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { Logins, type Login, Refused } from "../src/logins/index.ts";
import type { Callback } from "../src/logins/relay.ts";
import { asksEnter, commandWords, deviceCodeIn, deviceUrls, loopbackOf, plainText, programOf, prompts, saysDone, storesSecret, unwrapped, urlsIn } from "../src/logins/parse.ts";
import { COLS, QUIET_MS, STALL_MS, TIMEOUT_MS } from "../src/logins/run.ts";
import { routes } from "../src/api/routes/logins.ts";
import { act, endedNotice, loginTools, promptNotice, screenFor } from "../src/tools/login.ts";
import { WINDOWS, platform } from "../src/platform/index.ts";
import { approval, fakeBrowser, script, temp, upon } from "./accounts-fakes.ts";
import type { LoginPages } from "../src/logins/pages.ts";
import { settle, testClock } from "./hub-fakes.ts";

type Json = any;

// ── what output and pages say ──

test("pages, loopback callbacks and device codes are read as the CLIs say them", () => {
  assert.equal(plainText("\u001b]11;?\u001b\\\u001b[0;1;92m? \u001b[0mAuthenticate\r\nok\rnext"), "? Authenticate\nok\nnext");
  assert.equal(plainText("a\r\r\nb\r\r\rc"), "a\nb\nc");
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
  assert.equal(deviceCodeIn("Visit https://vercel.com/oauth/device?user_code=ABCD-EFGH"), "ABCD-EFGH");
  assert.equal(deviceCodeIn("To finish, open https://login.example.org/activate and enter code: WDJB-MJHT"), "WDJB-MJHT");
  assert.equal(deviceCodeIn("Then enter the code:\n\nKXQB-RMTD\n"), "KXQB-RMTD");
  assert.equal(deviceCodeIn("Press ENTER to open in the browser..."), null);
  assert.equal(deviceCodeIn("Authenticate Git with your GitHub credentials? (Y/n)"), null);
  assert.deepEqual(deviceUrls(["https://vercel.com/oauth/device?user_code=ABCD-EFGH"], "ABCD-EFGH"), { url: "https://vercel.com/oauth/device?user_code=ABCD-EFGH", codeUrl: "https://vercel.com/oauth/device?user_code=ABCD-EFGH" });
  assert.deepEqual(deviceUrls(["https://docs.github.com/x", "https://github.com/login/device"], "AB12-CD34"), { url: "https://github.com/login/device", codeUrl: null });
  // Only Enter to open a page is pressed for the person; a question is theirs.
  assert.ok(asksEnter("Press Enter to open https://github.com/login/device in your browser... "));
  assert.ok(asksEnter("Press ENTER to open in the browser..."));
  assert.ok(asksEnter("Press ENTER to open your browser or submit your device code here: https://login.docker.com/activate"));
  assert.ok(!asksEnter("? Authenticate Git with your GitHub credentials? (Y/n) "));
  assert.ok(!asksEnter("Press Enter to continue"));
  // What says the person's step is over, and what keeps a secret where the OS may ask.
  for (const done of ["✓ Authentication complete.", "Logged in as octocat", "You are now logged in as a@x.com.", "Successfully authenticated", "Authenticated as octocat"]) assert.ok(saysDone(done), done);
  for (const not of ["Opening github.com/login/device in your browser.", "Waiting for the browser", "! First copy your one-time code: 1A2B-C3D4", "✓ Opened"]) assert.ok(!saysDone(not), not);
  for (const name of ["git-credential-osxkeychain", "/opt/homebrew/libexec/git-core/git-credential-osxkeychain", "pinentry-mac", "ssh-askpass", "secret-tool"]) assert.ok(storesSecret(name), name);
  for (const name of ["gh", "git", "python3", "sh", "script"]) assert.ok(!storesSecret(name), name);
  assert.ok(prompts("? Authenticate Git with your GitHub credentials? (Y/n) "));
  assert.deepEqual(commandWords(`vercel login --scope "my team" 'a b' c\\ d`), ["vercel", "login", "--scope", "my team", "a b", "c d"]);
  assert.equal(commandWords(`gh "open`), null);
  assert.deepEqual(commandWords("  "), []);
});

/// Devin's sign-in page (Devin CLI 3000.11.92, `devin auth login --force-manual-token-flow`): longer than the terminal is
/// wide, its PKCE challenge with a run of capitals and digits in it that reads like a code.
const DEVIN_PAGE = "https://app.devin.ai/auth/cli/continue?state=Zr8wq1VbN0cT5yHk2LmP9sXa4Jd7Ue0RtWo6Gi3Ny5Bf1Mh8Kl2Sp9Qc&prompt=select_account&code_challenge=xQ2-K9ZTRW4P_vb7Hq0nLm3cYt8sWe1aD5fGj6kU4rI&code_challenge_method=S256&cli_pkce_marker=1";

test("a login's program by its name, past env, its variables and what only runs it; a link broken at the terminal's width put together; no device code read from a page's parameters", () => {
  assert.equal(programOf(["env", "HOME=/x/home", "XDG_DATA_HOME=/x/home/.local/share", "XDG_CONFIG_HOME=/x/home/.config", "/x/bin/devin", "auth", "login", "--force-manual-token-flow"]), "devin");
  assert.equal(programOf(["GH_HOST=github.com", "gh", "auth", "login"]), "gh");
  assert.equal(programOf(["env", "-i", "-u", "TOKEN", "A=b", "gcloud", "auth", "login"]), "gcloud");
  assert.equal(programOf(["sudo", "-u", "bob", "-E", "/usr/local/bin/az", "login"]), "az");
  assert.equal(programOf(["npx", "-y", "vercel@latest", "login"]), "vercel");
  assert.equal(programOf(["pnpm", "dlx", "@azure/static-web-apps-cli@2", "login"]), "static-web-apps-cli");
  assert.equal(programOf(["uvx", "--from", "azure-cli", "az", "login"]), "az");
  assert.equal(programOf(["pnpm", "login"]), "pnpm");
  assert.equal(programOf(["env"]), "env");
  // Broken at 200 columns by the program itself (no box, so the line is as wide as the terminal): put together again.
  const line = `Visit ${DEVIN_PAGE} to sign in, then copy the code and paste it below.`;
  assert.ok(DEVIN_PAGE.length > COLS);
  const broken = `${line.slice(0, COLS)}\n${line.slice(COLS)}\n\n Code:\n ❭ ••••`;
  assert.deepEqual(urlsIn(broken), [DEVIN_PAGE.slice(0, COLS - "Visit ".length)], "as it is said, the link ends where the line does");
  assert.deepEqual(urlsIn(unwrapped(broken, COLS)), [DEVIN_PAGE]);
  assert.ok(unwrapped(broken, COLS).endsWith(`${DEVIN_PAGE} to sign in, then copy the code and paste it below.\n\n Code:\n ❭ ••••`));
  // Over three lines; a short line ending in a link is left as it is.
  const long = `https://x.example/${"a".repeat(2 * COLS)}`;
  assert.deepEqual(urlsIn(unwrapped(`${long.slice(0, COLS)}\n${long.slice(COLS, 2 * COLS)}\n${long.slice(2 * COLS)}\nnext`, COLS)), [long]);
  assert.equal(unwrapped("open https://github.com/login/device\nand enter the code", COLS), "open https://github.com/login/device\nand enter the code");
  // A PKCE challenge's capitals are no device code.
  assert.equal(deviceCodeIn(`${line}\n\n Code:`), null);
  assert.equal(deviceCodeIn("open https://login.microsoft.com/device?x=ABCD-1234 and enter the code GQGFJ2QXM"), "GQGFJ2QXM");
});

// ── logins run for real ──

/// A machine for logins: a temp HOME, a bin/ for the stand-ins, Node on PATH (for the stand-ins written in it), the
/// system's tools; a Logins on a TestClock.
function machine(pages?: LoginPages) {
  const home = temp("logins");
  const bin = join(home, "bin");
  mkdirSync(bin, { recursive: true });
  const env = { HOME: home, PATH: `${bin}:${dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`, LANG: "en_US.UTF-8" };
  const time = testClock();
  const logins = new Logins({ data: join(home, "data"), env: () => env, clock: time.clock, lang: () => "zh", ...(pages ? { pages } : {}) });
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
  /// Waits until its screen shows `text` anywhere; then its output has gone quiet (the clock moved on).
  const quietShowing = async (id: string, text: string) => {
    await upon((wake) => logins.follow(id, wake), () => screen(id).includes(text), text);
    await settle(5);
    await time.adjust(QUIET_MS);
  };
  const by = { by: { email: "a@x.com", name: "张三" }, workspace: "w1" };
  return { home, bin, env, time, logins, until, quietAt, quietShowing, screen, by };
}

const skipped = WINDOWS && "logins run in a pseudo-terminal: script is Unix's";

test("a device-code login, as any tool runs it: its question left to the person, Enter pressed only to open its page, the page and the code told", { skip: skipped }, async () => {
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
echo "Logged in as octocat"
`);
  try {
    const started = await m.logins.start("fakegh auth login", m.by);
    assert.deepEqual([started.name, started.command, started.by], ["fakegh", ["fakegh", "auth", "login"], m.by.by]);
    // The same command under way is given rather than another.
    assert.equal((await m.logins.start(["fakegh", "auth", "login"], m.by)).id, started.id);
    // Its question is the person's: it waits for them, in the terminal.
    await m.quietAt(started.id, "Authenticate Git");
    const asks = await m.until(started.id, (l) => l.waiting, "waiting");
    assert.deepEqual([asks.state, asks.step], ["input", "terminal"]);
    assert.ok(!m.screen(started.id).includes("answered"), "not answered for them");
    m.logins.input(started.id, { text: "n" });
    m.logins.input(started.id, { key: "Enter" });
    const device = await m.until(started.id, (l) => l.step === "device" && l.url !== undefined, "device");
    assert.equal(device.code, "1A2B-C3D4");
    assert.ok(m.screen(started.id).includes("answered [n]"));
    await m.quietAt(started.id, "Press Enter to open");
    // Enter pressed: the page goes to the station's BROWSER, not a browser on this machine.
    await upon((w) => m.logins.follow(started.id, w), () => m.screen(started.id).includes("Waiting for the browser"), "opened");
    const opened = m.logins.get(started.id)!;
    assert.deepEqual([opened.state, opened.step, opened.url, opened.domain, opened.code, opened.waiting], ["code", "device", "https://github.com/login/device", "github.com", "1A2B-C3D4", false]);
    await approved.approve();
    await m.until(started.id, (l) => l.state === "done", "done");
    // A read-only member sees how it stands, not its page or code.
    const limited = Logins.limited(opened);
    assert.deepEqual([limited.url, limited.code, limited.domain, limited.state], [undefined, undefined, "github.com", "code"]);
  } finally {
    await m.logins.close();
  }
});

test("a login whose page gives a code to paste back (gcloud --no-launch-browser): its agent says so, not the station; the person's to enter from the card, typed with Enter", { skip: skipped }, async () => {
  const m = machine();
  const page = "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=1.apps.googleusercontent.com&redirect_uri=https%3A%2F%2Fsdk.cloud.google.com%2Fauthcode.html&state=s1";
  script(join(m.bin, "fakegcloud"), `#!/bin/sh
echo "Go to the following link in your browser, and complete the sign-in prompts:"
echo
echo "    ${page}"
echo
printf "Once finished, enter the verification code provided in your browser: "
read code
echo "got [$code]"
echo "You are now logged in as [a@x.com]."
`);
  const [tool] = loginTools({ logins: () => m.logins, starter: () => ({ ...m.by, chat: "ember:c-1" }), link: (_s, id) => `https://still.fail/w/w1/s/st/login/${id}` });
  try {
    // Waiting on its prompt is told in the answer of its agent's call, the call waiting on it then (no notice besides).
    const heard: boolean[] = [];
    const stop = m.logins.changes(({ login }) => {
      if (m.logins.get(login)?.waiting) heard.push(m.logins.heard(login));
    });
    const starting = tool!.run("ember:c-1", { command: "fakegcloud auth login --no-launch-browser" });
    const id = await upon((w) => m.logins.changes(w), () => m.logins.logins()[0]?.id, "started");
    await m.quietAt(id, "enter the verification code");
    const first = await starting;
    stop();
    assert.deepEqual(heard, [true]);
    assert.ok(!m.logins.heard(id));
    // The station does not decide it waits for the page's code: its agent, from the screen.
    const asks = m.logins.get(id)!;
    assert.deepEqual([asks.step, asks.url, asks.waiting, asks.paste], ["open", page, true, undefined]);
    assert.match(first, /unless it asks for what the page it gave hands out \(a code to paste back\): then do not answer it; login \{id, paste: true\}/);
    // Not before its agent says so: nothing is to be entered on the card yet.
    assert.throws(() => m.logins.answer(id, "4/abc"), /does not wait for a code/);
    const told = await tool!.run("ember:c-1", { id, paste: true });
    assert.equal(m.logins.get(id)!.paste, true);
    assert.match(told, /enter what it gives \(a code\) in the login card's field/);
    assert.match(told, /do not answer its prompt yourself/);
    assert.throws(() => m.logins.answer(id, "  "), /text/);
    assert.throws(() => m.logins.answer(id, "a\nb"), /one line/);
    const answered = m.logins.answer(id, " 4/0AXlq-code ", { email: "b@x.com", name: "李四" });
    assert.deepEqual([answered.doneBy?.name, answered.paste, answered.state], ["李四", true, "verifying"], "entered: the field stays, what was entered checked in place");
    assert.throws(() => m.logins.answer(id, "4/again"), /being checked/);
    await m.until(id, (l) => l.state === "done", "done");
    assert.ok(m.screen(id).includes("got [4/0AXlq-code]"), m.screen(id));
  } finally {
    await m.logins.close();
  }
});

test("Devin's sign-in (env and its variables before it, a page longer than the terminal is wide, then a masked field read key by key): named devin, the whole page given, and a field on the card once its agent says so", { skip: skipped }, async () => {
  const m = machine();
  // As Devin draws it: the line broken at the terminal's width by the program, the code read in raw mode with no echo,
  // a dot drawn for each key.
  script(join(m.bin, "fakedevin"), `#!/usr/bin/env node
const out = (s) => process.stdout.write(s);
const line = ${JSON.stringify(`Visit ${DEVIN_PAGE} to sign in, then copy the code and paste it below.`)};
const cols = Number(process.env.COLUMNS) || 80;
out(line.slice(0, cols) + "\\r\\n" + line.slice(cols) + "\\r\\n\\r\\n Code:\\r\\n ❭ " + "•".repeat(42) + "\\r\\n ↵ submit · esc cancel\\u001b[1A\\r\\u001b[3C");
process.stdin.setRawMode(true);
let code = "";
process.stdin.on("data", (d) => {
  for (const c of d.toString()) {
    if (c === "\\r") {
      out("\\r\\n\\r\\n\\r\\ngot [" + code + "] for " + process.env.XDG_CONFIG_HOME + "\\r\\n");
      process.exit(0);
    }
    code += c;
    out("•");
  }
});
`);
  const [tool] = loginTools({ logins: () => m.logins, starter: () => ({ ...m.by, chat: "ember:c-1" }), link: (_s, id) => `https://still.fail/w/w1/s/st/login/${id}` });
  const home = join(m.home, "devin");
  try {
    const command = `env HOME=${home} XDG_DATA_HOME=${home}/.local/share XDG_CONFIG_HOME=${home}/.config ${join(m.bin, "fakedevin")} auth login --force-manual-token-flow`;
    const starting = tool!.run("ember:c-1", { command });
    const id = await upon((w) => m.logins.changes(w), () => m.logins.logins()[0]?.id, "started");
    await m.quietAt(id, "❭");
    const first = await starting;
    const login = m.logins.get(id)!;
    assert.equal(login.name, "fakedevin");
    // The whole page, past the line's end; no code read from its challenge; nothing the station decides it waits for.
    assert.deepEqual([login.step, login.state, login.url, login.code, login.paste], ["open", "browser", DEVIN_PAGE, undefined, undefined]);
    assert.match(first, /if the screen says the page gives a code to paste back here, first login \{id, paste: true\}/);
    assert.ok(first.includes("copy the code and paste it below") && !first.includes("app.devin.ai"), first);
    assert.throws(() => m.logins.answer(id, "abc"), /does not wait for a code/);
    // Its agent says so: the card's field, and what the person enters typed at its masked field with Enter.
    assert.match(await tool!.run("ember:c-1", { id, paste: true }), /in the login card's field/);
    assert.equal(m.logins.get(id)!.paste, true);
    const answered = m.logins.answer(id, "dvn_code-123", { email: "b@x.com", name: "李四" });
    assert.deepEqual([answered.paste, answered.state], [true, "verifying"]);
    await m.until(id, (l) => l.state === "done", "done");
    assert.ok(m.screen(id).includes(`got [dvn_code-123] for ${home}/.config`), m.screen(id));
  } finally {
    await m.logins.close();
  }
});

test("the agent drives the command through its tool: it sees the screen without the page or code, answers the Y/n itself, and is told when the person's step is ready", { skip: skipped }, async () => {
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
`);
  const [tool] = loginTools({ logins: () => m.logins, starter: () => ({ ...m.by, chat: "ember:c-1", chatTitle: "部署" }), link: (_s, id) => `https://still.fail/w/w1/s/st/login/${id}` });
  try {
    const starting = tool!.run("ember:c-1", { command: "fakegh auth login" });
    const id = await upon((w) => m.logins.changes(w), () => m.logins.logins()[0]?.id, "started");
    await m.quietAt(id, "Authenticate Git");
    const asked = await starting;
    assert.match(asked, /\? Authenticate Git with your GitHub credentials\? \(Y\/n\)/);
    assert.match(asked, /It waits on the prompt above: answer it with login/);
    assert.ok(!asked.includes("card"), "no card yet: nothing is the person's to do");
    // Its default, as the agent takes it: Enter.
    const answering = tool!.run("ember:c-1", { id, key: "enter" });
    await m.quietAt(id, "Press Enter to open");
    await upon((w) => m.logins.follow(id, w), () => m.screen(id).includes("Waiting for the browser"), "opened");
    // Quiet again (its cursor on the line after what it said).
    await settle(5);
    await m.time.adjust(QUIET_MS);
    const ready = await answering;
    assert.ok(m.screen(id).includes("answered []"));
    assert.match(ready, /The person's browser step is ready: chat_post with card \{"type": "login", "login": "/);
    assert.ok(ready.includes("<code>") && ready.includes("<link>"), ready);
    assert.ok(!ready.includes("1A2B-C3D4") && !ready.includes("github.com/login/device"), "neither the code nor the page");
    assert.equal(m.logins.get(id)!.chatTitle, "部署");
    await approved.approve();
    await m.until(id, (l) => l.state === "done", "done");
    assert.match(await tool!.run("ember:c-1", { id }), /It finished/);
    await assert.rejects(tool!.run("ember:c-1", { id, key: "f13" }), /key: one of/);
  } finally {
    await m.logins.close();
  }
});

test("a login another station's agent started (its tool's station): told where it runs and the card's station, its own logins only, told as it ends", { skip: skipped }, async () => {
  const m = machine();
  const approved = approval(m.home);
  script(join(m.bin, "fakegh"), `#!/bin/sh
echo "! First copy your one-time code: 1A2B-C3D4"
"$BROWSER" https://github.com/login/device
echo "Waiting for the browser"
read ok < '${approved.path}'
`);
  const here = { station: "b".repeat(64), name: "Mini1" };
  const peer = (station: string) => ({ starter: () => ({ ...m.by, chat: null, chatTitle: "部署", peer: { station, session: "ember:c-a" } }), link: (id: string) => `https://still.fail/w/w1/s/${here.station}/login/${id}`, where: here, mine: (id: string) => m.logins.starterOf(id)?.peer?.station === station });
  // The agent's tool hands a call naming a station to the station transport (logins/module.ts), as it was given.
  const asked: unknown[] = [];
  const [tool] = loginTools({ logins: () => m.logins, starter: () => ({ ...m.by, chat: "ember:c-1" }), link: () => null, remote: async (station, session, args) => (asked.push({ station, session, args }), "told there") });
  try {
    assert.equal(await tool!.run("ember:c-1", { station: "Mini1", command: "gh auth login" }), "told there");
    assert.deepEqual(asked, [{ station: "Mini1", session: "ember:c-1", args: { station: "Mini1", command: "gh auth login" } }]);
    // On the station it runs on: started for the other station's agent, its chat none here.
    const starting = act(m.logins, { command: "fakegh auth login" }, peer("a".repeat(64)));
    const id = await upon((w) => m.logins.changes(w), () => m.logins.logins()[0]?.id, "started");
    await upon((w) => m.logins.follow(id, w), () => m.screen(id).includes("Waiting for the browser"), "opened");
    await settle(5);
    await m.time.adjust(QUIET_MS);
    const ready = await starting;
    assert.ok(ready.includes(`card {"type": "login", "login": "${id}", "station": "${here.station}"}`), ready);
    assert.match(ready, /who should log in to what on Mini1 and why/);
    assert.match(ready, /"stationName": "Mini1"/);
    assert.equal(m.logins.get(id)!.chat, undefined, "no chat of this station's");
    assert.deepEqual(m.logins.starterOf(id)!.peer, { station: "a".repeat(64), session: "ember:c-a" });
    // Another station acts only on the logins it started.
    await assert.rejects(act(m.logins, { id }, peer("c".repeat(64))), /no login/);
    assert.match(await act(m.logins, { id }, peer("a".repeat(64))), /The person's browser step is ready/);
    assert.match(promptNotice(m.logins, m.logins.get(id)!, null, here), /^The login on Mini1 you started/);
    await approved.approve();
    const done = await m.until(id, (l) => l.state === "done", "done");
    assert.match(endedNotice(done, null, here), /^The login on Mini1 you started or posted a card for, fakegh auth login/);
  } finally {
    await m.logins.close();
  }
});

test("the screen as the agent reads it: the page and the code hidden, the cursor's line marked, nothing past the last line", () => {
  const login = { code: "1A2B-C3D4" } as Login;
  const rows = ["! First copy your one-time code: 1A2B-C3D4", "Press Enter to open https://github.com/login/device in your browser... ", "", "", ""];
  assert.equal(screenFor({ rows, cursor: { x: 70, y: 1 }, echo: true, live: true }, login), "! First copy your one-time code: <code>\nPress Enter to open <link> in your browser...▏");
  assert.equal(screenFor(null, login), "");
});

test("a tool nobody described: its device code and page read from what it says", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "acme"), `#!/bin/sh\necho "Acme CLI 3.1"\necho "To finish, open https://login.acme.example/activate and enter code: WDJB-MJHT"\necho "(the code lasts 10 minutes)"\nread forever\n`);
  try {
    const login = await m.logins.start("acme login --device", m.by);
    const device = await m.until(login.id, (l) => l.step === "device", "device");
    assert.deepEqual([device.code, device.url, device.domain, device.state], ["WDJB-MJHT", "https://login.acme.example/activate", "login.acme.example", "code"]);
  } finally {
    await m.logins.close();
  }
});

test("a login waiting on prompts: its terminal answers the program's queries, its agent types a name, and nothing is typed at a password prompt", { skip: skipped }, async () => {
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
    const login = await m.logins.start("fakeprompt --user", m.by);
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
    // A secret is nobody's to type here: refused, nothing sent.
    assert.throws(() => m.logins.input(login.id, { text: "s3cret" }), (e: unknown) => e instanceof Refused && e.status === 409 && /secret/.test(e.message));
    assert.throws(() => m.logins.input(login.id, { key: "Enter" }), (e: unknown) => e instanceof Refused && /secret/.test(e.message));
    assert.ok(m.screen(login.id).trimEnd().endsWith("Password:"), "nothing reached it");
    assert.equal(m.logins.get(login.id)!.state, "input");
    stop();
    m.logins.cancel(login.id);
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
      const login = await m.logins.start(["fakeloop", host, mode], m.by);
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
      await m.until(login.id, (l) => l.state === "done", "done");
      assert.match(m.screen(login.id), mode === "post" ? /got POST \/ code=c0de&state=s3cret host=localhost:\d+/ : /got GET \/callback\?code=c0de&state=s3cret  host=localhost:\d+/);
    } finally {
      await m.logins.close();
    }
  });
}

test("a login's page opened in the station's browser: the page its command opened, one tab however often asked, its browser back to the command here with nothing relayed, the tab closed as it ends", { skip: skipped }, async () => {
  const b = fakeBrowser();
  const m = machine(b.pages);
  script(join(m.bin, "fakeloop"), LOOPBACK);
  const by = { email: "b@x.com", name: "李四" };
  try {
    const login = await m.logins.start(["fakeloop", "127.0.0.1", "get"], m.by);
    const waiting = await m.until(login.id, (l) => l.step === "loopback", "loopback");
    assert.deepEqual([waiting.browser, waiting.screen], [true, undefined]);
    assert.equal(await m.logins.openPage(login.id, by), "browser:T1");
    assert.deepEqual([...b.tabs.values()], [waiting.url], "the page it opened, which comes back to it here");
    await m.until(login.id, (l) => l.screen === "browser:T1", "its tab told");
    // Asked again (from another device): the same tab, brought forward.
    assert.equal(await m.logins.openPage(login.id), "browser:T1");
    assert.deepEqual(b.fronted, ["T1"]);
    // A read-only member is not told of it.
    const limited = Logins.limited(m.logins.get(login.id)!);
    assert.deepEqual([limited.browser, limited.screen], [undefined, undefined]);
    // Closed by a person: told, and opened again when asked.
    b.gone("T1");
    await m.until(login.id, (l) => l.screen === undefined, "its tab gone");
    assert.equal(await m.logins.openPage(login.id, by), "browser:T2");
    // The station's browser comes back to the command on this machine itself.
    const back = waiting.callback!;
    await fetch(`http://127.0.0.1:${back.port}${back.path}?code=c0de&state=s3cret`);
    const done = await m.until(login.id, (l) => l.state === "done", "done");
    assert.deepEqual([done.screen, done.browser, done.doneBy], [undefined, undefined, by], "who finished it: whose browser step it was");
    assert.equal(b.tabs.size, 0, "its tab closed as it ended");
    await assert.rejects(m.logins.openPage(login.id), (e: unknown) => e instanceof Refused && e.status === 409);
  } finally {
    await m.logins.close();
  }
});

test("a device code's page opens with its code where the service gives one; a station with no Chrome offers none", { skip: skipped }, async () => {
  const b = fakeBrowser();
  const m = machine(b.pages);
  script(join(m.bin, "fakecode"), `#!/bin/sh\necho "Visit https://vercel.com/oauth/device?user_code=ABCD-EFGH"\nread forever\n`);
  const none = machine(fakeBrowser(() => {}, false).pages);
  script(join(none.bin, "fakecode"), `#!/bin/sh\necho "Visit https://vercel.com/oauth/device?user_code=ABCD-EFGH"\nread forever\n`);
  try {
    const login = await m.logins.start("fakecode", m.by);
    await m.until(login.id, (l) => l.step === "device" && l.browser === true, "device");
    await m.logins.openPage(login.id);
    assert.deepEqual([...b.tabs.values()], ["https://vercel.com/oauth/device?user_code=ABCD-EFGH"]);
    m.logins.cancel(login.id);
    assert.equal(b.tabs.size, 0);
    const there = await none.logins.start("fakecode", none.by);
    const device = await none.until(there.id, (l) => l.step === "device", "device");
    assert.equal(device.browser, undefined);
    await assert.rejects(none.logins.openPage(there.id), (e: unknown) => e instanceof Refused && e.status === 501);
  } finally {
    await m.logins.close();
    await none.logins.close();
  }
});

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
    const taken = await m.logins.start(["fakeport"], m.by);
    await m.until(taken.id, (l) => l.step === "loopback", "loopback");
    await assert.rejects(
      m.logins.callback(taken.id, { method: "GET", path: "/cb?state=s1&code=x", headers: { host: `127.0.0.1:${port}` } }),
      (e: unknown) => e instanceof Refused && e.status === 409 && e.message.includes(`does not listen on port ${port}`),
    );
    assert.equal(reached, 0, "the code never went to the other program");
    const cancelled = m.logins.cancel(taken.id);
    assert.equal(cancelled.state, "cancelled");
    const gone = await m.logins.start(["fakegone"], m.by);
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

test("gh's Enter to open its page, the cursor on the empty line under it: pressed by the station, and the login finishes with nobody typing", { skip: skipped }, async () => {
  const m = machine();
  // As gh prints it: the code, then its Enter line ended by a newline, so the cursor waits on the line under it.
  script(join(m.bin, "fakegh"), `#!/bin/sh
echo "! First copy your one-time code: 1A2B-C3D4"
echo "Press Enter to open https://github.com/login/device in your browser... "
read go
"$BROWSER" https://github.com/login/device
echo "✓ Authentication complete."
`);
  try {
    const started = await m.logins.start("fakegh auth login", m.by);
    await m.until(started.id, (l) => l.step === "device" && l.code === "1A2B-C3D4", "device");
    await m.quietShowing(started.id, "Press Enter to open");
    const done = await m.until(started.id, (l) => l.state === "done", "done");
    assert.equal(done.url, "https://github.com/login/device");
  } finally {
    await m.logins.close();
  }
});

test("a login silent once nothing is left for anyone (it said it is logged in) ends after a while, saying so with its last screen; silent while the person signs in, it goes on", { skip: skipped }, async () => {
  const m = machine();
  const approved = approval(m.home);
  const stuck = approval(m.home);
  script(join(m.bin, "fakestuck"), `#!/bin/sh
echo "! First copy your one-time code: 1A2B-C3D4"
printf "Press Enter to open https://github.com/login/device in your browser... "
read go
"$BROWSER" https://github.com/login/device
echo "Waiting for the browser"
read ok < '${approved.path}'
echo "✓ Authentication complete."
echo "- gh config set -h github.com git_protocol https"
read never < '${stuck.path}'
`);
  try {
    const started = await m.logins.start(["fakestuck"], m.by);
    await m.quietShowing(started.id, "Press Enter to open");
    await m.quietShowing(started.id, "Waiting for the browser");
    // The person takes their time: silence then is theirs, not the command's.
    await m.time.adjust(STALL_MS);
    await settle(20);
    assert.equal(m.logins.get(started.id)!.state, "code");
    await approved.approve();
    await m.quietShowing(started.id, "git_protocol");
    await m.time.adjust(STALL_MS);
    const ended = await m.until(started.id, (l) => l.state === "failed", "stalled");
    assert.equal(ended.timedOut, true);
    assert.match(ended.error!, /^登录命令在不需要人的时候 3 分钟没有动静/);
    assert.match(ended.error!, /✓ Authentication complete\.\n- gh config set -h github\.com git_protocol https$/);
    // Its agent is told why, with the screen, the page and code hidden.
    const told = endedNotice(ended, null);
    assert.match(told, /failed: 登录命令在不需要人的时候 3 分钟没有动静.* \/ ✓ Authentication complete\. \/ - gh config set/);
    assert.ok(!told.includes("1A2B-C3D4") && !told.includes("https://"), told);
  } finally {
    await m.logins.close();
  }
});

test("git's credential helpers are kept out of a login's command (no keychain to wait on), ~/.gitconfig left as it was but for what the command writes", { skip: skipped }, async () => {
  const m = machine();
  const ran = join(m.home, "helper-ran");
  script(join(m.bin, "keychain-helper"), `#!/bin/sh
echo "$@" >> '${ran}'
cat > /dev/null
`);
  const gitconfig = join(m.home, ".gitconfig");
  writeFileSync(gitconfig, `[user]\n\tname = Someone\n[credential]\n\thelper = ${join(m.bin, "keychain-helper")}\n`);
  // As gh does when told to authenticate git: asks git for its helper, has git store the token through it, and (none
  // set) adds its own for github.com.
  script(join(m.bin, "fakegit"), `#!/bin/sh
echo "helper [$(git config --get credential.helper)]"
printf 'protocol=https\nhost=github.com\nusername=octocat\npassword=t0ken\n\n' | git credential approve
git config --global --add credential.https://github.com.helper '!fakegh auth git-credential'
echo "Logged in as octocat"
`);
  try {
    const started = await m.logins.start(["fakegit"], m.by);
    await m.until(started.id, (l) => l.state === "done", "done");
    assert.ok(m.screen(started.id).includes("helper []"), m.screen(started.id));
    assert.equal(existsSync(ran), false, "the file's helper was not run");
    const after = readFileSync(gitconfig, "utf8");
    assert.ok(after.startsWith(`[user]\n\tname = Someone\n[credential]\n\thelper = ${join(m.bin, "keychain-helper")}\n`), after);
    assert.match(after, /helper = !fakegh auth git-credential/);
  } finally {
    await m.logins.close();
  }
});

test("a login not finished in time ends, its command with it; one that cannot run says why", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "fakeslow"), `#!/bin/sh\necho "Visit https://example.com/activate"\nread forever\n`);
  try {
    const slow = await m.logins.start(["fakeslow"], m.by);
    await m.until(slow.id, (l) => l.step === "open", "open");
    await m.time.adjust(TIMEOUT_MS);
    const ended = await m.until(slow.id, (l) => l.state === "failed", "timed out");
    assert.equal(ended.error, "15 分钟内没有完成登录，已结束");
    assert.equal(m.logins.logins()[0]!.id, slow.id);
    const none = await m.logins.start(["no-such-login-command"], m.by);
    const failed = await m.until(none.id, (l) => l.state === "failed", "cannot run");
    assert.ok(failed.error !== undefined && failed.error !== "", JSON.stringify(failed));
    await assert.rejects(m.logins.start("gh 'open", m.by), (e: unknown) => e instanceof Refused && e.status === 400);
    await assert.rejects(m.logins.start("  ", m.by), (e: unknown) => e instanceof Refused && e.status === 400);
  } finally {
    await m.logins.close();
  }
});

test("the logins done here are kept: command, who, when and how each ended, without its page, code or output", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "fakeok"), `#!/bin/sh\necho "Open https://example.com/device and enter WXYZ-1234"\necho done\n`);
  script(join(m.bin, "fakewait"), `#!/bin/sh\necho "Open https://example.com/device and enter WXYZ-5678"\nread forever\n`);
  try {
    const ok = await m.logins.start("fakeok", m.by);
    await m.until(ok.id, (l) => l.state === "done", "done");
    const waits = await m.logins.start("fakewait", { ...m.by, chat: "ember:c-1", chatTitle: "部署" });
    await m.until(waits.id, (l) => l.step === "device", "device");
    m.logins.cancel(waits.id, { email: "b@x.com", name: "李四" });
    // A station started again: what it kept.
    const again = new Logins({ data: join(m.home, "data"), env: () => m.env, clock: m.time.clock, lang: () => "zh" });
    const kept = again.logins();
    assert.deepEqual(kept.map((l) => [l.command.join(" "), l.state, l.by.name]), [["fakewait", "cancelled", "张三"], ["fakeok", "done", "张三"]]);
    assert.ok(kept.every((l) => l.url === undefined && l.code === undefined && l.error === undefined && typeof l.endedAt === "number"));
    assert.equal(again.get(ok.id)!.state, "done");
    assert.deepEqual([kept[0]!.chat, kept[0]!.chatTitle, kept[0]!.doneBy?.name], ["ember:c-1", "部署", "李四"]);
    await again.close();
  } finally {
    await m.logins.close();
  }
});

test("the routes: a read-only member's list has no pages or codes; no route starts a login, or types into one but a page's code while it waits for one", { skip: skipped }, async () => {
  const m = machine();
  script(join(m.bin, "fakecode"), `#!/bin/sh\necho "Open https://example.com/device and enter WXYZ-1234"\nread forever\n`);
  const all = routes(() => m.logins);
  assert.deepEqual(all.map((r) => r.method), ["GET", "GET", "DELETE", "POST", "POST"], "list, one, cancel, a page's code, callback: starting one is an agent's");
  const [list, , cancel, answer] = all;
  const ask = (route: (typeof list), role: string, body: Json = {}, args: string[] = []) =>
    route!.handle({ method: route!.method, path: "/machine-logins", query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), viewer: { sub: "s", email: "a@x.com", name: "张三", role, workspace: "w1", device: "d" }, lang: "zh" }, args);
  const read = async (answer: Promise<{ status: number; body: unknown }>) => {
    const a = await answer;
    return { status: a.status, body: JSON.parse((a.body as Buffer).toString()) };
  };
  try {
    const started = await m.logins.start("fakecode", m.by);
    await m.until(started.id, (l) => l.step === "device", "device");
    const member = await read(ask(list, "member"));
    const viewer = await read(ask(list, "viewer"));
    const mine = member.body.logins.find((l: Json) => l.id === started.id);
    const theirs = viewer.body.logins.find((l: Json) => l.id === started.id);
    assert.deepEqual([mine.code, mine.url], ["WXYZ-1234", "https://example.com/device"]);
    assert.deepEqual([theirs.code, theirs.url, theirs.step, theirs.domain], [undefined, undefined, "device", "example.com"]);
    // A page's code: not a read-only member's, and only while it waits for one (this one waits for nothing typed).
    assert.equal((await read(ask(answer!, "viewer", { text: "x" }, [started.id]))).status, 403);
    const typed = await read(ask(answer!, "member", { text: "x" }, [started.id]));
    assert.deepEqual([typed.status, typed.body.error], [409, "this login does not wait for a code from its page"]);
    // Nor may its agent say it does, with a device code and no page to sign in on and come back from.
    assert.throws(() => m.logins.paste(started.id, true), /only once it has given a page to open/);
    const cancelled = (await read(ask(cancel!, "member", {}, [started.id]))).body;
    assert.deepEqual([cancelled.state, cancelled.doneBy], ["cancelled", { email: "a@x.com", name: "张三" }], "who finished it: who cancelled it");
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
