// What the accounts' tests stand in for: providers (a local HTTP server answering as a test says, keeping what it was
// asked), command-line tools (shell scripts in a bin/ of a temp HOME, first on a PATH of only that and the system's),
// and a machine (a temp HOME with its own .claude and .codex). Nothing here reaches a real service, keychain or login.
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { createServer, type IncomingMessage } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";

export type Asked = { method: string; url: string; headers: Record<string, string>; body: any };
export type Reply = { status: number; body: unknown; delayMs?: number };

/// A provider at a local address: `answer` says what each request gets; `asked` keeps the requests in order.
export async function provider(answer: (asked: Asked) => Reply) {
  const asked: Asked[] = [];
  const server = createServer(async (req: IncomingMessage, res) => {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const text = Buffer.concat(chunks).toString("utf8");
    let body: any = null;
    try {
      body = text === "" ? null : JSON.parse(text);
    } catch {}
    const one: Asked = { method: req.method ?? "", url: req.url ?? "", headers: Object.fromEntries(Object.entries(req.headers).map(([k, v]) => [k, String(v)])), body };
    asked.push(one);
    const reply = answer(one);
    if (reply.delayMs) await new Promise((r) => setTimeout(r, reply.delayMs));
    const out = typeof reply.body === "string" ? reply.body : JSON.stringify(reply.body);
    res.writeHead(reply.status, { "content-type": "application/json", connection: "close" });
    res.end(out);
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const base = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;
  return { base, asked, close: () => new Promise<void>((resolve) => server.close(() => resolve())) };
}

export const temp = (name: string) => mkdtempSync(join(tmpdir(), `accounts-${name}-`));

/// A machine: a HOME, and a bin/ with stand-ins for the CLIs (shell scripts) on a PATH of only that and the system's.
/// A `security` that finds nothing of Claude Code's unless one is given (never the real keychain).
export function machine(clis: Record<string, string> = {}): { home: string; bin: string; env: Record<string, string> } {
  const home = temp("machine");
  const bin = join(home, "bin");
  mkdirSync(bin);
  for (const [name, script] of Object.entries({ security: "exit 44", ...clis })) {
    const path = join(bin, name);
    writeFileSync(path, script.startsWith("#!") ? script : `#!/bin/sh\n${script}\n`);
    chmodSync(path, 0o755);
  }
  return { home, bin, env: { HOME: home, PATH: `${bin}:/usr/bin:/bin` } };
}

/// An executable script at `path`.
export function script(path: string, text: string) {
  writeFileSync(path, text);
  chmodSync(path, 0o755);
}

/// The stand-in login command (login.rs's tests): Claude's prints a link and reads a code; Codex's prints a device
/// link and a code, then finishes.
export const FAKE_LOGIN = `#!/bin/sh
if [ "$1" = "auth" ]; then
  echo "Opening browser to sign in…"
  echo "If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=x&state=y"
  printf "Paste code here if prompted > "
  read code
  [ "$code" = "good-code" ] && { echo "Login successful"; exit 0; }
  echo "OAuth error: invalid code"; exit 1
fi
printf "1. Open this link\\n   \\033[94mhttps://auth.openai.com/codex/device\\033[0m\\n2. Enter this one-time code\\n   \\033[94mABCD-12345\\033[0m\\n"
sleep 0.3
echo "Successfully logged in"
`;

/// Waits until `f` gives something (up to 30 s: a new executable can take long to start on a busy machine).
export async function until<T>(f: () => T | undefined | null | false, what: string, ms = 30_000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const got = f();
    if (got) return got;
    if (Date.now() > end) throw new Error(`never: ${what}`);
    await new Promise((r) => setTimeout(r, 20));
  }
}

export const idToken = (claims: unknown) => `x.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.y`;
