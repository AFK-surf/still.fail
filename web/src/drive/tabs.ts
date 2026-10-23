// The files' page's tabs, as the core keeps them on this device (its `filesTabs` topic and `files.tabs`;
// client/core-ts/src/drive-browse.ts has what they hold and what is done to them), and a pane's address.
import { useCall, useTopic } from "../core/react.ts";
import type { FilesPane, FilesTabsView } from "../core/shapes.ts";
import { drivePath } from "./useDrive.ts";
import { stationBase } from "../station.tsx";

/** One side of a tab: a folder of a station (its address), by one of its roots and a path under it. */
export type Pane = FilesPane;

/** What is done to the tabs (`files.tabs`'s `act`, with what it takes). */
export type TabsAct = { act: "arrive" | "open" | "besides"; pane: Pane } | { act: "close" | "show"; id: string } | { act: "split"; pane?: Pane } | { act: "front"; side: number };

/** The page's address for a pane. */
export const paneUrl = (p: Pane, what: "" | "read" | "play" = "") => drivePath(stationBase(p.station), p.root, p.path, what);

/** The workspace's tabs as kept (undefined until the core says, null before any), and what is done to them: answered
 * with the tabs after it. */
export function useFilesTabs(workspace: string): [FilesTabsView | null | undefined, (act: TabsAct) => Promise<FilesTabsView | null>] {
  const kept = useTopic<FilesTabsView | null>({ topic: "filesTabs", workspace });
  const call = useCall();
  return [kept.loading ? undefined : kept.value ?? null, (act) => call("files.tabs", { workspace, ...act }) as Promise<FilesTabsView | null>];
}
