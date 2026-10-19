// alice's other device in the local still.fail (scripts/e2e-local.sh): ember's TS core in Node (client/core-ts
// hosts/node.ts, on the station's own mesh addon), signed in with the dev cloud's mock account, asked as a UI asks.
// It makes the chat the app's flows run in and says things in it, so the app sees a chat made and words come from
// elsewhere; and it reads the chat back, as a check from outside the app.
//
//   node e2e/peer.ts setup                 the workspace, its station online, a chat made with its first words;
//                                          prints CHAT <station> <session> <thread> (kept in $E2E_PEER_DATA/chat.json)
//   node e2e/peer.ts create TITLE-WORDS    another chat, its first message TITLE-WORDS (Home's new row)
//   node e2e/peer.ts send TEXT             TEXT said in the chat by this device
//   node e2e/peer.ts sendfiles TEXT -- F…  TEXT said with files (from $E2E_FILES), each put up first in 4 MB parts
//   node e2e/peer.ts createfiles TEXT -- F…  another chat, its first message TEXT with those files
//   node e2e/peer.ts read                  the chat as this device's core shows it (JSON lines: who, text, files)
//   node e2e/peer.ts chats [WORDS]         the workspace's chats as Home lists them (JSON: title, session, last), once a
//                                          row has WORDS
//   node e2e/peer.ts newchat               the workspace's new-chat page as the core has it (the `newChat` topic)
//   node e2e/peer.ts archive TITLE-WORDS   another chat made, then archived by hand (chat.archive): ARCHIVED <session>
//   node e2e/peer.ts station-name [NAME]   the test station's name as still.fail cloud says it (the workspace topic):
//                                          STATION <name>; with NAME, once it is that (or the time is up)
//   node e2e/peer.ts members               the workspace's people as the cloud has them: MEMBER <email> <role>, a line each
//   node e2e/peer.ts lock-on               safe mode turned on by this device (the owner's, a signer), every other device
//                                          left out (the app's among them): LOCK ON <entry>
//   node e2e/peer.ts lock-await [SECONDS]  this device online for that long (60) to be met face to face: the first new
//                                          device showing its code, PAIRING <code>\t<person>\t<its label> (then 12 s more)
//   node e2e/peer.ts lock-off              safe mode turned off again: LOCK OFF
//
// E2E_EMBER (the ember checkout), E2E_ORIGIN (the dev cloud), E2E_PEER_DATA (this core's own data directory).
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

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

/// A call with bytes beside it (a file's part going up).
function callBytes(name: string, params: J, bytes: Uint8Array): Promise<J> {
  const id = next++;
  return new Promise((resolve, reject) => {
    pending.set(id, (m) => ("error" in m ? reject(new Error(`${name}: ${JSON.stringify(m.error)}`)) : resolve(m.ok)));
    core.receiveRaw(client, { id, call: name, params, bytes });
  });
}

