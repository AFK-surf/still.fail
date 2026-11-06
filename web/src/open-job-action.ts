import type { Job } from "./core/shapes.ts";

/// What the long-running row asks the core to stop, and how its progress is matched.
export function openJobAction(job: Pick<Job, "station" | "id" | "stop">): { call: string; params: Record<string, string>; word: string | null } | null {
  if (!job.station) return null;
  if (job.stop) {
    const { call, screen, view, word } = job.stop;
    if (!screen) return null;
    if (call === "screen.close") return { call, params: { station: job.station, screen }, word };
    if (call === "screen.endView" && view) return { call, params: { station: job.station, screen, view }, word };
    return null;
  }
  return { call: "job.stop", params: { station: job.station, id: job.id }, word: null };
}
