// Bring forward only the active session keys of an older store, in bounded low-priority transactions.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { workspaceActivityStep } from "../store/workspace-activity.ts";
import { recoverWaitsStep } from "../store/recover-waits.ts";
import { awakeWaitsStep } from "../store/awake-waits.ts";
import { disableSandboxIndex, enableSandboxIndex, sandboxIndexStep } from "../store/sandbox-index.ts";
import { installSessionDirectories, sessionDirectoriesStep } from "../store/session-directory.ts";
import { chatShareIndexStep, installChatShareIndex } from "../store/chat-share-index.ts";
import { installProcessJobs, processJobsStep } from "../store/process-jobs.ts";
import { activeJobUpgradeStep } from "../store/active-jobs-upgrade.ts";
import { legacySaidMaintenanceStep } from "../store/legacy-said-build.ts";
import { legacyAgentMaintenanceStep } from "../store/legacy-agent-build.ts";
import { legacyLoginCardsMaintenanceStep } from "../store/legacy-login-cards.ts";
import { legacyEditsMaintenanceStep } from "../store/legacy-edits-build.ts";
import { archivePolicyIndexStep } from "../store/archive-policy-index.ts";
import { decisionTimeIndexStep } from "../store/legacy-decision-time.ts";
import { decisionSessionIndexStep } from "../store/legacy-decision-session.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (message: { kind?: "activity" | "recovery" | "awake" | "sandbox" | "sandbox-off" | "directory" | "chat-share" | "process-jobs" | "active-jobs" | "legacy-said" | "legacy-agent" | "legacy-login" | "legacy-edits" | "legacy-policy" | "legacy-decision-time" | "legacy-decision-session" }) => {
  const kind = message.kind ?? "activity";
  let result: { done: boolean; error?: string } = { done: false };
  if (takeBackfill(priority, threadId)) {
    try {
      if (kind === "sandbox") { enableSandboxIndex(db); result = sandboxIndexStep(db); }
      else if (kind === "sandbox-off") { disableSandboxIndex(db); result = { done: true }; }
      else if (kind === "directory") { installSessionDirectories(db); result = sessionDirectoriesStep(db); }
      else if (kind === "chat-share") { installChatShareIndex(db); result = chatShareIndexStep(db); }
      else if (kind === "process-jobs") { installProcessJobs(db); result = processJobsStep(db); }
      else if (kind === "active-jobs") result = activeJobUpgradeStep(db);
      else if (kind === "legacy-said") result = legacySaidMaintenanceStep(db);
      else if (kind === "legacy-agent") result = legacyAgentMaintenanceStep(db);
      else if (kind === "legacy-login") result = legacyLoginCardsMaintenanceStep(db);
      else if (kind === "legacy-edits") result = legacyEditsMaintenanceStep(db);
      else if (kind === "legacy-policy") result = archivePolicyIndexStep(db);
      else if (kind === "legacy-decision-time") result = decisionTimeIndexStep(db);
      else if (kind === "legacy-decision-session") result = decisionSessionIndexStep(db);
      else result = kind === "recovery" ? recoverWaitsStep(db) : kind === "awake" ? awakeWaitsStep(db) : workspaceActivityStep(db);
    }
    catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
    } finally { giveBackfill(priority, threadId); }
  }
  if (!result.done && !result.error) await wall.sleep(20);
  parentPort!.postMessage({ ...result, kind });
});
