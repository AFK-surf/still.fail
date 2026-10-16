// A login's browser came back to a loopback port on the person's device, and their client handed the request here
// (docs/remote-login.md, 回环回调): it goes to the login command, once, on the port its page named, and only when that
// port is the command's own (lsof: the command or what it started listens there). Nothing is ever sent to the callback
// to try it: a request with a wrong state ends most of these commands (gcloud, aws, Claude Code, wrangler). The
// command's answer (its 登录成功 page) goes back as it was.
import { request as httpRequest } from "node:http";
import { platform } from "../platform/index.ts";
import type { LoginRun } from "./run.ts";

export type Callback = { method: string; path: string; headers: Record<string, string>; body?: string };
export type Answered = { status: number; headers: Record<string, string>; body: string };

/// Why a callback was not relayed: its words, and the status it is answered with.
export class Refused extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/// Headers that are the connection's, not the request's.
const HOP = new Set(["connection", "keep-alive", "transfer-encoding", "upgrade", "proxy-connection", "proxy-authorization", "te", "trailer", "content-length"]);
/// What is taken of an answer at most.
const MOST = 1_000_000;

/// The callback's state: in its query (GET), or its form (POST, form_post).
export function stateOf(callback: Callback): string | null {
  const at = callback.path.indexOf("?");
  const query = new URLSearchParams(at < 0 ? "" : callback.path.slice(at + 1));
  if (callback.method === "POST") {
    const form = new URLSearchParams(Buffer.from(callback.body ?? "", "base64").toString("utf8"));
    return form.get("state") ?? query.get("state");
  }
  return query.get("state");
}

/// Whether a callback is the one this login waits for: its method, its path, its state. Throws Refused when not.
export function check(run: LoginRun, callback: Callback): void {
  const back = run.loopback;
  if (!run.active) throw new Refused(409, "this login has ended");
  if (back === null || run.step !== "loopback") throw new Refused(409, "this login does not wait for a browser to come back");
  if (run.relayed) throw new Refused(409, "this login's callback was relayed already");
  if (back.state === null) throw new Refused(409, "this login's page names no state: its callback is not relayed");
  const method = callback.method.toUpperCase();
  if (method !== (back.post ? "POST" : "GET")) throw new Refused(400, `this login's callback is a ${back.post ? "POST" : "GET"}`);
  const at = callback.path.indexOf("?");
  const path = at < 0 ? callback.path : callback.path.slice(0, at);
  if ((path === "" ? "/" : path) !== back.path) throw new Refused(400, "not this login's callback path");
  if (stateOf(callback) !== back.state) throw new Refused(400, "not this login's state");
}

/// The callback handed to the login command, and its answer. Refused (and nothing sent) when it is not the one the login
/// waits for, or its port is not the command's.
export async function relay(run: LoginRun, callback: Callback): Promise<Answered> {
  check(run, callback);
  const back = run.loopback!;
  const pids = await run.pids();
  const addresses = await platform.listening(pids, back.port);
  if (addresses === null) throw new Refused(409, "this machine cannot tell which program listens on the port: the callback is not relayed");
  if (addresses.length === 0) throw new Refused(409, `the login command does not listen on port ${back.port}${pids.length === 0 ? " (it has ended)" : ""}`);
  // Once only, from here: a second callback is refused even while this one is under way.
  check(run, callback);
  run.relayedNow();
  // Where it listens, as lsof saw it: ::1 for one that listens there only (Claude Code, wrangler), else 127.0.0.1.
  const order = addresses.includes("::1") && !addresses.some((a) => a === "127.0.0.1" || a === "*" || a === "0.0.0.0") ? ["::1", "127.0.0.1"] : ["127.0.0.1", "::1"];
  const headers: Record<string, string> = {};
  for (const [k, v] of Object.entries(callback.headers)) if (!HOP.has(k.toLowerCase())) headers[k.toLowerCase()] = v;
  const body = callback.body ? Buffer.from(callback.body, "base64") : Buffer.alloc(0);
  if (body.length > 0) headers["content-length"] = String(body.length);
  headers.connection = "close";
  for (const [i, address] of order.entries()) {
    try {
      return await send(address, back.port, callback.method.toUpperCase(), callback.path, headers, body);
    } catch (e) {
      // Only a refused connection tries the other address: the request went nowhere.
      if ((e as NodeJS.ErrnoException).code !== "ECONNREFUSED" || i === order.length - 1) throw new Refused(502, `the login command did not answer: ${(e as Error).message}`);
    }
  }
  throw new Refused(502, "the login command did not answer");
}

function send(host: string, port: number, method: string, path: string, headers: Record<string, string>, body: Buffer): Promise<Answered> {
  return new Promise((resolve, reject) => {
    const req = httpRequest({ host, port, method, path, headers, family: host.includes(":") ? 6 : 4, signal: AbortSignal.timeout(30_000) }, (res) => {
      const parts: Buffer[] = [];
      let size = 0;
      res.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size <= MOST) parts.push(chunk);
      });
      res.on("end", () => {
        const out: Record<string, string> = {};
        for (const [k, v] of Object.entries(res.headers)) if (v !== undefined && !HOP.has(k)) out[k] = Array.isArray(v) ? v.join(", ") : v;
        resolve({ status: res.statusCode ?? 502, headers: out, body: Buffer.concat(parts).toString("base64") });
      });
      res.on("error", reject);
    });
    req.on("error", reject);
    req.end(body);
  });
}
