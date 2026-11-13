// The one error calls and topics report (error.rs): `code` stable and machine-readable (still.fail cloud's codes pass
// through as they are), `message` for people in their language, `status` the HTTP status when it came from still.fail
// cloud or a station.
import { t } from "./lang.ts";
import type { Span } from "./trace.ts";
import { local, remEuclid } from "./util.ts";
import { DROPPED, GONE, NETWORK } from "./wake-words.ts";

/// 10月28日 00:40:14, local: a moment said to the second, for an error people may report days later.
export function dateClockSeconds(ms: number, offsetMin: number): string {
  const [, month, day, , h, m] = local(ms, offsetMin);
  // Offsets are whole minutes: the second is the same everywhere.
  const s = Math.floor(remEuclid(Math.floor(ms), 60_000) / 1000);
  const two = (n: number) => String(n).padStart(2, "0");
  return t("core-logic.format.date_time", { date: t(`core-logic.format.date.${month}`, { day }), time: `${two(h)}:${two(m)}:${two(s)}` });
}

export class CoreError extends Error {
  code: string;
  status?: number;
  /// When it failed (`stamped`), ms.
  at?: number;
  constructor(code: string, message: string, status?: number) {
    super(message);
    this.code = code;
    if (status !== undefined) this.status = status;
  }

  withStatus(status: number): CoreError {
    this.status = status;
    return this;
  }

  /// The account's session is gone: it has to sign in again.
  static signedOut(message: string): CoreError {
    return new CoreError("signed_out", message);
  }

  static invalid(message: string): CoreError {
    return new CoreError("invalid_params", message);
  }

  /// What a host said went wrong (`From<HostError>`): what wake.rs gives up with, and what the core said itself
  /// (`HostError.said`), in the person's language; anything else (a system's, the network's, in its own words) as what
  /// kind of failure it was (`plainly`).
  static host(error: HostError | string): CoreError {
    const text = typeof error === "string" ? error : error.message;
    if (text === DROPPED) return new CoreError("host", t("core-misc.wake.dropped"));
    if (text === GONE) return new CoreError("host", t("core-misc.wake.gone"));
    if (text === NETWORK) return new CoreError("host", t("core-misc.wake.network"));
    if (error instanceof HostError && error.said === true) return new CoreError("host", text);
    return CoreError.plainly("host", text);
  }

  /// A failure under the core (a host's, the network's, a library's) said to people: in their words, as what kind of
  /// failure it was; what it said itself kept as its `cause`, which telemetry has (`failedIn`), never shown. `words`:
  /// what failed, where the caller can say it better.
  static plainly(code: string, said: unknown, words?: string): CoreError {
    const text = said instanceof Error ? said.message : String(said);
    const error = new CoreError(code, words ?? t(NETWORKISH.test(text) ? "core-misc.host.network" : "core-misc.host.failed"));
    error.cause = text;
    return error;
  }

  /// What the system's secure storage or its prompt said no with (host-of.ts `secureGet`, `secureAsk`): the host's word
  /// (`user_cancelled`, `no_device_lock`, `not_in_front`, `key_invalidated`, …) as the code a page goes by, said in the
  /// person's language; what is not such a word, as `otherwise` with what the host said.
  static refused(error: HostError, otherwise: string): CoreError {
    const said = error.message;
    if (!/^[a-z][a-z_]*$/.test(said)) return new CoreError(otherwise, said);
    const words: Record<string, string> = {
      user_cancelled: t("core-misc.call.cancelled"),
      no_device_lock: t("core-misc.secure.noDeviceLock"),
      not_in_front: t("core-misc.secure.notInFront"),
      key_invalidated: t("core-misc.secure.keyInvalidated"),
    };
    return new CoreError(said, words[said] ?? said);
  }

  /// As it goes on the wire: `{ code, message, status? }`.
  toJSON(): { code: string; message: string; status?: number } {
    return this.status === undefined ? { code: this.code, message: this.message } : { code: this.code, message: this.message, status: this.status };
  }

  /// Gone wrong past what people did or can mend (the network, a host, a station's own fault, anything said `plainly`):
  /// said with the local date and time it failed at, to the second, by which an agent finds its spans
  ///. The first time, the deepest span's: the one that has what the transport said.
  stamped(atMs: number, offsetMin: number): void {
    if (this.at !== undefined) return;
    if (!(this.code === "mesh" || this.code === "host" || this.code === "timeout" || (this.status ?? 0) >= 500 || typeof this.cause === "string")) return;
    this.at = atMs;
    this.message = t("core-misc.error.at", { message: this.message, time: dateClockSeconds(atMs, offsetMin) });
  }

  equals(other: CoreError): boolean {
    return this.code === other.code && this.message === other.message && this.status === other.status;
  }
}

/// What a host says when what it was asked failed: in its own words, or (`said`) in the person's,
/// as the core says it to them.
export class HostError extends Error {
  readonly said?: true;
  constructor(message: string, said = false) {
    super(message);
    if (said) this.said = true;
  }

  /// A failure the core words for people itself (with `t`): said as it is.
  static said(message: string): HostError {
    return new HostError(message, true);
  }
}

/// What a network failure says, in any host's words (Rust's reqwest and quinn, undici, a browser's fetch, the OS).
const NETWORKISH = /network|connect|connection|dns|resolve|timed? ?out|timeout|socket|reset|refused|unreachable|tls|certificate|fetch failed|load failed|offline|ECONN|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|EPIPE|EHOSTUNREACH|ENETUNREACH/i;

/// Any failure as the core's error: a CoreError as it is, a host's as `host`.
export function asCoreError(error: unknown): CoreError {
  if (error instanceof CoreError) return error;
  if (error instanceof HostError) return CoreError.host(error);
  return CoreError.host(error instanceof Error ? error.message : String(error));
}

/// `span` failed with `error`: what it was (`error.type`), what the transport said (`stillfail.cause`), and the error
/// said with when (`stamped`).
export function failedIn(span: Span, error: CoreError): void {
  span.fail();
  span.set("error.type", error.code);
  if (typeof error.cause === "string") span.set("stillfail.cause", error.cause);
  const now = span.host.nowMs();
  error.stamped(now, span.host.utcOffsetMin(now));
}

export type Result<T> = { ok: T } | { err: CoreError };
