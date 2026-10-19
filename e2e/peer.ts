// alice's other device in the local still.fail (scripts/e2e-local.sh): ember's TS core in Node (client/core-ts
// hosts/node.ts, on the station's own mesh addon), signed in with the dev cloud's mock account, asked as a UI asks.
// It makes the chat the app's flows run in and says things in it, so the app sees a chat made and words come from
// elsewhere; and it reads the chat back, as a check from outside the app.
//
//   node e2e/peer.ts setup                 the workspace, its station online, a chat made with its first words;
//                                          prints CHAT <station> <session> <thread> (kept in $E2E_PEER_DATA/chat.json)
//   node e2e/peer.ts create TITLE-WORDS    another chat, its first message TITLE-WORDS (Home's new row)
//   node e2e/peer.ts send TEXT             TEXT said in the chat by this device
//   node e2e/peer.ts read                  the chat as this device's core shows it (JSON lines: who, text, files)
//
// E2E_EMBER (the ember checkout), E2E_ORIGIN (the dev cloud), E2E_PEER_DATA (this core's own data directory).
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const ember = process.env.E2E_EMBER!;
const origin = process.env.E2E_ORIGIN!;
const dir = process.env.E2E_PEER_DATA!;
mkdirSync(dir, { recursive: true });
const { start } = await import(join(ember, "client/core-ts/src/hosts/node.ts"));
const { apply } = await import(join(ember, "client/core-ts/src/delta.ts"));

type J = any;
const pending = new Map<number, (m: J) => void>();
const topics = new Map<number, { value: J; error: J; changed: () => void }>();
let next = 1;
const core = start(join(dir, "core"), origin, (_client: number, json: string) => {
  const m = JSON.parse(json);
  if (m.fatal) {
    console.error("core fatal:", m.fatal);
    process.exit(3);
  }
  const t = topics.get(m.id);
  if (t && "value" in m) t.value = m.value;
  else if (t && "delta" in m) t.value = apply(t.value, m.delta);
  else if (t && "error" in m) t.error = m.error;
  else if (pending.has(m.id)) {
    pending.get(m.id)!(m);
    pending.delete(m.id);
    return;
  }
  t?.changed();
});
const client = core.connect();

function call(name: string, params?: J): Promise<J> {
  const id = next++;
  return new Promise((resolve, reject) => {
    pending.set(id, (m) => ("error" in m ? reject(new Error(`${name}: ${JSON.stringify(m.error)}`)) : resolve(m.ok)));
    core.receive(client, JSON.stringify(params === undefined ? { id, call: name } : { id, call: name, params }));
  });
}

/// The topic's value once `ok` says it is what is waited for (or the time is up: what it was, in the error).
function until<T>(topic: J, ok: (v: J) => T | undefined | null | false, ms = 60_000): Promise<T> {
  const id = next++;
  return new Promise((resolve, reject) => {
    const entry = { value: undefined as J, error: undefined as J, changed: () => {} };
    const timer = setTimeout(() => {
      core.receive(client, JSON.stringify({ id, unsubscribe: true }));
      reject(new Error(`timed out on ${JSON.stringify(topic)}: ${JSON.stringify(entry.value ?? entry.error)?.slice(0, 2000)}`));
    }, ms);
    entry.changed = () => {
      if (entry.value === undefined) return;
      const got = ok(entry.value);
      if (got) {
        clearTimeout(timer);
        topics.delete(id);
        core.receive(client, JSON.stringify({ id, unsubscribe: true }));
        resolve(got);
      }
    };
    topics.set(id, entry);
    core.receive(client, JSON.stringify({ id, subscribe: topic }));
  });
}

async function signIn(): Promise<{ workspace: string; station: string }> {
  const accounts = await until({ topic: "accounts" }, (v) => v);
  if (!Array.isArray(accounts) || accounts.length === 0) {
    const account = await (await fetch(`${origin}/__dev/account?user=alice`)).json();
    await call("migrate", { accounts: [account] });
  }
  const workspace = await until({ topic: "workspaces" }, (v) => {
    for (const a of v ?? []) for (const w of a.workspaces ?? []) if (w.name === "Dev") return w.id as string;
    return undefined;
  });
  const station = await until({ topic: "workspace", workspace }, (v) => {
    const st = (v?.stations ?? [])[0];
    return st ? `${workspace}/${st.id}` : undefined;
  }, 120_000);
  console.error(`peer: signed in, workspace ${workspace}, station ${station}`);
  return { workspace, station };
}

/// A chat made on `station` with `text` its first words: its row once the station has it.
async function make(workspace: string, station: string, text: string): Promise<{ session: string; thread: number; title: string }> {
  const { key } = await call("chat.create", { station, runtime: "claude" });
  console.error(`peer: chat.create on ${station}: ${key}`);
  console.error(`peer: chat.send: ${JSON.stringify(await call("chat.send", { station, session: key, text }))}`);
  return until({ topic: "chats", scope: workspace, mine: false }, (v) => {
    for (const d of v?.days ?? []) {
      for (const it of d.items ?? []) {
        if (it.station === station && typeof it.thread === "number" && it.session && !String(it.session).startsWith("pending") &&
          (it.last?.preview ?? "").includes(text.split(" post:")[0].slice(0, 6))) {
          return { session: it.session, thread: it.thread, title: it.title };
        }
      }
    }
    return undefined;
  }, 120_000);
}

const chatFile = join(dir, "chat.json");
const [cmd, ...rest] = process.argv.slice(2);
try {
  const { workspace, station } = await signIn();
  if (cmd === "setup") {
    const made = await make(workspace, station, "端到端测试的对话 post:你好，我是测试用的 agent");
    writeFileSync(chatFile, JSON.stringify({ workspace, station, ...made }));
    console.log(`CHAT ${station} ${made.session} ${made.thread} ${made.title}`);
  } else if (cmd === "create") {
    const made = await make(workspace, station, rest.join(" "));
    console.log(`CHAT ${station} ${made.session} ${made.thread} ${made.title}`);
  } else if (cmd === "send") {
    const chat = JSON.parse(readFileSync(chatFile, "utf8"));
    console.log(JSON.stringify(await call("chat.send", { station: chat.station, thread: chat.thread, text: rest.join(" ") })));
  } else if (cmd === "read") {
    const chat = JSON.parse(readFileSync(chatFile, "utf8"));
    const v = await until({ topic: "chat", station: chat.station, thread: chat.thread }, (v) => v);
    console.log(JSON.stringify(v, null, 1));
  } else {
    throw new Error(`unknown command ${cmd}`);
  }
  await core.close();
  process.exit(0);
} catch (e) {
  console.error(String(e));
  process.exit(1);
}
