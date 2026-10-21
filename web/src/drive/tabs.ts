// The files' page's tabs kept on this device (./tabsModel.ts: what they hold and what is done to them), among the prefs
// (`filesTabs`, by workspace, as the page writes it), and a pane's address.
import { useMemo } from "react";
import { setPrefs, usePrefs } from "../prefs.ts";
import { drivePath } from "./useDrive.ts";
import { stationBase } from "../station.tsx";
import { frontOf, readTabs, type FilesTabs, type Pane } from "./tabsModel.ts";

export * from "./tabsModel.ts";

/** The page's address for a pane. */
export const paneUrl = (p: Pane, what: "" | "read" | "play" = "") => drivePath(stationBase(p.station), p.root, p.path, what);

/** The workspace's tabs as kept, and how to keep new ones. */
export function useFilesTabs(workspace: string): [FilesTabs | null, (next: FilesTabs) => void] {
  const raw = usePrefs((p) => p.filesTabs[workspace]);
  const s = useMemo(() => readTabs(raw), [raw]);
  return [s, (next) => setPrefs({ filesTabs: { [workspace]: JSON.stringify(next) } })];
}

/** Where the files' page opens in a workspace: the folder in front as it was left, if any. */
export function keptFront(raw: string | undefined): Pane | null {
  const s = readTabs(raw);
  return s ? frontOf(s) : null;
}

