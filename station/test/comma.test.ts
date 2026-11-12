// The Comma connect: the station takes part in Comma's Tasks as a Comma station does, against a stand-in for Comma's
// connector socket on a local port (the frames of SalixWeb.ConnectorSocket: `connected`, heartbeats, requests and their
// answers both ways), through a hub with scripted runtimes. Nothing reaches the real Comma.
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { WebSocketServer, type WebSocket } from "ws";
import { commaLine } from "../src/comma/index.ts";
import { CommaSurface, connectUrl, questionOf } from "../src/comma/surface.ts";
import { CommaTasks, threadTsOf } from "../src/comma/tasks.ts";
import { Rig, settle } from "./hub-fakes.ts";

type Json = any;

/// Comma's connector socket: who dialed with what, the frames that came up, the requests the station asked (answered
/// by `answer`), and requests sent down with their answers.
class FakeComma {
  readonly server: Server;
  readonly wss = new WebSocketServer({ noServer: true });
  base = "";
  socket: WebSocket | null = null;
  auth = "";
  frames: Json[] = [];
  asked: Json[] = [];
  answer: (request: Json) => Json = () => ({});
  private replies = new Map<string, Json>();
  private waiters: (() => void)[] = [];
  private n = 0;

  constructor() {
    this.server = createServer((_req, res) => res.writeHead(404).end());
    this.server.on("upgrade", (req, socket, head) => {
      this.auth = String(req.headers.authorization ?? "");
      this.wss.handleUpgrade(req, socket, head, (ws) => {
        this.socket = ws;
        ws.on("message", (data) => {
          const f = JSON.parse(String(data));
          this.frames.push(f);
          if (f.type === "request") {
            this.asked.push(f);
            ws.send(JSON.stringify({ id: f.id, type: "response", result: this.answer(f) }));
          } else if (f.type === "response" || f.type === "error") this.replies.set(f.id, f);
          this.tell();
        });
        ws.send(JSON.stringify({ type: "connected", connector_run_id: "run_1", device_id: "dev_1" }));
        this.tell();
      });
    });
  }

  static async start(): Promise<FakeComma> {
    const fake = new FakeComma();
    await new Promise<void>((resolve) => fake.server.listen(0, "127.0.0.1", resolve));
    fake.base = `http://127.0.0.1:${(fake.server.address() as AddressInfo).port}`;
    return fake;
  }

  /// Asks the station, as Salix does over the socket: its answer frame.
  async request(method: string, params: Json): Promise<Json> {
    const id = `req-${++this.n}`;
    this.socket!.send(JSON.stringify({ id, type: "request", method, params }));
    await this.until(method, () => this.replies.has(id));
    return this.replies.get(id);
  }

  posts(): Json[] {
    return this.asked.filter((f) => f.method === "task.post").map((f) => f.params);
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
    this.socket?.terminate();
    this.wss.close();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }
}

test("the line Comma shows reads as its server and token; anything else does not", () => {
  assert.deepEqual(commaLine("  comma https://api.comma.surf/ salix_conn_abcdef123  "), { server: "https://api.comma.surf", token: "salix_conn_abcdef123" });
  assert.deepEqual(commaLine("comma wss://salix.comma.surf salix_conn_abcdef123"), { server: "https://salix.comma.surf", token: "salix_conn_abcdef123" });
  assert.deepEqual(commaLine("comma ws://localhost:4000 salix_conn_abcdef123"), { server: "http://localhost:4000", token: "salix_conn_abcdef123" });
  assert.equal(commaLine("tailcat 100.1.2.3 4750"), null);
  assert.equal(commaLine("comma ftp://x salix_conn_abcdef123"), null);
  assert.equal(commaLine("comma https://api.comma.surf short"), null);
  assert.equal(connectUrl("https://api.comma.surf", "mac").replace(/&os=.*/, ""), "wss://api.comma.surf/v1/connect?name=mac");
  assert.equal(new URL(connectUrl("https://api.comma.surf", "mac", "ws_1")).searchParams.get("stillfail_workspace"), "ws_1");
});

test("an options card is Comma's question card, the recommended one marked; a text card or one option is words alone", () => {
  const q = questionOf({ type: "options", options: [{ label: "先不合", detail: "留着" }, { label: "合并", recommended: true }] }, "合不合？");
  assert.deepEqual(q, {
    type: "question", prompt: "合不合？", multi_select: false, allow_other: true,
    choices: [{ id: "o1", label: "先不合", description: "留着" }, { id: "o2", label: "合并", recommended: true }],
  });
  assert.equal(questionOf({ type: "options", options: [{ label: "好" }] }, "x"), null);
  assert.equal(questionOf({ type: "text" }, "x"), null);
});

