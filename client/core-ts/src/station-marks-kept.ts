// What the device keeps of its workspaces' stations' names and marks as the stations keep them (views/station-marks.ts
// reads and changes them), and how they are laid over still.fail cloud's list of the stations: apart, so the sync that
// writes the cloud's list (sync/cloud.ts) lays them over it as it writes.
import { isObject } from "./util.ts";

/// A station's name and mark as it keeps them: `emoji` and `icon` "" where it has none, `at` its station's clock.
export type StationMark = { name: string; emoji: string; icon: string; at: number };

/// What a station answered as a record; null when it is none.
export function markOf(raw: unknown): StationMark | null {
  if (!isObject(raw) || typeof raw.name !== "string" || raw.name === "" || typeof raw.at !== "number") return null;
  return { name: raw.name, emoji: typeof raw.emoji === "string" ? raw.emoji : "", icon: typeof raw.icon === "string" ? raw.icon : "", at: raw.at };
}

/// The records kept on the device for `ws`'s stations, by station id.
export function keptMarks(data: { record(table: string, key: string): unknown }, ws: string): Record<string, StationMark> {
  const raw = data.record("stationMarks", ws);
  const out: Record<string, StationMark> = {};
  if (isObject(raw)) for (const [id, r] of Object.entries(raw)) {
    const m = markOf(r);
    if (m !== null) out[id] = m;
  }
  return out;
}

/// `view` (a workspace as still.fail cloud gives it) with its stations' names and marks as `marks` say: the same object
/// where none differs.
export function overlaid(view: unknown, marks: Record<string, StationMark>): unknown {
  if (!isObject(view) || !Array.isArray(view.stations) || Object.keys(marks).length === 0) return view;
  let changed = false;
  const stations = view.stations.map((s) => {
    const id = isObject(s) && typeof s.id === "string" ? s.id : null;
    const m = id === null ? undefined : marks[id];
    if (m === undefined || !isObject(s)) return s;
    if (s.name === m.name && (s.emoji ?? "") === m.emoji && (s.icon ?? "") === m.icon) return s;
    changed = true;
    const { emoji: _e, icon: _i, ...rest } = s;
    return { ...rest, name: m.name, ...(m.emoji ? { emoji: m.emoji } : {}), ...(m.icon ? { icon: m.icon } : {}) };
  });
  return changed ? { ...view, stations } : view;
}

