// Where something a search found opens that the wide screen and the phone open the same way (docs/search.md).
import type { SearchOpen } from "./core/shapes.ts";
import { drivePath } from "./drive/useDrive.ts";

/**
 * The drive's page (drive/useDrive.ts `drivePath`) for a place in a station's files the core says a file found opens
 * at (`SearchOpen` `files`: its folder entered, a text read, a video or song played, anything else shown in its
 * folder), under `base`, its station's pages.
 */
export function filesPath(base: string, open: SearchOpen): string {
  return drivePath(base, open.root ?? null, open.path ?? "", open.how === "read" || open.how === "play" ? open.how : "");
}
