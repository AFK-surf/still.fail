// A rig's forms (a station that only runs tasks, 2026-11-10): what its person's device signs for it, one for the devices (rig.ts) and the
// stations (station/src/rig/, station/src/rigs/). A rig is a machine that only runs what the workspace's stations send
// it; whose chats may use it is its person's say alone, signed with a key on their own lock (personal-lock.ts) and
// checked by the rig itself against the lock it pinned as it joined, whatever a station or the cloud says. Pure: each
// side hashes with its own SHA-256, as lock-form.ts.
import { canonical } from "./lock-form.ts";

/// How long a grant lasts, as a vault's does (station/src/vault/secrets.ts): `idle`, until the chat has used the rig for
/// nothing that long (a task of its still running there is use); `fixed`, that long from when it was signed.
export type Timeout = { kind: "idle" | "fixed"; seconds: number };
export const TIMEOUT_DEFAULT: Timeout = { kind: "idle", seconds: 3600 };
export const TIMEOUT_MIN = 60;
export const TIMEOUT_MAX = 30 * 86400;

/// Why `t` is no timeout a grant may have, or null: idle or fixed, whole minutes, a minute to 30 days.
export function timeoutRefusal(t: unknown): string | null {
  const o = t as Timeout | null;
  if (o === null || typeof o !== "object" || (o.kind !== "idle" && o.kind !== "fixed") || !Number.isSafeInteger(o.seconds) || o.seconds < TIMEOUT_MIN || o.seconds > TIMEOUT_MAX || o.seconds % 60 !== 0) {
    return "timeout must be idle or fixed, in whole minutes from 1 minute to 30 days";
  }
  return null;
}

/// A chat's grant of a rig: the chat (`session` on `station`, `chat` its thread) may use `rig` until `exp` at the
/// latest (unix seconds), sooner by `timeout`. `title` and `by` (who started the chat) are what the person saw as they
/// signed, kept for whoever lists the rig's grants; `request` is the station's name for what was asked. `device`: one
/// of the rig's devices (`DeviceBody`) alone, not the rig; none: the rig, its devices with it.
export type GrantBody = { v: 1; sub: string; ws: string; rig: string; station: string; session: string; chat: string; request: string; title: string; by: string; timeout: Timeout; at: number; exp: number; device?: string };
/// A grant taken back.
export type RevokeBody = { v: 1; sub: string; ws: string; rig: string; request: string; at: number };
/// The rig's settings, each one whole and numbered (`seq`): a rig keeps the highest it has seen, so one from before
/// cannot be brought again. `open` (免批准): every chat of the workspace uses it with no grant, as a station's.
/// `device`: one of its devices' settings, numbered on their own.
export type SettingsBody = { v: 1; sub: string; ws: string; rig: string; seq: number; open: boolean; at: number; device?: string };
/// The rig taken into a workspace in security mode by its person, who compared its code: what the stations there
/// take in the place of the cloud's word that it is one of the workspace's rigs.
export type AddBody = { v: 1; sub: string; ws: string; rig: string; at: number };

/// The rig made a whole station again (one that runs agents and serves the workspace's every chat) by its person:
/// what the machine takes, with the control plane listing it as one, to stop being a rig. Good for `FULL_FOR` seconds
/// from `at`, so one never acted on is not brought much later.
export type FullBody = { v: 1; sub: string; ws: string; rig: string; at: number };
export const FULL_FOR = 3600;

/// A device the rig's person attached to it (设备, 2026-11-10: a phone or a board on its USB, a camera or a router on
/// its network, anything an agent reaches that runs no station), or, `removed`, taken off it again. What a chat reaches
/// of it is `target`: an adb serial on the rig's own adb (`adb`), an address and port its network reaches (`tcp`), or a
/// serial port's path (`serial`, at `baud`).
export type Device = { id: string; name: string; kind: DeviceKind; target: string; baud?: number };
export type DeviceKind = "adb" | "tcp" | "serial";
export const DEVICE_KINDS: DeviceKind[] = ["adb", "tcp", "serial"];
export type DeviceBody = { v: 1; sub: string; ws: string; rig: string; device: Device; removed: boolean; at: number };

export type Kind = "grant" | "revoke" | "settings" | "add" | "full" | "device";
export type Signed<B> = { body: B; sig: { key: string; sig: string } };

