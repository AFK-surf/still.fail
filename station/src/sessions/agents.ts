// The agents' side of the station (server.rs `App::start`): the hub with its drivers, background jobs, tasks for other
// stations, the agents' tools and their door (/mcp). Made here and given to the rest; nothing else starts an agent.
//
// What the previous station process ran goes on (docs/station-ts.md, 已定 1): a station that stops hands its sessions
// over (run/handover.json) and the next takes them up, runtimes and all, from their runners. Under the launcher the
// next process is up before the previous one hands over: it takes up only once that one is gone (run/hub.json says
// which process holds the sessions), and opens the agents' door only then, so no call reaches a hub without its session.
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Context, Effect, Layer, Stream } from "effect";
import { ClaudeDriver } from "../agents/claude.ts";
import { CodexDriver } from "../agents/codex.ts";
import { Jobs, notifyEndpoint } from "../jobs/jobs.ts";
import { Remote } from "../jobs/remote.ts";
import { ConfigFile } from "../ops/config.ts";
import type { Control } from "../ops/launcher.ts";
import { log } from "../ops/log.ts";
import { Cloud, Events, Paths, Readers, Store } from "../services.ts";
import { adbTools } from "../tools/adb.ts";
import { chatTools } from "../tools/chat.ts";
import { type AgentsDoor, openAgentsDoor } from "../tools/http.ts";
import { jobTools } from "../tools/jobs.ts";
import { McpEndpoint, UNBOUND_REFUSAL } from "../tools/mcp.ts";
import { remoteTools } from "../tools/remote.ts";
import { UsageCounter } from "../usage/counter.ts";
import { hubConfig } from "./config.ts";
import { Hub } from "./hub.ts";
import { InternalChat } from "./internal.ts";
import { autoArchive } from "./lifecycle.ts";
import { fromPeer } from "./messages.ts";

/// server.rs `encode` (encodeURIComponent).
const encode = encodeURIComponent;

/// How long a drain waits for running turns to end, and how long a drained station waits to be stopped before it takes
/// turns again (whoever asked went away).
const DRAIN_LIMIT_MS = 600_000;
const DRAINED_LIMIT_MS = 300_000;
/// How long the previous station process is waited for before its sessions are taken up all the same.
const PREVIOUS_LIMIT_MS = 40_000;

export type AgentsParts = { hub: Hub; jobs: Jobs; remote: Remote; mcp: McpEndpoint; config: ConfigFile; usage: UsageCounter };

export class Agents extends Context.Service<Agents, AgentsParts>()("stillfail/Agents") {}

/// Whether a process is alive (signal 0).
function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === "EPERM";
  }
}

/// Waits for the station process that held the sessions before (run/hub.json) to be gone.
async function previousGone(run: string) {
  let pid = 0;
  try {
    pid = JSON.parse(readFileSync(join(run, "hub.json"), "utf8")).pid;
  } catch {
    return;
  }
  if (typeof pid !== "number" || pid === process.pid || !alive(pid)) return;
  log.info("hub", "waiting for the previous station process to hand over", { pid });
  const until = Date.now() + PREVIOUS_LIMIT_MS;
  // A process's end can only be looked for: every 100 ms, for the seconds a handover takes.
  while (alive(pid) && Date.now() < until) await new Promise((r) => setTimeout(r, 100));
  if (alive(pid)) log.warn("hub", "the previous station process is still there; taking up its sessions all the same", { pid });
}

