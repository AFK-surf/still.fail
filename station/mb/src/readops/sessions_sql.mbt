// The statements a session's summary and the session list read by, as the TypeScript station makes them.

///|
/// read/store.ts SESSION_STATS.
let session_stats_sql : String =
  #|SELECT s.key,
  #|       COALESCE((SELECT c.n FROM session_turns c WHERE c.session = s.key),
  #|         (SELECT CASE WHEN COUNT(*) <= 64 THEN COUNT(*) END FROM
  #|           (SELECT 1 FROM turns old INDEXED BY turns_by_session WHERE old.session_key = s.key LIMIT 65))) AS turns,
  #|       -- How long its turns ran, where every one ended since that was kept (schema.ts SESSION_WORK); else none.
  #|       CASE WHEN NOT EXISTS (SELECT 1 FROM turns o INDEXED BY turns_by_end WHERE o.session_key = s.key AND o.ended_at <= (SELECT f.at FROM session_work_from f WHERE f.id = 1))
  #|         THEN COALESCE((SELECT w.ms FROM session_work w WHERE w.session = s.key), 0) END AS work_ms,
  #|       ((SELECT COUNT(*) FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = s.key AND d.delivered_at IS NULL) +
  #|         (SELECT COUNT(*) FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)) AS pending,
  #|       (SELECT substr(m.text, 1, 300) FROM session_first f JOIN merged m ON m.thread = f.thread AND m.n = f.n WHERE f.session = s.key) AS first_text,
  #|       l.id AS turn_id, l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at
  #|     FROM sessions s
  #|     LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)

///|
/// store/session-list-index.ts SESSION_LIST_CONNECT.
let session_list_connect_sql : String =
  #|SELECT s.* FROM session_list_rows i INDEXED BY session_list_connect
  #|  CROSS JOIN sessions s ON s.key = i.session WHERE i.archived = ?1 AND i.connect = ?2
  #|  ORDER BY s.last_active_at DESC, s.rowid ASC

///|
/// store/session-list-index.ts SESSION_LIST_SCOPE.
let session_list_scope_sql : String =
  #|WITH scope(kind, ws) AS (SELECT 1, ?1 UNION ALL SELECT 0, '' WHERE ?2)
  #|  SELECT s.* FROM scope w CROSS JOIN session_list_rows i
  #|  CROSS JOIN sessions s ON s.key = i.session
  #|  WHERE i.kind = w.kind AND i.ws = w.ws AND i.archived = ?3
  #|  ORDER BY s.last_active_at DESC, s.rowid ASC

///|
/// store/session-list-index.ts SESSION_LIST_SCOPE_CONNECT.
let session_list_scope_connect_sql : String =
  #|WITH scope(kind, ws) AS (SELECT 1, ?1 UNION ALL SELECT 0, '' WHERE ?2)
  #|  SELECT s.* FROM scope w CROSS JOIN session_list_rows i
  #|  CROSS JOIN sessions s ON s.key = i.session
  #|  WHERE i.kind = w.kind AND i.ws = w.ws AND i.archived = ?3 AND i.connect = ?4
  #|  ORDER BY s.last_active_at DESC, s.rowid ASC

///|
/// store/session-bindings-index.ts SESSION_BINDINGS_SELECTED.
let session_bindings_selected_sql : String =
  #|SELECT i.session, i.connect FROM json_each(?) k
  #|  CROSS JOIN session_binding_rows i WHERE i.session = k.value ORDER BY i.binding_rowid

///|
/// store/rows.ts PEOPLE_AT.
let people_at_sql : String =
  #|SELECT p.author, e.at FROM thread_people p JOIN entries e ON e.thread = p.thread AND e.n = p.first_n WHERE p.thread = ?
