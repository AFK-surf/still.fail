// A stand-in for Feishu on a local port (docs/feishu.md「测试」): its OpenAPI (each call recorded and answered by the
// test), its long connection (/callback/ws/endpoint gives a socket on the same port, frames as Feishu encodes them;
// the test sends events down it and sees what the station acknowledges), and the app registration's device flow.
// Nothing reaches the real Feishu.
import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { WebSocketServer, type WebSocket } from "ws";
import { CONTROL, DATA, type Frame, decode, encode, header } from "../src/feishu/frame.ts";

type Json = any;

/// A call the stand-in saw: its method and path, its bearer token, its query, its JSON body (or multipart fields).
export type Seen = { method: string; path: string; auth: string; query: Record<string, string>; body: Json };

export type Answer = (seen: Seen) => Json | Promise<Json>;

export class FakeFeishu {
  readonly server: Server;
  readonly wss: WebSocketServer;
  base = "";
  seen: Seen[] = [];
  answers = new Map<string, Answer>();
  sockets: WebSocket[] = [];
  /// The data frames that came back up (acknowledgements), and the control frames (pings).
  acks: Frame[] = [];
  pings = 0;
  /// The bot it says the app has.
  bot = { open_id: "ou_bot", app_name: "Codex 机器人", avatar_url: "https://example.test/bot.png" };
  private waiters: (() => void)[] = [];
  private n = 1;

