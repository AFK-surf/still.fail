import type { Account } from "./account";
import type { Directory } from "./directory";
import type { LoginAttempt, LoginLimiter } from "./login";
import type { TelemetryLimiter } from "./tracing";

export interface Env {
  ACCOUNTS: DurableObjectNamespace<Account>;
  DIRECTORY: DurableObjectNamespace<Directory>;
  /** ember station's releases (scripts/release.sh). */
  RELEASES?: R2Bucket;
  LOGINS: DurableObjectNamespace<LoginAttempt>;
  LOGIN_LIMITS: DurableObjectNamespace<LoginLimiter>;
  TELEMETRY_LIMITS: DurableObjectNamespace<TelemetryLimiter>;
  PUBLIC_ORIGIN: string;
  /** The admin's console's host (its /v1/ calls come here: see index.ts). */
  ADMIN_ORIGIN: string;
  /** Where stations and clients find the relay; defaults to PUBLIC_ORIGIN (whose /relay is the relay: relay-worker.ts). */
  RELAY_URL?: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  AUTH_SIGNING_KEY: string;
  ADMIN_TOKEN?: string;
  /** Who the console's admin is instead of ADMIN_EMAIL; set only by the tests and the dev cloud. */
  ADMIN_EMAIL?: string;
  /** Ed25519 private JWK (JSON) that signs station grants. */
  GRANT_SIGNING_JWK: string;
  /** Axiom's ingest token and dataset for traces (tracing.ts); without a token nothing is sent. */
  AXIOM_TOKEN?: string;
  AXIOM_DATASET?: string;
}
