// A chat's files downloaded to this device by the core (client/core-ts views/downloads.ts): asked from a preview's 下载
// or a card's ↻, fetched by the core whatever becomes of the page that asked and of the app (written down until saved);
// how far each has come said by its `downloads` topic, which the preview and the message's file read (✕ calls one
// off). Once all of one is here it is taken (`download.take`, once) whatever page shows, read off the device a part at
// a time (`keep`: not from the station again), saved as the preview's 下载 saves a file, and said done.
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
 * `active` (under way, waiting for its station, ready, being saved) or failed; null when there is none. */
export function useDownload(station: string, key: string | null, name: string): DownloadShown | null {
  return useTopicSelect<DownloadsView, DownloadShown | null>(key === null ? null : DOWNLOADS,
    (s) => s.value?.downloads.find((d) => d.station === station && d.key === key && d.name === name) ?? null);
}

/** The file a message names downloaded by the core (`size` as the message says): one under way or ready is that one, a
 * failed one starts again. How it goes is the `downloads` topic's. */
export function startDownload(station: string, key: string, name: string, size: number): void {
  core().call("download.start", { station, key, name, size }).catch(() => {});
}

/** The core's download `id`, failed (or waiting for its station), tried again now. */
export function retryDownload(id: string): void {
  core().call("download.retry", { id }).catch(() => {});
}

/** The core's download `id` called off: stopped, what was fetched of it let go. */
export function cancelDownload(id: string): void {
  core().call("download.cancel", { id }).catch(() => {});
}
