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
//                                          device showing its code, PAIRING <code>\t<person>\t<its label> (then until
//                                          that device is done with it: its prompt gone)
//   node e2e/peer.ts lock-off              safe mode turned off again: LOCK OFF
//   node e2e/peer.ts added [WORDS|!WORDS]  those added who have not signed in yet: ADDED <email> <role>; with WORDS
//                                          once a line has them (!: none has)
//   node e2e/peer.ts connect-put ID        a connect made on the test station (connect.put), with no Slack tokens
//   node e2e/peer.ts connects              the test station's connects: CONNECT <id> enabled=<on> mode=<mode>
//   node e2e/peer.ts vault-items [WORDS|!WORDS]  the workspace's library: ITEM <name> <kind> listed=<listed>; WORDS as added
//   node e2e/peer.ts stations [WORDS|!WORDS]  the workspace's stations as the cloud has them: STATION <id> <name>
//                                          emoji=<emoji> icon=<icon>; with WORDS once a line has them (!: none has)
//
// E2E_EMBER (the ember checkout), E2E_ORIGIN (the dev cloud), E2E_PEER_DATA (this core's own data directory).
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";

const ember = process.env.E2E_EMBER!;
const origin = process.env.E2E_ORIGIN!;
const dir = process.env.E2E_PEER_DATA!;
mkdirSync(dir, { recursive: true });
// (as URLs: a Windows path is no module specifier)
const { start } = await import(pathToFileURL(join(ember, "client/core-ts/src/hosts/node.ts")).href);
const { apply } = await import(pathToFileURL(join(ember, "client/core-ts/src/delta.ts")).href);

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
// whether lines `l` are what WORDS want: one has WORDS (`!WORDS`: none has); no WORDS, any lines are
function wanted(want: string, l: string[]): boolean {
  if (!want) return true;
  const has = l.some((x) => x.includes(want.replace(/^!/, "")));
  return want.startsWith("!") ? !has : has;
}

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
    // (online until a new device shows this one's code, then until it is done with it, confirmed or turned down: its
    // prompt gone from the lockPrompts topic; then gone, so that another of these commands may take this device's data)
    const most = Number(rest[0] ?? 60) * 1000;
    const p = await until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], most);
    console.log(`PAIRING ${p.code}\t${p.name || p.email}\t${p.label}`);
    await until({ topic: "lockPrompts" }, (v) => !(v?.pairing ?? []).some((q: J) => q.code === p.code) || undefined, most);
  } else if (cmd === "lock-off") {
    await call("lock.disable", { workspace });
    console.log("LOCK OFF");
  } else if (cmd === "stations") {
    // the workspace's stations as still.fail cloud has them, a line each: their id, name and mark; with WORDS, once a
    // line has them (or, `!WORDS`, once none has)
    const want = rest.join(" ");
    const lines = (v: J) => (v?.stations ?? []).map((s: J) => `STATION ${s.id} ${s.name} emoji=${s.emoji ?? ""} icon=${s.icon ?? ""}`);
    let got: string[] = [];
    try {
      got = await until({ topic: "workspace", workspace }, (v) => {
        const l = lines(v);
        if (!v?.stations) return undefined;
        if (!want) return l;
        const has = l.some((x: string) => x.includes(want.replace(/^!/, "")));
        return (want.startsWith("!") ? !has : has) ? l : undefined;
      }, want ? 60_000 : 20_000);
    } catch (e) {
      console.error(String(e));
    }
    for (const l of got) console.log(l);
  } else if (cmd === "connect-put") {
    // a connect made (or changed) on the test station as the app's "…" would (connect.put), no Slack tokens: its page
    // says it is not in Slack yet
    const [id] = rest;
    console.log(JSON.stringify(await call("connect.put", { station, id, input: { mode: "multi-session", requireMention: true, enabled: true, bind: { runtime: "claude", model: "claude-sonnet-5-5" } } })));
    console.log(`CONNECT ${id} made`);
  } else if (cmd === "connects") {
    // the test station's connects as its overview has them: CONNECT <id> enabled=<on> mode=<mode>
    const v = await until({ topic: "stations", scope: workspace }, (v) => {
      const s = (v ?? []).find((x: J) => x.station === station);
      return s?.overview ? s : undefined;
    });
    for (const c of v.overview.connects ?? []) console.log(`CONNECT ${c.id} enabled=${c.enabled} mode=${c.mode}`);
  } else if (cmd === "vault-items") {
    // the workspace's library as this device reads it: ITEM <name> <kind> listed=<listed>, a line each; with WORDS,
    // once a line has them (`!WORDS`: once none has), this device's copy caught up
    // (each vault's items as the topic says them, once they are as WORDS want: `!WORDS` in every vault, WORDS in one)
    const want = rest.join(" ");
    const v = await until({ topic: "vaults", workspace }, (v) => v);
    const lines = (x: J) => (x.items as J[]).map((it: J) => `ITEM ${it.name ?? "?"} ${it.kind ?? "?"} listed=${it.listed}`);
    const each = (v.vaults ?? []).map((vault: J) => until({ topic: "vaultItems", workspace, vault: vault.id },
      (x) => x?.items && wanted(want, lines(x)) && lines(x)));
    const got: string[][] = want && !want.startsWith("!") ? [await Promise.any(each)] : await Promise.all(each);
    for (const l of got.flat()) console.log(l);
  } else if (cmd === "added") {
    // those added to the workspace who have not signed in yet: ADDED <email> <role>; with WORDS as vault-items
    // (the workspace's topic, once its added are as WORDS want)
    const want = rest.join(" ");
    const lines = (v: J) => (v.added ?? []).map((a: J) => `ADDED ${a.email} ${a.role}`);
    const v = await until({ topic: "workspace", workspace }, (v) => v?.members && wanted(want, lines(v)) ? v : undefined);
    for (const l of lines(v)) console.log(l);
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
