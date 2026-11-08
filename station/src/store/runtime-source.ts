import type { SQLInputValue } from "node:sqlite";
import type { Json } from "./rows.ts";

export type RuntimeSource = { id: string; runtime: string; profile: string | null };

/// The source whose JavaScript id is `id`, as the ordered source reader would return it. A reader may decode distinct
/// NUL-suffixed ids alike, so detect those by their indexed byte range and use the original reader for that case.
export function findRuntimeSource(key: string, id: string, one: (sql: string, ...args: SQLInputValue[]) => Json | undefined,
  original: () => RuntimeSource | null): RuntimeSource | null {
  const safe = (value: unknown): value is string => typeof value === "string" && !value.includes("\0") && !value.includes("\ufffd")
    && Buffer.from(value, "utf8").toString("utf8") === value;
  if (!safe(id)) return original();
  const prefix = Buffer.from(id, "utf8");
  const lower = Buffer.concat([prefix, Buffer.from([0])]), upper = Buffer.concat([prefix, Buffer.from([1])]);
  let row: Json | undefined;
  try {
    row = one(`SELECT s.runtime_session_id AS current_id, s.runtime AS session_runtime, s.profile AS session_profile,
      r.id AS source_id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS source_runtime, r.profile AS source_profile,
      EXISTS (SELECT 1 FROM runtime_sessions x WHERE x.session_key = s.key
        AND x.id >= CAST(?3 AS TEXT) AND x.id < CAST(?4 AS TEXT)) AS ambiguous
      FROM sessions s LEFT JOIN runtime_sessions r ON r.session_key = s.key AND r.id = ?2 WHERE s.key = ?1`, key, id, lower, upper);
  } catch { return original(); } // An old database uses the original reader's fallbacks.
  if (row === undefined) return null;
  if (row.ambiguous || (row.current_id !== null && !safe(row.current_id))) return original();
  if (row.source_id !== null) {
    if (row.source_id !== id) return original();
    return { id: row.source_id, runtime: row.source_runtime, profile: row.source_profile ?? null };
  }
  return row.current_id === id ? { id, runtime: row.session_runtime, profile: row.session_profile } : null;
}