const TAGS: Record<Kind, string> = { grant: "stillfail-rig-grant/1", revoke: "stillfail-rig-revoke/1", settings: "stillfail-rig-settings/1", add: "stillfail-rig-add/1", full: "stillfail-rig-full/1", device: "stillfail-rig-device/1" };

/// What is signed for a statement of `kind`: its tag, a NUL, then the SHA-256 of its body's canonical JSON (as a
/// phone's grant is signed), so a signature for one kind is none for another.
export function signedBytes(kind: Kind, body: unknown, sha256: (bytes: Uint8Array) => Uint8Array): Uint8Array {
  const tag = new TextEncoder().encode(`${TAGS[kind]}\0`);
  const digest = sha256(new TextEncoder().encode(canonical(body)));
  const out = new Uint8Array(tag.length + digest.length);
  out.set(tag, 0);
  out.set(digest, tag.length);
  return out;
}

const HEX32 = /^[0-9a-f]{64}$/;
/// A device's id: 16 hex digits, made where it is added.
export const DEVICE_ID = /^[0-9a-f]{16}$/;
const text = (v: unknown, max = 512): v is string => typeof v === "string" && v.length <= max;
const time = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
const common = (b: any): boolean => b !== null && typeof b === "object" && b.v === 1 && text(b.sub) && b.sub !== "" && text(b.ws, 64) && b.ws !== "" && typeof b.rig === "string" && HEX32.test(b.rig) && time(b.at);

/// Why `d` is no device, or null: a name, a kind, and a target of that kind (an adb serial, `host:port`, a path).
export function deviceRefusal(d: unknown): string | null {
  const o = d as Device | null;
  if (o === null || typeof o !== "object" || typeof o.id !== "string" || !DEVICE_ID.test(o.id)) return "a device has an id of 16 hex digits";
  if (!text(o.name, 80) || o.name.trim() === "") return "a device has a name, up to 80 characters";
  if (!DEVICE_KINDS.includes(o.kind)) return "kind: adb, tcp or serial";
  if (!text(o.target, 256) || o.target.trim() === "" || /[\s\0]/.test(o.target)) return "target: what it is reached at, with no spaces";
  if (o.kind === "tcp" && !/^(\[[0-9a-fA-F:.]+\]|[A-Za-z0-9.-]+):([1-9][0-9]{0,4})$/.test(o.target)) return "a tcp device's target is host:port";
  if (o.kind === "tcp" && Number(o.target.slice(o.target.lastIndexOf(":") + 1)) > 65535) return "a tcp device's port is 1 to 65535";
  if (o.kind === "serial" && !o.target.startsWith("/") && !/^COM[0-9]+$/.test(o.target)) return "a serial device's target is its path (/dev/…) or COMn";
  if (o.baud !== undefined && (!Number.isSafeInteger(o.baud) || o.baud < 50 || o.baud > 4_000_000)) return "baud: 50 to 4000000";
  return null;
}

/// Whether `signed` has the shape of a statement of `kind` (its signature is checked by who takes it).
export function wellFormed(kind: Kind, signed: unknown): boolean {
  const s = signed as Signed<any> | null;
  if (s === null || typeof s !== "object" || s.sig === null || typeof s.sig !== "object" || !text(s.sig.key, 200) || !text(s.sig.sig, 200) || !common(s.body)) return false;
  const b = s.body;
  switch (kind) {
    case "grant":
      return typeof b.station === "string" && HEX32.test(b.station) && text(b.session, 256) && b.session !== "" && text(b.chat, 256) && text(b.request, 128) && b.request !== ""
        && text(b.title) && text(b.by) && timeoutRefusal(b.timeout) === null && time(b.exp) && b.exp > b.at && b.exp - b.at <= TIMEOUT_MAX
        && (b.device === undefined || (typeof b.device === "string" && DEVICE_ID.test(b.device)));
    case "revoke":
      return text(b.request, 128) && b.request !== "";
    case "settings":
      return time(b.seq) && typeof b.open === "boolean" && (b.device === undefined || (typeof b.device === "string" && DEVICE_ID.test(b.device)));
    case "device":
      return deviceRefusal(b.device) === null && typeof b.removed === "boolean";
    case "add":
    case "full":
      return true;
  }
}

/// Until when a grant signed at `at` holds at the latest: a fixed one its length, an idle one 30 days.
export const latest = (at: number, timeout: Timeout): number => at + (timeout.kind === "fixed" ? timeout.seconds : TIMEOUT_MAX);
