// A chat's files downloaded to this device by the core (client/core-ts views/downloads.ts): asked from a preview's 下载,
// fetched by the core whatever becomes of the page that asked (the preview closed, another opened); how far each has
// come said by its `downloads` topic, which the preview and the message's card read. Once all of one is here it is
// taken (`download.take`, once) whatever page shows, read as the core keeps it on the device (`station.file` with
// `keep`: not from the station again) and saved as the preview's 下载 saves a file.
// (What saves them is the signed-in app's: chatDownloadsSaved.ts. The preview is the share page's too, which has no core.)
import { core, useTopicSelect } from "./core/react.ts";
import type { DownloadShown, DownloadsView } from "./core/shapes.ts";

export const DOWNLOADS = { topic: "downloads" } as const;

/** A blob handed to the browser to download, as the bar's link would. */
export function saveBlob(url: string, name: string) {
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
}

/** The core's download of a chat's file (its `station`, the session that keeps it, its name there) while it is listed:
 * under way, ready, or failed; null when there is none. */
export function useDownload(station: string, key: string | null, name: string): DownloadShown | null {
  return useTopicSelect<DownloadsView, DownloadShown | null>(key === null ? null : DOWNLOADS,
    (s) => s.value?.downloads.find((d) => d.station === station && d.key === key && d.name === name) ?? null);
}

/** The file a message names downloaded by the core (`size` as the message says): one under way or ready is that one, a
 * failed one starts again. How it goes is the `downloads` topic's. */
export function startDownload(station: string, key: string, name: string, size: number): void {
  core().call("download.start", { station, key, name, size }).catch(() => {});
}
