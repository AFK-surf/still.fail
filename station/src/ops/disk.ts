// The disk of the station's data running low. Every five minutes (agents.ts `relieving`), with less than DISK_LOW_BYTES
// free, what can go goes, in this order, until there is that much again: the mirrors of other stations' tasks not in use
// (jobs/remote.ts `relieve`), then the workspaces of archived chats before their time, the longest archived first
// (sessions/lifecycle.ts `relieveArchived`). Only the mirrors went at first: ccvm, which runs no one's tasks, had none,
// and its 89G disk was down to 2.3G free with 10G of archived workspaces waiting out their week (2026-10-25).

import { statfsSync } from "node:fs";

export const DISK_LOW_BYTES = 20 * 1024 ** 3;
/// How often the station looks at its free space.
export const DISK_EVERY_MS = 5 * 60_000;

/// The bytes free for the station on the disk holding `path`.
export function diskFree(path: string): number {
  const st = statfsSync(path);
  return st.bavail * st.bsize;
}