export const AgentsLive = (control: Control) =>
  Layer.effect(
    Agents,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      const store = yield* Store;
      const cloud = (yield* Cloud).state;
      const readers = yield* Readers;
      const events = yield* Events;
      const run = join(data, "run");
      const config = new ConfigFile(data);
      const place = () => {
        const s = cloud.state;
        return s && s.workspace && !cloud.removed() ? s : null;
      };
      const bound = () => place() !== null;
      const pageOf = (key: string) => {
        const s = place();
        return s ? `${s.origin}/o/${s.workspace}/${s.station}/${encode(key)}` : undefined;
      };

      const settings = () => hubConfig(config.raw(), data);
      const hub = new Hub({
        config: settings,
        store,
        // Slack and the other chat platforms: phase 4. The station's own chat is the hub's.
        chats: () => undefined,
        drivers: [
          new ClaudeDriver({ data }),
          new CodexDriver({ data, currentProfile: (id) => settings().profiles.find((p) => p.id === id) }),
        ],
        mcpUrl: () => door?.url ?? "",
        internal: new InternalChat(),
        link: pageOf,
      });
      // Background jobs and web services: their agents told through the hub; a service's link is its session's page
      // with its port.
      const jobs = new Jobs({
        store,
        data,
        notify: (session, text) => {
          try {
            hub.notify(session, text);
          } catch (error) {
            log.warn("jobs", "job notice not given", { session, error: (error as Error).message });
          }
        },
        link: (session, job) => {
          const page = pageOf(session);
          return page ? `${page}?service=${encode(job)}` : null;
        },
      });
      const remote = new Remote({ data, store, jobs, notify: (session, text) => hub.notify(session, text), config: () => config.raw() });
      hub.setJobs(jobs);
      hub.onPeer((station, request) => remote.ask(station, request));
      hub.onClose((session) => remote.closeSession(session));
      remote.setInbox((peer, request) => fromPeer(hub, peer, request));

      const tools = [
        ...chatTools(hub),
        ...remoteTools(remote),
        ...adbTools(() => [], () => {
          const s = place();
          return s ? `${s.origin}/w/${s.workspace}/s/${s.station}/adb` : null;
        }),
        ...jobTools(jobs, (key) => store.getSession(key)?.workspace ?? null),
      ];
      // Outside a workspace its agents do not reach out of it: their outward tools are refused.
      const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, tools, () => (bound() ? undefined : UNBOUND_REFUSAL));

      // The readers say what runs, and which chats clients made: the hub's.
      readers.processes = () => hub.processes();
      readers.clientKeys = () => hub.clientKeys();
      events.followLive((key, from, last, send) => {
        const id = hub.live.subscribe(key, from, last, send);
        return () => hub.live.unsubscribe(key, id);
      });

      // In a workspace, or out of it, as cloud.json says, from now on.
      let inWorkspace = bound();
      const follow = async () => {
        const now = bound();
        if (now === inWorkspace) return;
        inWorkspace = now;
        if (now) {
          log.info("station", "in a workspace: turns and jobs go on");
          hub.recover();
          jobs.relaunch();
          hub.release("unbound");
        } else {
          const why = cloud.removed() ? "the station was removed from its workspace" : "the station is in no workspace";
          log.warn("station", "out of its workspace: ending the agents' runtimes, stopping jobs and services", { why });
          hub.hold("unbound");
          await hub.suspendAll();
          await jobs.stopAll(why);
        }
      };
      yield* (yield* Cloud).changes.pipe(
        Stream.runForEach(() => Effect.promise(follow)),
        Effect.forkScoped,
      );

      let door: AgentsDoor | null = null;
      let handing = false;
      // Taken up once the previous process is gone; then the door opens, and what was cut off resumes.
      const start = async () => {
        await previousGone(run);
        mkdirSync(run, { recursive: true });
        writeFileSync(join(run, "hub.json"), JSON.stringify({ pid: process.pid }) + "\n");
        if (!inWorkspace) hub.hold("unbound");
        await hub.takeUp();
        // The launcher's socket; on its own, 4750 or the port config.json names (taken by something else: a free one,
        // unless it was named, ports.rs).
        const named = config.raw()?.http?.port;
        const notified = (authorization: string | undefined, body: Buffer) => notifyEndpoint(jobs, authorization, body);
        try {
          door = await openAgentsDoor(control.mcpFd !== undefined ? { fd: control.mcpFd } : { port: Number(named ?? 4750) }, mcp, notified);
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "EADDRINUSE" || named !== undefined) throw error;
          door = await openAgentsDoor({ port: 0 }, mcp, notified);
        }
        jobs.setNotifyUrl(door.url.replace(/\/mcp$/, "/jobs/notify"));
        log.info("station", "agents' door open", { url: door.url });
        if (inWorkspace) {
          hub.recover();
          jobs.relaunch();
        } else if (cloud.removed()) {
          // Removed, and the station stopped before it stopped its jobs (or crashed): what still runs is ended now.
          await jobs.stopAll("the station was removed from its workspace");
        }
      };
      yield* Effect.forkScoped(Effect.promise(() => start().catch((e) => log.error("hub", "the agents' side did not start", { error: (e as Error).message }))));

      // What the agents spent, read from their transcripts: now, and after each turn ends.
      const usage = new UsageCounter({ store, config: () => ({ dataDir: data, profiles: settings().profiles }) });
      usage.start();

      // Chats idle long enough go to the archive: looked at now and every hour.
      const archiving = setInterval(() => {
        try {
          autoArchive(hub, Date.now());
        } catch (error) {
          log.warn("hub", "auto-archiving failed", { error: (error as Error).message });
        }
      }, 3_600_000);
      archiving.unref();

      // A drain (SIGUSR1): no new turns; said when none runs (run/drained), turns again if nobody stops the station.
      let draining = false;
      control.on("drain", () => {
        if (draining) return;
        draining = true;
        log.info("station", "draining: no new turns; waiting for running ones to end");
        hub.hold("drain");
        const until = Date.now() + DRAIN_LIMIT_MS;
        const done = (said: "idle" | "timeout") => {
          stopListening();
          clearTimeout(limit);
          log.info("station", "drained", { said });
          writeFileSync(join(run, "drained"), `${said}\n`);
          control.drained(said);
          setTimeout(() => {
            log.warn("station", "drained but not stopped; taking turns again");
            rmSync(join(run, "drained"), { force: true });
            hub.release("drain");
            draining = false;
          }, DRAINED_LIMIT_MS).unref();
        };
        // A turn's end is a session change: looked at then, not on a timer.
        const stopListening = store.subscribe((change) => {
          if (change.type === "session" && !hub.anyRunning()) done("idle");
        });
        const limit = setTimeout(() => done("timeout"), Math.max(0, until - Date.now()));
        if (!hub.anyRunning()) done("idle");
      });

      // Stopping hands the sessions over, whether to the next process now (handover) or the next start: their runtimes
      // run on under their runners.
      yield* Effect.addFinalizer(() =>
        Effect.promise(async () => {
          if (handing) return;
          handing = true;
          clearInterval(archiving);
          await door?.close(30_000);
          try {
            await hub.handOver();
          } catch (error) {
            log.warn("hub", "sessions not handed over; they resume the usual way", { error: (error as Error).message });
            await hub.shutdown();
          }
          await jobs.shutdown();
          await usage.stop();
          if (existsSync(join(run, "hub.json"))) {
            try {
              if (JSON.parse(readFileSync(join(run, "hub.json"), "utf8")).pid === process.pid) rmSync(join(run, "hub.json"), { force: true });
            } catch {}
          }
        }),
      );
      return Agents.of({ hub, jobs, remote, mcp, config, usage });
    }),
  );
