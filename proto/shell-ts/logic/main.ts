// Prototype logic: what the station decides lives here; the Rust shell (../shell) only holds the connections and
// SQLite and hands them over as messages on stdin/stdout, one JSON object a line. Runs on Node 22.18+ as is (types
// stripped), so changing it needs no build at all.

import { createInterface } from "node:readline";

const VERSION = "v1";
const generation = Number(process.env.SHELL_GENERATION);

type Message = { t: string; [key: string]: any };

function send(message: Message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

// ---- primitives the shell offers ----

let nextSql = 0;
const answers = new Map<number, (message: Message) => void>();

function sql(text: string, params: unknown[] = []): Promise<Message> {
  const r = nextSql++;
  send({ t: "sql", r, sql: text, params });
  return new Promise((resolve, reject) => answers.set(r, (m) => (m.error ? reject(new Error(m.error)) : resolve(m))));
}

function reply(s: number, value: unknown) {
  send({ t: "write", s, b: Buffer.from(JSON.stringify(value)).toString("base64") });
  send({ t: "finish", s });
}

// ---- the logic ----

let inFlight = 0;
let draining = false;

async function handle(s: number, body: string) {
  inFlight++;
  try {
    const request = JSON.parse(body);
    if (request.op === "ping") {
      reply(s, { ok: true, i: request.i });
      return;
    }
    if (request.op === "chats") {
      reply(s, { ok: true, chats: chats(request.n ?? 2000) });
      return;
    }
    // Some work, so that requests are in flight when a restart comes.
    await new Promise((resolve) => setTimeout(resolve, 30));
    await sql("INSERT INTO hits (i, generation, version) VALUES (?, ?, ?)", [request.i, generation, VERSION]);
    const { rows } = await sql("SELECT count(*) FROM hits");
    reply(s, { ok: true, i: request.i, total: rows[0][0], generation, version: VERSION, pid: process.pid });
  } catch (error) {
    reply(s, { error: String(error) });
  } finally {
    inFlight--;
    if (draining && inFlight === 0) stop();
  }
}

// A station's chat list, made up but shaped like the real one (for the client prototype, proto/client-shell).
function chats(n: number) {
  const words = ["部署", "安卓", "登录", "中继", "截图", "合并", "通知", "预览", "设置", "迁移", "Slack", "station", "core", "web"];
  const states = ["running", "waiting", "need_human", "all_done", "idle"];
  let seed = 7;
  const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  const pick = <T,>(list: T[]) => list[Math.floor(random() * list.length)];
  const now = Date.now();
  return Array.from({ length: n }, (_, i) => ({
    id: `c-${i.toString(16).padStart(8, "0")}`,
    title: `${pick(words)}${pick(words)}：${pick(words)}的问题 ${i}`,
    station: `station-${i % 7}`,
    updated: now - Math.floor(random() * 30 * 86400000),
    unread: random() < 0.2 ? Math.floor(random() * 9) + 1 : 0,
    pinned: random() < 0.03,
    state: pick(states),
    last: Array.from({ length: 12 }, () => pick(words)).join(" "),
    people: Array.from({ length: 1 + Math.floor(random() * 3) }, () => `user${Math.floor(random() * 20)}@example.com`),
  }));
}

// Exits once stdout is flushed: nothing left to listen to.
function stop() {
  lines.close();
  process.stdin.destroy();
}

const bodies = new Map<number, Buffer[]>();
const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  const message: Message = JSON.parse(line);
  switch (message.t) {
    case "stream":
      bodies.set(message.s, []);
      break;
    case "data":
      bodies.get(message.s)?.push(Buffer.from(message.b, "base64"));
      break;
    case "end": {
      const parts = bodies.get(message.s);
      bodies.delete(message.s);
      if (parts) void handle(message.s, Buffer.concat(parts).toString());
      break;
    }
    case "sql":
      answers.get(message.r)?.(message);
      answers.delete(message.r);
      break;
    case "drain":
      draining = true;
      if (inFlight === 0) stop();
      break;
  }
});

await sql("CREATE TABLE IF NOT EXISTS hits (i INTEGER, generation INTEGER, version TEXT)");
send({ t: "ready" });