  constructor() {
    this.server = createServer((req, res) => {
      void this.take(req).then(
        (body) => res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(body)),
        (error) => res.writeHead(500).end(String(error)),
      );
    });
    this.wss = new WebSocketServer({ noServer: true });
    this.server.on("upgrade", (req, socket, head) => {
      this.wss.handleUpgrade(req, socket, head, (ws) => {
        this.sockets.push(ws);
        ws.on("message", (data) => {
          const f = decode(new Uint8Array(data as Buffer));
          if (f.method === CONTROL) {
            this.pings++;
            if (header(f, "type") === "ping") ws.send(encode({ ...f, headers: [["type", "pong"]], payload: new TextEncoder().encode(JSON.stringify({ PingInterval: 120 })) }));
          } else this.acks.push(f);
          this.tell();
        });
        this.tell();
      });
    });
  }

  static async start(): Promise<FakeFeishu> {
    const fake = new FakeFeishu();
    await new Promise<void>((resolve) => fake.server.listen(0, "127.0.0.1", resolve));
    fake.base = `http://127.0.0.1:${(fake.server.address() as AddressInfo).port}`;
    return fake;
  }

  /// Calls of `method path` (path without its query), in order.
  calls(method: string, path: string | RegExp): Seen[] {
    return this.seen.filter((s) => s.method === method && (typeof path === "string" ? s.path === path : path.test(s.path)));
  }

  answer(key: string, answer: Answer | Json) {
    this.answers.set(key, typeof answer === "function" ? (answer as Answer) : () => answer);
  }

  /// An event down the newest socket, as Feishu sends one (a data frame of type event); its frame's message id.
  event(type: string, event: Json, eventId = `ev-${this.n++}`): string {
    const ws = this.sockets.at(-1);
    if (!ws) throw new Error("no socket open");
    const payload = new TextEncoder().encode(JSON.stringify({ schema: "2.0", header: { event_id: eventId, event_type: type, tenant_key: "tk1", app_id: "cli_test" }, event }));
    const id = `frame-${eventId}`;
    ws.send(encode({ seqId: 1n, logId: 2n, service: 7, method: DATA, headers: [["type", "event"], ["message_id", id], ["sum", "1"], ["seq", "0"], ["trace_id", "t"]], payload }));
    return id;
  }

  /// Someone's message: in `chat` (a group unless `p2p`), with `text`, @ing the bot when `at`.
  message(o: { id: string; chat?: string; user?: string; text?: string; at?: boolean; p2p?: boolean; thread?: string; root?: string; type?: string; content?: Json }) {
    const text = o.text ?? "hi";
    const content = o.content ?? { text: o.at ? `@_user_1 ${text}` : text };
    return this.event("im.message.receive_v1", {
      sender: { sender_id: { open_id: o.user ?? "ou_ada" }, sender_type: "user", tenant_key: "tk1" },
      message: {
        message_id: o.id,
        chat_id: o.chat ?? "oc_g",
        chat_type: o.p2p ? "p2p" : "group",
        message_type: o.type ?? "text",
        content: JSON.stringify(content),
        ...(o.thread ? { thread_id: o.thread, root_id: o.root ?? o.id } : {}),
        mentions: o.at ? [{ key: "@_user_1", id: { open_id: this.bot.open_id }, name: this.bot.app_name }] : [],
      },
    });
  }

  /// The acknowledgement of a frame, its payload parsed.
  ack(frameId: string): Json | undefined {
    const f = this.acks.find((a) => header(a, "message_id") === frameId);
    return f?.payload ? JSON.parse(new TextDecoder().decode(f.payload)) : undefined;
  }

  async until(_what: string, f: () => boolean) {
    while (!f()) {
      await new Promise<void>((resolve) => {
        this.waiters.push(resolve);
        setTimeout(resolve, 20);
      });
    }
  }

  private tell() {
    for (const w of this.waiters.splice(0)) w();
  }

  async close() {
    for (const ws of this.sockets) ws.terminate();
    this.wss.close();
    this.server.closeAllConnections();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }

  private async take(req: IncomingMessage): Promise<Json> {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const raw = Buffer.concat(chunks);
    const url = new URL(req.url ?? "/", "http://x");
    const contentType = String(req.headers["content-type"] ?? "");
    let body: Json = null;
    if (contentType.startsWith("application/json")) body = JSON.parse(raw.toString("utf8") || "null");
    else if (contentType.startsWith("application/x-www-form-urlencoded")) body = Object.fromEntries(new URLSearchParams(raw.toString("utf8")));
    else if (contentType.startsWith("multipart/form-data")) {
      const form = await new Response(raw, { headers: { "content-type": contentType } }).formData();
      body = {};
      for (const [k, v] of form) body[k] = typeof v === "string" ? v : `<file ${(v as File).name}>`;
    }
    const seen: Seen = { method: req.method ?? "GET", path: url.pathname, auth: String(req.headers.authorization ?? "").replace(/^Bearer /, ""), query: Object.fromEntries(url.searchParams), body };
    this.seen.push(seen);
    this.tell();
    const answer = this.answers.get(`${seen.method} ${seen.path}`);
    if (answer) return answer(seen);
    if (seen.path === "/open-apis/auth/v3/tenant_access_token/internal") return { code: 0, tenant_access_token: `t-${body?.app_id}`, expire: 7200 };
    if (seen.path === "/callback/ws/endpoint") return { code: 0, data: { URL: `${this.base.replace(/^http/, "ws")}/ws?device_id=d1&service_id=7`, ClientConfig: { PingInterval: 120 } } };
    if (seen.path === "/open-apis/bot/v3/info") return { code: 0, bot: this.bot };
    if (seen.path === "/open-apis/tenant/v2/tenant/query") return { code: 0, data: { tenant: { name: "Acme", tenant_key: "tk1" } } };
    if (seen.path === "/open-apis/im/v1/messages" && seen.method === "POST") return { code: 0, data: { message_id: `om_bot${this.n++}` } };
    if (/^\/open-apis\/im\/v1\/messages\/[^/]+\/reply$/.test(seen.path)) return { code: 0, data: { message_id: `om_bot${this.n++}` } };
    if (seen.path === "/open-apis/cardkit/v1/cards" && seen.method === "POST") return { code: 0, data: { card_id: `card${this.n++}` } };
    if (seen.path === "/open-apis/im/v1/images") return { code: 0, data: { image_key: "img_1" } };
    if (seen.path === "/open-apis/im/v1/files") return { code: 0, data: { file_key: "file_1" } };
    if (/^\/open-apis\/im\/v1\/chats\/[^/]+$/.test(seen.path)) return { code: 0, data: { name: "项目群", chat_mode: "group", group_message_type: "chat" } };
    if (/^\/open-apis\/contact\/v3\/users\//.test(seen.path)) return { code: 0, data: { user: { name: "Ada", email: "ada@example.test" } } };
    return { code: 0, data: {} };
  }
}
