// A station that only runs tasks (a rig) end to end against the local still.fail (scripts/e2e-local.sh rigs, after
// up; rigs-all, the side run's): alice's device A, still.fail's TS core in Node (e2e/device.ts), and a second machine
// beside the test station, a real process of the station's release. Four times: added as one that only runs tasks,
// and added as a whole station then made one in the app, each in the workspace as it stands and then in security
// mode (A turns it on):
//   1 A opens alice's own lock. Added so: the command the app shows, with her lock's hash to pin (and the
//     workspace's, in security mode); the machine enrolls with it and comes up as a rig, listed as hers, no station;
//     in security mode a station refuses it until A gives the code the machine printed (`rig.vouch`). Made so: a
//     whole station enrolled (taken into the lock by its code, in security mode), then `rig.setMode tasks`: its
//     process ends what it ran as a station and starts as a rig, hers;
//   2 a chat's agent runs a task there with no grant: refused;
//   3 the agent asks (station_use): the request shows in A's list and on a card in the chat; A grants it (signed with
//     her own lock's key); the machine takes the grant, the agent's task runs there (the file it writes, its record);
//   4 A takes the grant back: the next task of that chat is refused;
//   5 A turns 免批准 on: the task runs with no grant; off again: refused;
//   6 the one made so is made a whole station again (`rig.setMode full`): among the stations, and the task runs with
//     no grant;
//   7 A takes it out of the workspace: listed no more.
// Each check says PASS or FAIL; it stops at the first that failed (each needs the one before). E2E_SF_SRC, E2E_ORIGIN,
// E2E_PEER_DATA as peer.ts; E2E_WORK, E2E_STATION as e2e-local.sh's.
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { Device, dir, fail, failures, type J, log, must, stationDo, whenChanged, within } from "./device.ts";

