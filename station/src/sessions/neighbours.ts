// What the hub needs of the parts beside it that are ported elsewhere (src/jobs/): background jobs (jobs.rs) and the
// station transport to the workspace's other stations (remote.rs). Minimal: the hub and its tools call these, the
// composition root gives them; until it does, what needs one says it is not there.
import type { JobRow } from "../store/store.ts";

type Json = any;

/// jobs.rs `Watch`: whether a job keeps watch (its end and notices bring its session back, its wait does not run out).
export type Watch = { on: boolean };

/// jobs.rs `Jobs`, its public functions.
export interface Jobs {
  start(session: string, name: string, command: string, cwd: string, port: number | null, watch: Watch): JobRow | Promise<JobRow>;
  /// A session's jobs, or all.
  list(session: string | null): JobRow[];
  /// The last `lines` of a job's output.
  log(id: string, lines: number): string;
  stop(id: string): Promise<JobRow>;
  /// Stopped by someone (`who`: an email), as the pages do.
  stopFor(id: string, who: string): Promise<JobRow>;
  stopAll(why: string): Promise<void>;
  /// Starts again the services that were up when the station stopped.
  relaunch(): void;
  /// The watches running, by session (jobs.rs `watching`).
  watching(): Map<string, Json>;
}

/// remote.rs `Remote`, as far as the hub and its tools reach it.
export interface Remote {
  /// station_list / station_task / station_file for `session` (remote.rs `tool`): what the tool answers, as JSON.
  tool(name: "station_list" | "station_task" | "station_file", session: string, args: Record<string, Json>): Promise<Json>;
  /// Calls another station of the workspace by its id (Remote::ask): how session_send reaches a session there. A
  /// station that refused it throws a `Refused`.
  ask(station: string, request: Json): Promise<Json>;
  /// A session was archived or deleted: what it left on other stations goes too.
  closeSession(session: string): void;
}

/// An answer another station gave: it refused the request (remote.rs `Refused`).
export class Refused extends Error {}
