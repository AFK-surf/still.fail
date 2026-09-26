// This station's errors, reported to ember's PostHog project (docs/telemetry.md).
// Off unless the station's operator turns it on in config.json
// (`"telemetry": { "errors": true }`). Only errors leave: uncaught exceptions
// (unhandled rejections become those), and log.error lines, each with its
// stack, the station's id and the build. Never a log line's fields, which may
// hold what people wrote; paths under home directories lose the home, and
// quoted text in error messages (JSON.parse, for one, quotes its input) is cut.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { PostHog, type EventMessage } from "posthog-node";
import { sendErrorsTo } from "./log.ts";

/** The project key and build, written next to the admin page by its build (web/vite.config.ts). */
export interface ProjectKey { host: string; key: string; release: string }

/** The key the admin page was built with; null for a build without one (then nothing can be reported). */
export function builtKey(uiDir: string): ProjectKey | null {
  try {
    return JSON.parse(readFileSync(join(uiDir, "posthog.json"), "utf8")) as ProjectKey;
  } catch {
    return null;
  }
}

/** Home directories (this user's and anyone's) in a path or stack, as ~. */
export function scrubPaths(text: string, home = homedir()): string {
  const own = home && home !== "/" ? text.split(home).join("~") : text;
  return own.replace(/\/(?:Users|home)\/[^/\s:'"()]+/g, "~");
}

/** An error message without the text it quoted. */
export function scrubMessage(text: string, home = homedir()): string {
  return scrubPaths(text, home).replace(/"[^"]*"|'[^']*'|`[^`]*`|“[^”]*”|「[^」]*」/g, (quote) => `${quote[0]}…${quote.at(-1)}`);
}

function scrubDeep(value: unknown, home: string): unknown {
  if (typeof value === "string") return scrubPaths(value, home);
  if (Array.isArray(value)) return value.map((item) => scrubDeep(item, home));
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, scrubDeep(item, home)]));
  }
  return value;
}

/** The part of posthog-node used here; tests pass their own. */
export type ReportClient = Pick<PostHog, "captureException" | "shutdown">;

export interface ErrorReportsOptions {
  key: ProjectKey | null;
  /** Read on every report, so turning it off in the config stops them at once. */
  enabled: () => boolean;
  /** The station's id from its mesh enrollment; null before it is enrolled. */
  station: () => string | null;
  home?: string;
  client?: (key: ProjectKey, beforeSend: (event: EventMessage | null) => EventMessage | null) => ReportClient;
}

export class ErrorReports {
  readonly #options: ErrorReportsOptions;
  readonly #home: string;
  #client: ReportClient | null = null;

  constructor(options: ErrorReportsOptions) {
    this.#options = options;
    this.#home = options.home ?? homedir();
    sendErrorsTo((msg, fields) => this.#logged(msg, fields));
    this.update();
  }

  get active(): boolean {
    return this.#client !== null && this.#options.enabled();
  }

  /**
   * Starts reporting once the config turns it on. The client, once made,
   * stays (its handlers for uncaught exceptions cannot be taken back); while
   * turned off it drops everything.
   */
  update(): void {
    const { key, enabled } = this.#options;
    if (this.#client || !key || !enabled()) return;
    const make = this.#options.client ?? ((k, beforeSend) => new PostHog(k.key, { host: k.host, enableExceptionAutocapture: true, before_send: beforeSend }));
    this.#client = make(key, (event) => this.#beforeSend(event));
  }

  #beforeSend(event: EventMessage | null): EventMessage | null {
    if (!event || !this.#options.enabled()) return null;
    const station = this.#options.station();
    const properties = scrubDeep(event.properties ?? {}, this.#home) as Record<string, unknown>;
    const list = properties.$exception_list;
    if (Array.isArray(list)) {
      for (const entry of list as { value?: unknown }[]) if (typeof entry.value === "string") entry.value = scrubMessage(entry.value, this.#home);
    }
    return {
      ...event,
      ...(station ? { distinctId: `station:${station}` } : {}),
      properties: { ...properties, station, release: this.#options.key?.release ?? null, $process_person_profile: false },
    };
  }

  #logged(msg: string, fields?: Record<string, unknown>): void {
    if (!this.active) return;
    // The error in the fields if there is one (its stack says where), else one made here.
    const error = Object.values(fields ?? {}).find((value) => value instanceof Error) ?? new Error(msg);
    this.#client!.captureException(error, undefined, { log: msg });
  }

  async shutdown(): Promise<void> {
    sendErrorsTo(null);
    await this.#client?.shutdown();
  }
}
