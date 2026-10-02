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
