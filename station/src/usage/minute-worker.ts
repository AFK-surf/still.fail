// Check the coverage of statistics on a read-only connection. Old records are not rebuilt in the background.
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import { usageDetailReady } from "../store/usage-detail.ts";
import { retiredUsage } from "../store/usage-retire.ts";
import { usageChatStatsReady } from "../store/usage-chat-stats.ts";
import type { MinuteRequest, MinuteResponse } from "./minute-reader.ts";

const db = new DatabaseSync(workerData.path as string, { readOnly: true });
const installed = (name: string) => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name) !== undefined;
const minutesReady = () => !installed("usage_minute_all") ||
  (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number } | undefined)?.done === 1;
const remoteReady = () => !installed("remote_run_progress") ||
  (db.prepare("SELECT done FROM remote_run_progress WHERE id = 1").get() as { done: number } | undefined)?.done === 1;
const detailReady = (viewer: Parameters<typeof usageDetailReady>[1]) => !retiredUsage(db) && (!installed("usage_detail_all") || usageDetailReady(db, viewer));
const chatsReady = (viewer: Parameters<typeof usageChatStatsReady>[1]) => !installed("usage_chat_progress") || usageChatStatsReady(db, viewer);

parentPort!.on("message", (request: MinuteRequest) => {
  try {
    const ready = "viewer" in request ? minutesReady()
      : "detail" in request ? detailReady(request.detail)
      : "chats" in request ? chatsReady(request.chats) : remoteReady();
    const name = "viewer" in request ? "minute" : "detail" in request ? "detail"
      : "chats" in request ? "chat and card" : "remote task";
    parentPort!.postMessage({ id: request.id, ...(!ready ? { error: `historical ${name} statistics are unavailable` } : {}) } satisfies MinuteResponse);
  } catch (error) {
    parentPort!.postMessage({ id: request.id, error: (error as Error).message } satisfies MinuteResponse);
  }
});

// Once every statistic is complete there is no need to keep this worker. A later workspace move starts it again.
if (minutesReady() && remoteReady() && detailReady(null) && chatsReady(null)) {
  parentPort!.postMessage({ complete: true } satisfies MinuteResponse);
}
