// The one error calls and topics report (error.rs): `code` stable and machine-readable (still.fail cloud's codes pass
// through as they are), `message` for people in their language, `status` the HTTP status when it came from still.fail
// cloud or a station.
import { t } from "./i18n.ts";
import { dateClockSeconds } from "./format.ts";
import type { Span } from "./trace.ts";
import { DROPPED, GONE, NETWORK } from "./wake-words.ts";

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

  /// What a host said went wrong (`From<HostError>`): what wake.rs gives up with is said in the person's language.
  static host(error: HostError | string): CoreError {
    const text = typeof error === "string" ? error : error.message;
    const message = text === DROPPED ? t("core-misc.wake.dropped") : text === GONE ? t("core-misc.wake.gone") : text === NETWORK ? t("core-misc.wake.network") : text;
    return new CoreError("host", message);
  }

  /// What the system's secure storage or its prompt said no with (host.ts `secureGet`, `secureAsk`): the host's word
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

  /// Gone wrong past what people did or can mend (the network, a host, a station's own fault): said with the local
  /// date and time it failed at, to the second, by which an agent finds its spans (docs/telemetry.md). The first
  /// time, the deepest span's: the one that has what the transport said.
  stamped(atMs: number, offsetMin: number): void {
    if (this.at !== undefined) return;
    if (!(this.code === "mesh" || this.code === "host" || this.code === "timeout" || (this.status ?? 0) >= 500)) return;
    this.at = atMs;
    this.message = t("core-misc.error.at", { message: this.message, time: dateClockSeconds(atMs, offsetMin) });
  }

  equals(other: CoreError): boolean {
    return this.code === other.code && this.message === other.message && this.status === other.status;
  }
}

/// What a host says when what it was asked failed (host.rs `HostError`).
export class HostError extends Error {}

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