test("a Comma Task is a thread its agent works in: invited, its Messages heard from the people who said them, what the agent says and asks written into it, where the turn stands, the Task left", async () => {
  const fake = await FakeComma.start();
  const rig = new Rig();
  const dir = mkdtempSync(join(tmpdir(), "comma-"));
  const tasks = new CommaTasks(join(dir, "tasks.json"));
  let seq = 10;
  fake.answer = (f) => (f.method === "task.post" ? { seq: ++seq } : {});
  const surface = new CommaSurface({
    connect: "cm", server: fake.base, token: "salix_conn_test123", name: "mac", tasks, store: rig.store,
    models: () => rig.hub.modelsFor("cm"),
  });
  try {
    rig.edit((raw) => raw.connects.push({ id: "cm", kind: "comma", comma: { server: fake.base, token: "salix_conn_test123" }, bind: { runtime: "claude" } }));
    await rig.hub.shutdown();
    rig.hub = rig.newHub({ chats: (id) => (id === "cm" ? surface : undefined) });
    await surface.start((e) => rig.hub.receive("cm", e));
    // Connected: it says it takes Tasks on its models, and that it is here.
    await fake.until("hello", () => fake.asked.some((f) => f.method === "task.hello"));
    assert.equal(fake.auth, "Bearer salix_conn_test123");
    const meta = fake.frames.find((f) => f.type === "metadata");
    assert.equal(meta.capabilities.tasks, 2);
    assert.ok("claude" in meta.capabilities.task_models);
    // Comma's heartbeat is answered.
    fake.socket!.send(JSON.stringify({ type: "heartbeat" }));
    await fake.until("heartbeat", () => fake.frames.some((f) => f.type === "heartbeat"));

    const invited = await fake.request("task.invite", { task: "cnv_1", start: { requester: "u_ada", runtime: "claude", model: "opus" } });
    const ts = threadTsOf("cnv_1");
    const key = `cm:TASK:${ts}`;
    assert.deepEqual(invited.result, { session: key, thread: `TASK/${ts}` });
    assert.match((await fake.request("task.invite", { task: "cnv_2", start: { requester: "u_ada", runtime: "dsh" } })).error, /dsh/);
    assert.deepEqual((await fake.request("task.status", { task: "cnv_1" })).result.state, "idle");

    const put = await fake.request("task.put", {
      task: "cnv_1", through: 2,
      messages: [
        { seq: 1, author: { kind: "agent", id: "router", name: "Router" }, text: "请看下登录页" },
        { seq: 2, author: { kind: "person", id: "u_ada", name: "Ada", email: "ada@example.test", picture: "https://example.test/ada.png" }, text: "顺便截个图" },
      ],
    });
    assert.deepEqual(put.result, { through: 2 });
    await settle();
    assert.ok(rig.store.getSession(key));
    // (a model the station's profiles do not run: the runtime's default)
    assert.deepEqual([rig.session(key).runtime, rig.session(key).model], ["claude", null]);
    const thread = rig.store.threadAt("comma:cm", "TASK", ts)!;
    assert.deepEqual(rig.said(thread.id).map((m) => [m.author, m.text]), [["agent:router", "请看下登录页"], ["u_ada", "顺便截个图"]]);
    assert.equal(surface.knownPerson("u_ada")?.name, "Ada");

    // What the agent says, and a card, go into the Task; the card as Comma's question.
    rig.claude.last().reads();
    const answer = await rig.call(key, "chat_post", { to: `TASK/${ts}`, text: "用哪个分支？", card: { type: "options", options: [{ label: "main" }, { label: "dev", recommended: true }] }, kind: "need_human", need: "选分支" });
    assert.ok(answer.startsWith(`Posted to TASK/${ts}`), answer);
    const post = fake.posts().at(-1);
    assert.deepEqual([post.task, post.session, post.text, post.question.choices.map((c: Json) => c.label)], ["cnv_1", key, "用哪个分支？", ["main", "dev"]]);
    assert.equal(rig.store.messageAt(thread.id, "11.000000")?.text, "用哪个分支？");

    // Where its turn stands goes into the Task with it.
    surface.standsAt({ channel: "TASK", threadTs: ts }, { kind: "need", words: "选分支" });
    await fake.until("need_help", () => fake.posts().some((p) => p.declared === "need_help"));
    assert.equal(fake.posts().find((p) => p.declared === "need_help").text, "选分支");

    // Given again with what it said itself and what it answered: only what is new is heard.
    await fake.request("task.put", {
      task: "cnv_1", through: 13, answered: 12,
      messages: [
        { seq: 11, author: { kind: "agent", id: "w", session: key }, text: "用哪个分支？" },
        { seq: 13, author: { kind: "person", id: "u_ada", name: "Ada" }, text: "dev" },
      ],
    });
    await settle();
    assert.deepEqual(rig.said(thread.id).map((m) => m.text).filter((t) => t === "dev"), ["dev"]);

    // Left: it runs elsewhere now; its session leaves the thread and Comma hears it is gone.
    await fake.request("task.leave", { task: "cnv_1" });
    assert.equal((await fake.request("task.status", { task: "cnv_1" })).result.state, "gone");
    assert.deepEqual((await fake.request("task.put", { task: "cnv_1", messages: [] })).result, { gone: true });
    assert.deepEqual((await fake.request("task.put", { task: "cnv_9", messages: [] })).result, { unknown: true, gone: true });
    assert.match((await fake.request("exec", { cmd: "ls" })).error, /not something a still\.fail station does/);
  } finally {
    await surface.stop();
    await rig.close();
    await fake.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
