import type { Account } from "./account";
import type { Directory } from "./directory";
import type { LoginAttempt, LoginLimiter } from "./login";
import type { TelemetryLimiter } from "./tracing";

export interface Env {
  ACCOUNTS: DurableObjectNamespace<Account>;
  DIRECTORY: DurableObjectNamespace<Directory>;
  /** The stations' releases (scripts/release.sh). */
  RELEASES?: R2Bucket;
  LOGINS: DurableObjectNamespace<LoginAttempt>;
  LOGIN_LIMITS: DurableObjectNamespace<LoginLimiter>;
  TELEMETRY_LIMITS: DurableObjectNamespace<TelemetryLimiter>;
  /** The web app's and the API's origin; every link the cloud makes is on it. */
  PUBLIC_ORIGIN: string;
  /** Older origins of the same (comma-separated): answered like PUBLIC_ORIGIN, never linked to (compat.ts). */
  PUBLIC_ORIGIN_ALIASES?: string;
  /** The admin's console's host (its /v1/ calls come here: see index.ts). */
  ADMIN_ORIGIN: string;
  /** Older origins of the console (comma-separated), answered like ADMIN_ORIGIN. */
  ADMIN_ORIGIN_ALIASES?: string;
  /**
   * The web app's test channel (https://app.youdid.wtf): the same API on another host, for the accounts the admin lets
   * in (`beta` in the console); unset, there is none (index.ts).
   */
  BETA_ORIGIN?: string;
  /** Where stations and clients find the relay; defaults to PUBLIC_ORIGIN (whose /relay is the relay: relay-worker.ts). */
  RELAY_URL?: string;
  /** More relays beside it (comma-separated), for where it is slow or out of reach (relays.ts). */
  RELAY_URLS?: string;
  /** Ways into the relays for devices alone (comma-separated): one relay machine's address forwarding to another's relay
   * (relays.ts). */
  RELAY_ENTRIES?: string;
  /** What the relays are called (by their URL) where people see which one a connection goes through (relays.ts). */
  RELAY_NAMES?: Record<string, string>;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  AUTH_SIGNING_KEY: string;
  ADMIN_TOKEN?: string;
  /** The console admin's Google email (wrangler.jsonc; the tests and the dev cloud set their own). Unset: no admin. */
  ADMIN_EMAIL?: string;
  /** Ed25519 private JWK (JSON) that signs station grants. */
  GRANT_SIGNING_JWK: string;
  /** Axiom's ingest token and dataset for traces (tracing.ts); without a token nothing is sent. */
  AXIOM_TOKEN?: string;
  AXIOM_DATASET?: string;
  /** still.fail cloud's VAPID key for Web Push (webpush.ts): the P-256 public point and private scalar, base64url. Without them there is no Web Push. */
  VAPID_PUBLIC_KEY?: string;
  VAPID_PRIVATE_KEY?: string;
  /** Who push services may write to about it (a mailto:); PUBLIC_ORIGIN if unset. */
  VAPID_SUBJECT?: string;
  /** The Firebase project's service account (its JSON) that sends to the Android app (fcm.ts). Without it there is no FCM. */
  FCM_SERVICE_ACCOUNT?: string;
  /** The accounts that sign in with an email and a password (password.ts): a JSON list of {email, password, name?}, App Store review's. Unset: none. */
  REVIEW_ACCOUNTS?: string;
}
