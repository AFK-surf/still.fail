// The adb share's calls by name (adb.rs `parse`).
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { StationAddr } from "./station/addr.ts";
import { get } from "./util.ts";

export const MINUTES = 60;
export const MAX_MINUTES = 8 * 60;

export type Offer = { station: string; connect: number | null; pair: number | null; device: string; android: string; package: string; minutes: number };
export type AdbCall = { kind: "share"; offer: Offer } | { kind: "stop" } | { kind: "pair"; code: string } | { kind: "grant" };

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
      return { kind: "pair", code: text("code") };
    case "adb.grant":
      return { kind: "grant" };
    default:
      return null;
  }
}
