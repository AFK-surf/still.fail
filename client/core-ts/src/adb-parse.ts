// The adb share's calls by name (adb.rs `parse`).
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { StationAddr } from "./station/addr.ts";
import { get } from "./util.ts";

export const MINUTES = 60;
export const MAX_MINUTES = 8 * 60;

export type Offer = { station: string; connect: number | null; pair: number | null; device: string; android: string; package: string; minutes: number };
export type AdbCall =
  | { kind: "share"; offer: Offer }
  | { kind: "stop" }
  | { kind: "pair"; code: string; station?: string }
  | { kind: "grant"; station?: string }
  /// The ports the app found for adbd, and what the phone is: lent with them to every station a grant wants it on.
  | { kind: "ports"; ports: Omit<Offer, "station" | "minutes"> }
  /// A chat's request for this person's phone decided (`scope`: "hour" | "chat"; null refuses it), or a grant taken back.
  | { kind: "decide"; station: string; request: string; scope: "hour" | "chat" | null; chat?: string }
  | { kind: "revoke"; station: string; request: string; chat?: string }
  /// Explicitly allow one already-granted request here after this phone took back its chat.
  | { kind: "approveHere"; station: string; request: string; proof: string }
  /// The person's 默认最长授权: the longest a chat's grant of their phone may last (every station told).
  | { kind: "lasts"; lasts: "hour" | "chat" }
  /// The person's own lock (docs/personal-lock.md): this device asks to join it, types the code shown on one on it, stops
  /// asking; a device taken off; the lock pinned here left, and one begun anew.
  /// (`sub`: whose: a device may be signed in to several accounts, each with a lock of its own.)
  | { kind: "personalOpen"; sub: string }
  | { kind: "personalJoin"; sub: string }
  | { kind: "personalCode"; code: string }
  | { kind: "personalCancel" }
  | { kind: "personalRemove"; sub: string; key: string }
  | { kind: "personalForget"; sub: string }
  | { kind: "personalRestart"; sub: string }
  /// The grants made before they were signed, signed now at one go (the person asked once).
  | { kind: "personalConfirm" }
  /// This phone's 共享调试 switch: off, lent to no chat; on, until turned off (kept on the device).
  | { kind: "on"; on: boolean }
  /// Retry reading or saving the phone's local revocations without changing its sharing switch.
  | { kind: "retryRevocations" };

export function parseAdb(name: string, params: unknown): AdbCall | null {
  const text = (field: string) => {
    const v = get(params, field);
    return typeof v === "string" ? v : "";
  };
  const port = (field: string) => {
    const v = get(params, field);
    return typeof v === "number" && Number.isInteger(v) && v > 0 && v <= 65535 ? v : null;
  };
  switch (name) {
    case "adb.share": {
      const station = text("station");
      try {
        StationAddr.parse(station);
      } catch {
        throw CoreError.invalid(t("core-misc.params.missing", { field: "station" }));
      }
      const m = get(params, "minutes");
      const minutes = typeof m === "number" && Number.isInteger(m) && m >= 0 ? Math.min(Math.max(m, 1), MAX_MINUTES) : MINUTES;
      return { kind: "share", offer: { station, connect: port("connect"), pair: port("pair"), device: text("device"), android: text("android"), package: text("package"), minutes } };
    }
    case "adb.stop":
      return { kind: "stop" };
    case "adb.pair":
      return { kind: "pair", code: text("code"), ...(text("station") !== "" ? { station: text("station") } : {}) };
    case "adb.grant":
      return { kind: "grant", ...(text("station") !== "" ? { station: text("station") } : {}) };
    case "adb.setLasts": {
      const l = get(params, "lasts");
      if (l !== "hour" && l !== "chat") throw CoreError.invalid(t("core-misc.params.missing", { field: "lasts" }));
      return { kind: "lasts", lasts: l };
    }
    case "adb.on": {
      const on = get(params, "on");
      if (typeof on !== "boolean") throw CoreError.invalid(t("core-misc.params.missing", { field: "on" }));
      return { kind: "on", on };
    }
    case "adb.retryRevocations":
      return { kind: "retryRevocations" };
    case "adb.personalOpen":
      return { kind: "personalOpen", sub: text("sub") };
    case "adb.personalJoin":
      return { kind: "personalJoin", sub: text("sub") };
    case "adb.personalCode":
      return { kind: "personalCode", code: text("code") };
    case "adb.personalCancel":
      return { kind: "personalCancel" };
    case "adb.personalRemove":
      return { kind: "personalRemove", sub: text("sub"), key: text("key") };
    case "adb.personalForget":
      return { kind: "personalForget", sub: text("sub") };
    case "adb.personalRestart":
      return { kind: "personalRestart", sub: text("sub") };
    case "adb.personalConfirm":
      return { kind: "personalConfirm" };
    case "adb.ports":
      return { kind: "ports", ports: { connect: port("connect"), pair: port("pair"), device: text("device"), android: text("android"), package: text("package") } };
    case "adb.decide":
    case "adb.revoke":
    case "adb.approveHere": {
      const station = text("station");
      try {
        StationAddr.parse(station);
      } catch {
        throw CoreError.invalid(t("core-misc.params.missing", { field: "station" }));
      }
      const request = text("request");
      if (request === "") throw CoreError.invalid(t("core-misc.params.missing", { field: "request" }));
      if (name === "adb.revoke") return { kind: "revoke", station, request, ...(text("chat") !== "" ? { chat: text("chat") } : {}) };
      if (name === "adb.approveHere") {
        const proof = text("proof");
        if (!/^[0-9a-f]{64}$/.test(proof)) throw CoreError.invalid(t("core-misc.params.missing", { field: "proof" }));
        return { kind: "approveHere", station, request, proof };
      }
      const s = get(params, "scope");
      return { kind: "decide", station, request, scope: s === "hour" || s === "chat" ? s : null, ...(text("chat") !== "" ? { chat: text("chat") } : {}) };
    }
    default:
      return null;
  }
}
