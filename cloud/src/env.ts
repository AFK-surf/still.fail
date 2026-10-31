import type { Account } from "./account";
import type { Directory } from "./directory";
import type { LoginAttempt, LoginLimiter } from "./login";
import type { Mailer } from "./mail";
import type { RelayLoad } from "./relay-load";
import type { Relay } from "./relay-worker";
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
  /** "globalping": the relays are probed from China's networks every half hour (probes.ts). */
  RELAY_PROBES?: string;
  /** Ways into the relays for devices alone (comma-separated): one relay machine's address forwarding to another's relay
   * (relays.ts). */
  RELAY_ENTRIES?: string;
  /** The relay each entry forwards to, keyed by the entry's URL (relays.ts). */
  RELAY_ENTRY_TARGETS?: Record<string, string>;
  /** What the relays are called (by their URL) where people see which one a connection goes through (relays.ts). */
  RELAY_NAMES?: Record<string, string>;
  /** How loaded the relays are, for the console (relay-load.ts). */
  RELAY_LOAD: DurableObjectNamespace<RelayLoad>;
  /** still.fail's own relay process, in the relay's Worker (relay-worker.ts): its counters, read by the cron. Unset: not read. */
  RELAY?: DurableObjectNamespace<Relay>;
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
  /** The team's APNs key that sends to the iOS app (apns.ts): JSON { keyId, teamId, key (the .p8's PEM), topic? }. Without it there is no APNs. */
  APNS_KEY?: string;
  /** The accounts that sign in with an email and a password (password.ts): a JSON list of {email, password, name?}, App Store review's. Unset: none. */
  REVIEW_ACCOUNTS?: string;
  /** Cloudflare Email Service's send_email binding (wrangler.jsonc), which sends the sign-in codes (mail.ts). */
  EMAIL?: Mailer;
  /** The address the codes come from (its domain onboarded for sending). Unset, or without EMAIL: nobody signs in with
   * an email, and a sign-in goes straight to Google, as before there was another way. */
  EMAIL_FROM?: string;
}
