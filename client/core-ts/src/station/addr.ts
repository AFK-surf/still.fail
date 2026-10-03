// A station's address, `"<workspace>/<station>"` (station.rs `StationAddr`).
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";

export class StationAddr {
  readonly workspace: string;
  readonly station: string;
  constructor(workspace: string, station: string) {
    this.workspace = workspace;
    this.station = station;
  }

  static parse(text: string): StationAddr {
    // What a station's own page (gone) was: still in UIs' kept links and prefs.
    if (text === "local") throw new CoreError("gone", t("station.core.localGone"));
    const at = text.indexOf("/");
    if (at > 0) {
      const workspace = text.slice(0, at);
      const station = text.slice(at + 1);
      if (station !== "" && !station.includes("/")) return new StationAddr(workspace, station);
    }
    throw CoreError.invalid(t("station.core.badAddress", { address: text }));
  }

  toString(): string {
    return `${this.workspace}/${this.station}`;
  }
}

/// A station's id in its address.
export function stationId(address: string): string {
  const at = address.lastIndexOf("/");
  return at >= 0 ? address.slice(at + 1) : address;
}
