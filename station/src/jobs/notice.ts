// Automatic job notices are summaries, not another transport for full logs. Keep the original on disk and let
// the agent ask for it. In particular, a compiler's column marker may have tens of thousands of padding spaces.
import type { Json } from "../store/store.ts";

const OMITTED = " … [omitted] … ";

/// A bounded excerpt, keeping both ends of a long line and the most recent lines of a long log. Only the summary
/// is changed; tool reads and the saved log retain their original contents. Limits count Unicode code points.
export function noticeExcerpt(text: string, limit = 4096): string {
  const lines = text.split("\n").map((line) => {
    const compact = line.replace(/[ \t]{65,}/g, (s) => ` [${s.length} spaces/tabs omitted] `);
    const chars = Array.from(compact);
    return chars.length <= 512 ? compact : chars.slice(0, 240).join("") + OMITTED + chars.slice(-240).join("");
  });
  const chars = Array.from(lines.join("\n"));
  return chars.length <= limit ? chars.join("") : "[Earlier output omitted]\n" + chars.slice(-(limit - 25)).join("");
}

/// The completion path shares this with local jobs; the remote result may also contain an arbitrarily long
/// command, queue description, notices or artifact list, so never embed that result wholesale in a prompt.
export function remoteNotice(key: string, station: string, result: Json): string {
  const job = result?.job;
  const status = JSON.stringify({ state: job?.state ?? null, exitCode: job?.exitCode ?? null });
  const parts = [`Remote task ${noticeExcerpt(key, 512)} on ${noticeExcerpt(station, 512)}: ${status}`];
  if (result?.back !== undefined) parts.push(`Returned files: ${noticeExcerpt(JSON.stringify(result.back), 1536)}`);
  if (Array.isArray(result?.notices) && result.notices.length > 0) {
    parts.push(`Task notices: ${noticeExcerpt(JSON.stringify(result.notices), 1536)}`);
  }
  if (typeof result?.log === "string" && result.log !== "") parts.push(`Log tail (excerpt):\n${noticeExcerpt(result.log)}`);
  parts.push(`For details use station_task with station=${JSON.stringify(station)}, key=${JSON.stringify(key)}, action=get or log. The original log is kept on the task's station.`);
  return parts.join("\n");
}