const a = new Device("A");
// What the rig's tasks write, outside every station's directories: the test reads it to see a task ran.
const out = `${dir}/ran`;
const NO_GRANT = /no grant of this station/;
try {
  const { workspace, station } = await a.signIn();
  log(`A signed in as ${a.sub}: workspace ${workspace}, station ${station}`);
  await a.stationState(workspace, (s) => s.state === "online", 120_000);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  await must("A opens alice's own lock", async () => {
    await a.call("adb.personalOpen", { sub: a.sub });
    await a.personal((p) => p.standing === "member");
  });

  let n = 0;
  /// The whole of it with a machine named `name`; `locked`: the workspace in security mode; `switched`: enrolled as a
  /// whole station and made one that only runs tasks in the app (else added as one).
  const run = async (name: string, locked: boolean, switched = false) => {
    const mode = `${locked ? "security mode: " : ""}${switched ? "made so: " : ""}`;
    const rigs = <T>(ok: (v: J) => T | undefined | null | false, ms = 60_000) => a.until({ topic: "rigs", workspace }, ok, ms);
    const rig = <T>(ok: (r: J) => T | undefined | null | false, ms = 60_000) => rigs((v) => {
      const r = (v?.rigs ?? []).find((x: J) => x.name === name);
      return r ? ok(r) : undefined;
    }, ms);

    // The chat whose agent uses the rig (the test station's fake claude, e2e/fake/claude.mjs: `rig:`, `rigtask:`):
    // `session` the key it was made by, `chat` its session as the station has it (what a request and a grant name).
    let session = "";
    let chat = "";
    const says = (text: string) => a.call("chat.send", { station, session, text });
    const said = (ok: (text: string) => boolean, ms = 90_000) => a.until({ topic: "chat", station, session }, (v) => (v?.messages ?? []).map((m: J) => String(m.text ?? "")).find(ok), ms);
    /// The chat's agent told to run a task on the rig that writes a file of its own: what it posted of it, and the file.
    const task = async (): Promise<{ posted: string; file: string }> => {
      const file = `${out}/${++n}`;
      const before = new Set<string>(session === "" ? [] : (await a.until({ topic: "chat", station, session }, (v) => v?.messages && v)).messages.map((m: J) => String(m.text ?? "")));
      if (session === "") session = (await a.call("chat.create", { station, runtime: "claude" })).key;
      await says(`rigtask:${name}|echo ran-on-rig > ${file}`);
      return { posted: await said((t) => t.startsWith("rigtask ") && !before.has(t)), file };
    };
    const ran = async () => {
      const t = await task();
      await whenChanged([out], () => existsSync(t.file) && readFileSync(t.file, "utf8").includes("ran-on-rig"), 60_000, () => `the task did not run on the rig: ${t.posted.slice(0, 600)}`);
    };
    const refused = async (why: RegExp) => {
      const t = await task();
      if (!why.test(t.posted)) throw new Error(`not refused as ${why}: ${t.posted.slice(0, 600)}`);
      if (existsSync(t.file)) throw new Error("the task ran all the same");
      log(`  refused: ${t.posted.slice(0, 200)}`);
    };

    let id = "";
    const code = () => readFileSync(`${process.env.E2E_WORK}/run/rig-enroll.log`, "utf8").match(/安全码(?:为)?\s*([0-9A-Z-]{4,})/)?.[1];
    if (switched) await must(`${mode}a whole station enrolled, then made one that only runs tasks: it comes up as A's`, async () => {
      const before = new Set<string>(((await a.until({ topic: "workspace", workspace }, (v) => v?.stations && v)).stations as J[]).map((s) => s.id));
      const made = await a.call("workspace.enroll", { account: a.sub, workspace, name });
      const at = `${dir}/enroll.log`;
      writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
      stationDo("second-station", at, "rig");
      id = (await a.until({ topic: "workspace", workspace }, (v) => (v?.stations ?? []).find((s: J) => !before.has(s.id)), 60_000)).id;
      if (locked) {
        if (!code()) throw new Error("no code printed");
        await a.call("lock.addStation", { workspace, station: id, code: code() });
        await a.until({ topic: "lock", workspace }, (l) => JSON.stringify(l ?? null).includes(id), 60_000);
      }
      // (reached by this device itself: what makes it one that only runs tasks is asked of it directly; hers to change,
      // as she added it)
      await a.until({ topic: "stations", scope: workspace }, (v) => (v ?? []).find((s: J) => s.id === id && s.online && s.mine), 120_000);
      await a.call("rig.setMode", { workspace, station: id, mode: "tasks" });
      const r = await rig((r) => r.id === id && r.mine && r.vouched && r.reached === true && r.known && r, 120_000);
      if (r.owner !== a.sub || r.open !== false) throw new Error(`listed as ${JSON.stringify(r)}`);
      const w = await a.until({ topic: "workspace", workspace }, (v) => v?.stations && !(v.stations as J[]).some((s) => s.id === id) && v);
      if (!(w.rigs as J[]).some((x) => x.id === id)) throw new Error("not listed as one that only runs tasks");
      log(`  ${id.slice(0, 12)} only runs tasks now`);
    });
    else await must(`${mode}A adds a rig, and the machine enrolled with its command comes up as hers`, async () => {
      const made = await a.call("rig.add", { workspace, name });
      if (!/ --rig [0-9a-f]{64}/.test(made?.command ?? "")) throw new Error(`the command pins no lock of hers: ${JSON.stringify(made)?.slice(0, 400)}`);
      if (/ --lock [0-9a-f]{64}/.test(made.command) !== locked) throw new Error(`the command and the workspace's lock: ${made.command}`);
      const at = `${dir}/enroll.log`;
      writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
      stationDo("second-station", at, "rig");
      const printed = readFileSync(`${process.env.E2E_WORK}/run/rig-enroll.log`, "utf8");
      log(`  ${printed.trim().split("\n").join(" | ")}`);
      if (locked) {
        // not taken yet: listed as hers, waiting for its code; no station sends it a task
        const waiting = await rig((r) => r.mine && r.vouched === false && r, 90_000);
        await refused(/not taken into this workspace yet/);
        if (!code()) throw new Error(`no code in: ${printed}`);
        if (await a.call("rig.vouch", { workspace, rig: waiting.id, code: "AAA-AAA" }).then(() => true, () => false)) throw new Error("taken with a code that is not its own");
        await a.call("rig.vouch", { workspace, rig: waiting.id, code: code() });
      }
      const r = await rig((r) => r.mine && r.vouched && r.reached === true && r.known && r, 90_000);
      id = r.id;
      if (r.owner !== a.sub || r.open !== false || r.grants.length !== 0) throw new Error(`listed as ${JSON.stringify(r)}`);
      // (a rig is no station: the workspace's stations are as they were)
      const w = await a.until({ topic: "workspace", workspace }, (v) => v?.stations && v);
      if ((w.stations as J[]).some((s) => s.id === id)) throw new Error("the rig is listed among the stations");
      log(`  rig ${id.slice(0, 12)} reached, code ${r.code}`);
    });

    await must(`${mode}a chat's agent with no grant is refused by the rig`, async () => {
      await refused(NO_GRANT);
      chat = await a.until({ topic: "chat", station, session }, (v) => typeof v?.thread?.id === "number" && typeof v?.key === "string" && (v.key as string));
    });

    let request: J = null;
    await must(`${mode}the agent asks for the rig: the request shows in A's list, the card in the chat`, async () => {
      await says(`rig:${name}|端到端测试：在只执行任务的 station 上跑一条命令`);
      await said((t) => t.startsWith("rig: ") && /waits for its owner/.test(t));
      request = await rig((r) => (r.requests ?? []).find((q: J) => q.status === "pending" && q.session === chat));
      const card = await a.until({ topic: "chat", station, session }, (v) => (v?.messages ?? []).map((m: J) => m.card?.rigAsk).find((c: J) => c?.request === request.id));
      if (card.rig !== id || card.owner !== a.sub || card.status) throw new Error(`the card: ${JSON.stringify(card)}`);
      log(`  request ${request.id} (${request.timeoutKind} ${request.timeoutSeconds} s)`);
    });

    await must(`${mode}A grants it: the rig takes the grant, the agent's task runs there and is in the rig's record`, async () => {
      await a.call("rig.decide", {
        station, request: request.id, allow: true, timeoutKind: "idle", timeoutSeconds: 600,
        ask: { rig: id, name, session: request.session, chat: request.chat, title: request.title, by: request.by },
      });
      const g = await rig((r) => (r.grants ?? []).find((g: J) => g.request === request.id));
      if (g.timeoutKind !== "idle" || g.timeoutSeconds !== 600 || g.session !== chat) throw new Error(`the grant: ${JSON.stringify(g)}`);
      await ran();
      const record = await a.call("rig.log", { workspace, rig: id });
      if (!JSON.stringify(record).includes("ran-on-rig")) throw new Error(`the rig's record: ${JSON.stringify(record)?.slice(0, 600)}`);
    });

    await must(`${mode}A takes the grant back: the chat's next task is refused`, async () => {
      await a.call("rig.revoke", { workspace, rig: id, request: request.id, station });
      await rig((r) => (r.grants ?? []).length === 0);
      await refused(NO_GRANT);
    });

    await must(`${mode}免批准 on: the task runs with no grant; off again: refused`, async () => {
      await a.call("rig.setOpen", { workspace, rig: id, open: true });
      await rig((r) => r.open === true);
      await ran();
      await a.call("rig.setOpen", { workspace, rig: id, open: false });
      await rig((r) => r.open === false);
      await refused(NO_GRANT);
    });

    // Devices (设备): one on the test station, every chat's; one on the rig, by its owner's grant alone. Each a TCP
    // service of this machine's that answers a line upper-cased (a camera's, a router's).
    if (!locked && !switched) {
      const echo = createServer((s) => s.on("data", (c: Buffer) => s.write(c.toString().toUpperCase())));
      await new Promise<void>((r) => echo.listen(0, "127.0.0.1", r));
      const port = (echo.address() as { port: number }).port;
      /// The chat's agent told to send `line` to `device`: what it posted of it (a post of its own, after this was said).
      const talk = async (device: string, line: string) => {
        const before = new Set<string>((await a.until({ topic: "chat", station, session }, (v) => v?.messages && v)).messages.map((m: J) => String(m.text ?? "")));
        await says(`devtalk:${device}|端到端测试：连一下设备|${line}`);
        return said((t) => (t.startsWith("devtalk heard: ") || t.startsWith("devtalk: ")) && !before.has(t));
      };
      const devices = <T>(ok: (v: J) => T | undefined | null | false) => a.until({ topic: "devices", workspace }, ok, 60_000);
      try {
        await must("a device on the test station: added by a member, every chat reaches it at once", async () => {
          await a.call("device.add", { workspace, station: station.split("/")[1], name: "e2e-cam", kind: "tcp", target: `127.0.0.1:${port}` });
          await devices((v) => (v?.devices ?? []).find((d: J) => d.name === "e2e-cam" && d.via === "station" && d.mine && d.open));
          const heard = await talk("e2e-cam", "hello-whole");
          if (!heard.includes("HELLO-WHOLE")) throw new Error(`not reached: ${heard.slice(0, 400)}`);
        });
        let request: J = null;
        await must("a device on the rig: attached as its owner signed it; a chat asks, its owner grants it alone, the chat reaches it", async () => {
          await a.call("device.add", { workspace, station: id, name: "e2e-board", kind: "tcp", target: `127.0.0.1:${port}` });
          const d = await devices((v) => (v?.devices ?? []).find((x: J) => x.name === "e2e-board" && x.via === "rig"));
          const asked = await talk("e2e-board", "hello-rig");
          if (!/waits for its owner/.test(asked)) throw new Error(`not asked: ${asked.slice(0, 400)}`);
          request = await devices((v) => (v?.devices ?? []).find((x: J) => x.id === d.id)?.requests?.find((q: J) => q.status === "pending"));
          await a.call("rig.decide", {
            station, request: request.id, allow: true, timeoutKind: "idle", timeoutSeconds: 600,
            ask: { rig: id, name, session: request.session, chat: request.chat, title: request.title, by: request.by, device: d.id, deviceName: d.name },
          });
          await devices((v) => (v?.devices ?? []).find((x: J) => x.id === d.id)?.grants?.find((g: J) => g.request === request.id));
          const heard = await talk("e2e-board", "hello-rig");
          if (!heard.includes("HELLO-RIG")) throw new Error(`not reached: ${heard.slice(0, 400)}`);
          // (a grant of the device is none of the rig: its tasks are still refused)
          await refused(NO_GRANT);
        });
        await must("the rig's device taken off by its owner: the chat reaches it no more", async () => {
          const d = await devices((v) => (v?.devices ?? []).find((x: J) => x.name === "e2e-board"));
          await a.call("device.remove", { workspace, station: id, device: d.id });
          await devices((v) => !(v?.devices ?? []).some((x: J) => x.name === "e2e-board") && v);
          const heard = await talk("e2e-board", "hello-gone");
          if (heard.includes("HELLO-GONE")) throw new Error(`still reached: ${heard.slice(0, 400)}`);
          const cam = await devices((v) => (v?.devices ?? []).find((x: J) => x.name === "e2e-cam"));
          await a.call("device.remove", { workspace, station: station.split("/")[1], device: cam.id });
        });
      } finally {
        echo.close();
      }
    }

    if (switched) await must(`${mode}A makes it a whole station again: among the stations, the task runs with no grant`, async () => {
      await a.call("rig.setMode", { workspace, station: id, mode: "full" });
      await a.until({ topic: "workspace", workspace }, (v) => (v?.stations ?? []).some((s: J) => s.id === id) && !(v.rigs ?? []).some((r: J) => r.id === id) && v, 60_000);
      await a.until({ topic: "stations", scope: workspace }, (v) => (v ?? []).find((s: J) => s.id === id && s.online && s.mine), 120_000);
      await ran();
    });

    await must(`${mode}A takes it out of the workspace: listed no more`, async () => {
      await a.call("workspace.removeStation", { account: a.sub, workspace, station: id });
      await a.until({ topic: "workspace", workspace }, (v) => v?.stations && !(v.stations as J[]).some((s) => s.id === id) && !(v.rigs ?? []).some((r: J) => r.id === id) && v);
      stationDo("second-down", "rig");
    });
  };

  await run("build-box", false);
  await run("nas", false, true);
  await must("A turns security mode on", async () => {
    const draft = await a.until({ topic: "lockDraft", workspace }, (v) => (v?.ready ? v : undefined), 120_000);
    for (const d of draft.devices ?? []) if (!d.current) await a.call("lock.toggle", { workspace, id: d.id });
    await a.call("lock.open", { workspace });
    await a.until({ topic: "lock", workspace }, (l) => l?.locked && l.signs);
    await a.stationState(workspace, (s) => s.state === "online");
  });
  await run("build-box-2", true);
  await run("nas-2", true, true);
} catch (e) {
  fail("the run", e);
}
try {
  stationDo("second-down", "rig");
} catch (e) {
  log(`  the rig's end: ${String(e).slice(0, 200)}`);
}
log(failures() === 0 ? "ALL PASSED" : `${failures()} FAILED`);
await within(a.close(), 5000);
process.exit(failures() === 0 ? 0 : 1);
