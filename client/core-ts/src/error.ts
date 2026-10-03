// The one error calls and topics report (error.rs): `code` stable and machine-readable (still.fail cloud's codes pass
// through as they are), `message` for people in their language, `status` the HTTP status when it came from still.fail
// cloud or a station.
import { t } from "./i18n.ts";
import { DROPPED, GONE, NETWORK } from "./wake-words.ts";

export class CoreError extends Error {
  code: string;
  status?: number;
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

  /// As it goes on the wire: `{ code, message, status? }`.
  toJSON(): { code: string; message: string; status?: number } {
    return this.status === undefined ? { code: this.code, message: this.message } : { code: this.code, message: this.message, status: this.status };
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

export type Result<T> = { ok: T } | { err: CoreError };
