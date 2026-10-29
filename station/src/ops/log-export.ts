// The station's log, sent to still.fail (docs/telemetry.md): what is wrong between stations, or between a station and
// still.fail cloud, is found from our side without asking anyone for their log file. On unless the station's config
// turns it off (`telemetry.logs: false`), read for every batch so turning it off stops it at once. Each line goes
// scrubbed: no home directories, emails, things shaped like keys or tokens, or quoted text, and fields that can carry
// what people wrote (a notice's text, a job's or skill's name) not at all. Batched every few seconds as OpenTelemetry
// logs to the control plane (still.fail cloud's `/v1/telemetry/logs`, signed with the station's key; the cloud passes
// them on to Axiom); a batch that cannot be sent is dropped, and lines past what is kept waiting are counted, not kept.
import { Effect } from "effect";
import { wall } from "./fibers.ts";
import type { Level, Line } from "./log.ts";
import { scrubMessage } from "./telemetry.ts";

const EVERY_MS = 5_000;
/// Lines kept waiting at most (the oldest go first), and sent in one batch at most.
const MAX_WAITING = 5_000;
const MAX_BATCH = 500;
/// A value is cut past this.
const MAX_VALUE = 2_000;
/// How often a batch that could not be sent is said on stderr.
const SAY_FAILED_MS = 10 * 60_000;

/// Fields whose values are what people or agents wrote, never sent.
const WRITTEN = new Set(["text", "name", "title", "command", "args", "prompt", "body", "question", "content"]);
const SEVERITY: Record<Level, number> = { INFO: 9, WARN: 13, ERROR: 17 };
/// A workspace's id (its name is people's).
const WORKSPACE_ID = /^[0-9A-HJKMNP-TV-Z]{26}$/;

const EMAIL = /[^\s@"'`<>()=,;:]+@[^\s@"'`<>()=,;:]+\.[A-Za-z]{2,}/g;
/// A profile's id made of an email (zzj3720-gmail-com).
const EMAIL_SLUG = /\b[\w.+]+-(?:[a-z0-9]+-)*(?:com|net|org|me|io|cn|dev|ai|co|app)\b/gi;
/// JWTs, API keys and tokens by their usual prefixes, AWS access keys.
const SECRET = /\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*|\b(?:sk|pk|rk|ghp|gho|ghs|ghu|github_pat|xox[abpr]|glpat)[-_][\w-]{16,}|\bAKIA[0-9A-Z]{16}\b/g;

/// A piece of the log as it may leave the machine.
export function scrubText(text: string, home: string): string {
  const cut = text.length > MAX_VALUE ? `${text.slice(0, MAX_VALUE)}…` : text;
  return scrubMessage(cut.replace(SECRET, "<secret>").replace(EMAIL, "<email>").replace(EMAIL_SLUG, "<email>"), home);
}

function scrubValue(key: string, value: unknown, home: string): unknown {
  if (WRITTEN.has(key)) return "…";
  if (key === "workspace" && typeof value === "string" && !WORKSPACE_ID.test(value)) return "…";
  if (typeof value === "string") return scrubText(value, home);
  if (Array.isArray(value)) return value.map((v) => scrubValue("", v, home));
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, scrubValue(k, v, home)]));
  return value;
}

const attribute = (key: string, value: unknown) => ({
  key,
  value: typeof value === "number" && Number.isSafeInteger(value) ? { intValue: String(value) }
    : typeof value === "number" ? { doubleValue: value }
    : typeof value === "boolean" ? { boolValue: value }
    : { stringValue: typeof value === "string" ? value : JSON.stringify(value) ?? String(value) },
});

/// A line as an OpenTelemetry log record, scrubbed.
export function record(line: Line, home: string) {
  const fields = Object.entries(line.fields).filter(([, v]) => v !== undefined);
  return {
    timeUnixNano: (BigInt(Math.round(line.ms)) * 1_000_000n).toString(),
    severityNumber: SEVERITY[line.level],
    severityText: line.level,
    body: { stringValue: scrubText(line.message, home) },
    attributes: [attribute("log.target", line.at), ...fields.map(([k, v]) => attribute(`log.${k}`, scrubValue(k, v, home)))],
  };
}

export type LogExportOptions = {
  /// Read for every batch.
  enabled: () => boolean;
  /// The station's id from its enrollment; null before it is enrolled (nothing is sent then).
  station: () => string | null;
  version: () => string;
  home?: string;
};

export class LogExport {
  private options: LogExportOptions | null = null;
  private home = process.env.HOME ?? "";
  private waiting: Line[] = [];
  private dropped = 0;
  private send: ((body: string) => Promise<unknown>) | null = null;
  private sending: Promise<void> | null = null;
  private stop: (() => void) | null = null;
  private saidFailed = 0;
  private closed = false;

  configure(options: LogExportOptions) {
    this.options = options;
    this.home = options.home ?? this.home;
    this.stop ??= wall.every(EVERY_MS, () => void this.flush());
  }

  /// How a batch goes (the control plane's, once the station has one).
  sendWith(send: (body: string) => Promise<unknown>) {
    this.send = send;
  }

  add(line: Line) {
    if (this.closed || this.options === null || !this.options.enabled()) return;
    this.waiting.push(line);
    if (this.waiting.length > MAX_WAITING) {
      this.dropped += this.waiting.length - MAX_WAITING;
      this.waiting.splice(0, this.waiting.length - MAX_WAITING);
    }
  }

  /// The batch of `lines` as it is sent.
  body(lines: Line[], station: string, dropped = 0): string {
    const records = lines.map((l) => record(l, this.home));
    if (dropped > 0) records.push(record({ ms: wall.now(), level: "WARN", at: "telemetry", message: "log lines dropped before they could be sent", fields: { dropped } }, this.home));
    const resource = [attribute("service.name", "stillfail-station"), attribute("service.version", this.options?.version() ?? ""), attribute("stillfail.station", station)];
    return JSON.stringify({ resourceLogs: [{ resource: { attributes: resource }, scopeLogs: [{ scope: { name: "stillfail-station" }, logRecords: records }] }] });
  }

  /// Sends what waits, a batch at a time.
  flush(): Promise<void> {
    this.sending ??= this.sendAll().finally(() => (this.sending = null));
    return this.sending;
  }

  private async sendAll() {
    while (this.waiting.length > 0) {
      const options = this.options;
      const send = this.send;
      const station = options?.station() ?? null;
      if (options === null || !options.enabled()) {
        this.waiting = [];
        this.dropped = 0;
        return;
      }
      if (send === null || station === null) return;
      const lines = this.waiting.splice(0, MAX_BATCH);
      const dropped = this.dropped;
      this.dropped = 0;
      try {
        await send(this.body(lines, station, dropped));
      } catch (error) {
        // Not through the log: that would send itself.
        if (wall.now() - this.saidFailed > SAY_FAILED_MS) {
          this.saidFailed = wall.now();
          process.stderr.write(`${new Date(wall.now()).toISOString()}  WARN telemetry: the station's log not sent error=${(error as Error).message}\n`);
        }
        return;
      }
    }
  }

  /// Sends what waits (at most 5 s), then nothing more.
  async shutdown() {
    this.stop?.();
    this.closed = true;
    const sent = this.flush();
    await Effect.runPromise(Effect.timeoutOption(Effect.promise(() => sent), "5 seconds"));
  }
}

/// The station's: configured as it starts (main.ts), sent through its control plane once the mesh is up (mesh.ts).
export const stationLog = new LogExport();