/// A file put up to the station (`station.upload.part`, 4 MB a part, as the app's composer does): the file as the
/// station keeps it, for a message's attachments.
async function upload(station: string, path: string): Promise<J> {
  const bytes = new Uint8Array(readFileSync(path));
  const name = path.split("/").pop()!;
  const id = randomUUID().replace(/-/g, "");
  let at = 0;
  for (;;) {
    const part = bytes.subarray(at, Math.min(bytes.length, at + 4 * 1024 * 1024));
    const got = await callBytes("station.upload.part", { station, id, name, size: bytes.length, offset: at }, part);
    if (got?.file) return got.file;
    const have = typeof got?.have === "number" ? got.have : at + part.length;
    if (have <= at) throw new Error(`upload of ${name} stood still at ${at}`);
    at = have;
  }
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
async function make(workspace: string, station: string, text: string, attachments: J[] = []): Promise<{ session: string; thread: number; title: string }> {
  const { key } = await call("chat.create", { station, runtime: "claude" });
  console.error(`peer: chat.create on ${station}: ${key}`);
  const send = attachments.length > 0 ? { station, session: key, text, attachments } : { station, session: key, text };
  console.error(`peer: chat.send: ${JSON.stringify(await call("chat.send", send))}`);
  const row = await until<{ session: string; thread: number; title: string }>({ topic: "chats", scope: workspace, mine: false }, (v) => {
    for (const d of v?.days ?? []) {
      for (const it of d.items ?? []) {
        if (it.station === station && typeof it.thread === "number" && it.session && !String(it.session).startsWith("pending") &&
          // its own words, whole where the row has them (a chat made before with the same lead may still be listed)
          [it.last?.preview ?? "", it.title ?? ""].some((w: string) => w.includes(text.split(" post:")[0]))) {
          return { session: it.session, thread: it.thread, title: it.title };
        }
      }
    }
    return undefined;
  }, 120_000);
  // not gone before the station has the words: the row shows them from this core's outbox already, and a process that
  // ends then leaves them there (the station's thread stays empty)
  await until({ topic: "chat", station, thread: row.thread }, (v) => (v?.messages ?? []).some((m: J) => m.text === text) || undefined, 120_000);
  return row;
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
  } else if (cmd === "createfiles") {
    const cut = rest.indexOf("--");
    const attachments = [];
    for (const f of rest.slice(cut + 1)) {
      const file = await upload(station, join(process.env.E2E_FILES!, f));
      console.error(`peer: put up ${f}: ${JSON.stringify(file)}`);
      attachments.push(file);
    }
    const made = await make(workspace, station, rest.slice(0, cut).join(" "), attachments);
    console.log(`CHAT ${station} ${made.session} ${made.thread} ${made.title}`);
  } else if (cmd === "sendfiles") {
    const chat = JSON.parse(readFileSync(chatFile, "utf8"));
    const cut = rest.indexOf("--");
    const text = rest.slice(0, cut).join(" ");
    const attachments = [];
    for (const f of rest.slice(cut + 1)) {
      const file = await upload(chat.station, join(process.env.E2E_FILES!, f));
      console.error(`peer: put up ${f}: ${JSON.stringify(file)}`);
      attachments.push(file);
    }
    console.log(JSON.stringify(await call("chat.send", { station: chat.station, thread: chat.thread, text, attachments })));
  } else if (cmd === "read") {
    const chat = JSON.parse(readFileSync(chatFile, "utf8"));
    const v = await until({ topic: "chat", station: chat.station, thread: chat.thread }, (v) => v);
    console.log(JSON.stringify(v, null, 1));
  } else if (cmd === "chats") {
    // with words: once a row has them (its title or its last words)
    const words = rest.join(" ");
    const rowsOf = (v: J) => (v?.days ?? []).flatMap((d: J) => d.items ?? []).map((it: J) => ({ title: it.title, session: it.session, station: it.station, last: it.last?.preview }));
    const rows = await until({ topic: "chats", scope: workspace, mine: false }, (v) => {
      const r = rowsOf(v);
      return v?.days && (!words || r.some((x: J) => `${x.title} ${x.last}`.includes(words))) && r;
    });
    console.log(JSON.stringify(rows, null, 1));
  } else if (cmd === "newchat") {
    const v = await until({ topic: "newChat", scope: workspace }, (v) => v?.stations && v);
    console.log(JSON.stringify(v, null, 1));
  } else if (cmd === "archive") {
    const made = await make(workspace, station, rest.join(" "));
    await call("chat.archive", { station, session: made.session, thread: made.thread, archived: true });
    // in the archive as the core puts it together (the station has it)
    await until({ topic: "archive", scope: workspace, limit: 60 }, (v) =>
      (v?.days ?? []).some((d: J) => (d.items ?? []).some((it: J) => it.session === made.session)), 120_000);
    console.log(`ARCHIVED ${made.session} ${made.thread} ${made.title}`);
  } else if (cmd === "station-name") {
    const id = station.split("/")[1];
    const want = rest.join(" ");
    let name = "";
    try {
      name = await until({ topic: "workspace", workspace }, (v) => {
        const st = (v?.stations ?? []).find((s: J) => s.id === id);
        return st && (!want || st.name === want) ? (st.name as string) : undefined;
      }, want ? 60_000 : 20_000);
    } catch (e) {
      console.error(String(e));
    }
    console.log(`STATION ${name}`);
  } else if (cmd === "lock-on") {
    const draft = await until({ topic: "lockDraft", workspace }, (v) => (v?.ready ? v : undefined), 120_000);
    for (const d of draft.devices ?? []) if (!d.current) await call("lock.toggle", { workspace, id: d.id });
    const opened = await call("lock.open", { workspace });
    console.log(`LOCK ON ${opened?.head?.seq ?? "?"}`);
  } else if (cmd === "lock-await") {
    // (online until the code has been met and a while after it, for the new device's tries: then gone, so that
    // another of these commands may take this device's data)
    let end = Date.now() + Number(rest[0] ?? 60) * 1000;
    let said = false;
    while (Date.now() < end) {
      const p = (await call("lockPrompt.state", {}))?.pairing?.[0];
      if (p && !said) {
        console.log(`PAIRING ${p.code}\t${p.name || p.email}\t${p.label}`);
        said = true;
        end = Math.min(end, Date.now() + 12_000);
      }
      await new Promise((r) => setTimeout(r, 500));
    }
  } else if (cmd === "lock-off") {
    await call("lock.disable", { workspace });
    console.log("LOCK OFF");
  } else if (cmd === "members") {
    const v = await until({ topic: "workspace", workspace }, (v) => (v?.members ?? []).length > 0 ? v : undefined);
    for (const m of v.members) console.log(`MEMBER ${m.email} ${m.role}`);
  } else {
    throw new Error(`unknown command ${cmd}`);
  }
  await core.close();
  process.exit(0);
} catch (e) {
  console.error(String(e));
  process.exit(1);
}
