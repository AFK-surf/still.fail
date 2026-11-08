// The index for one home workspace. The old comma-stats.db remains the Router's compatibility record; its index has
// no owner recorded and therefore cannot safely be sent after a station is enrolled in a different workspace.
import { CommaStats, type Read } from "./stats.ts";
import type { CommaIndexes } from "./surface.ts";

export function homeIndex(data: string, workspace: string, home: () => string | null, version: () => number,
  read: Read, changes: (changed: () => void) => () => void): { stats: CommaStats; indexes: CommaIndexes } {
  const guarded: Read = async (from, to) => {
    const at = version();
    const valid = () => home() === workspace && version() === at;
    if (!valid()) return { stations: [], unread: [], valid };
    const result = await read(from, to);
    return { ...result, valid: () => valid() && (result.valid?.() ?? true) };
  };
  const stats = CommaStats.inWorkspace(data, workspace, guarded,
    (changed) => changes(() => { if (home() === workspace) changed(); }));
  let started: number | null = null;
  return {
    stats,
    indexes: {
      stats: stats.stats,
      tasks: stats.tasks,
      start: () => {
        const now = version();
        if (started === null) { started = now; stats.start(); }
        else if (started !== now) { started = now; stats.build(); }
      },
    },
  };
}
