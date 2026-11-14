// The statements a session's page and the threads read by, as the TypeScript station makes them.

///|
/// read/store.ts UNREAD.
let unread_sql : String =
  #|SELECT COUNT(*) AS c FROM entries WHERE thread = ?1 AND n > ?2 AND kind = 'message' AND letter IS NULL
  #|  AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?3)))

///|
/// read/store.ts HAS_UNREAD.
let has_unread_sql : String =
  #|SELECT EXISTS (SELECT 1 FROM entries WHERE thread = ?1 AND n > ?2 AND kind = 'message' AND letter IS NULL
  #|  AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?3)))) AS c

///|
/// store/legacy-said-build.ts LEGACY_UNREAD.
let legacy_unread_sql : String =
  #|SELECT CASE WHEN (SELECT scanned FROM legacy_said_meta WHERE id=1)=0 THEN
  #|  (SELECT COUNT(*) FROM entries e WHERE e.thread=?1 AND e.n>?2 AND e.kind='message' AND e.letter IS NULL AND NOT (e.author_kind='person' AND e.author IN (SELECT value FROM json_each(?3))))
  #|  ELSE
  #|  (SELECT COUNT(*) FROM legacy_said_build s WHERE s.thread=?1 AND s.n>?2 AND NOT (s.author_kind='person' AND s.author IN (SELECT value FROM json_each(?3))))
  #|  - (SELECT COUNT(*) FROM legacy_said_dirty d CROSS JOIN legacy_said_build s ON s.thread=d.thread AND s.n=d.n
  #|      WHERE d.thread=?1 AND d.n>?2 AND NOT (s.author_kind='person' AND s.author IN (SELECT value FROM json_each(?3))))
  #|  + (SELECT COUNT(*) FROM legacy_said_dirty d CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
  #|      WHERE d.thread=?1 AND d.n>?2 AND e.kind='message' AND e.letter IS NULL AND NOT (e.author_kind='person' AND e.author IN (SELECT value FROM json_each(?3)))) END AS c

///|
/// store/cc-thread-index.ts CC_SESSION_KEYS.
let cc_session_keys_sql : String =
  #|SELECT CAST(thread AS TEXT) AS thread FROM cc_session_rows INDEXED BY cc_session_order
  #|  WHERE session=?1 AND surface != 'ember' ORDER BY last_at DESC,created_at DESC,cc_session_rows.thread DESC LIMIT 20

///|
/// store/cc-thread-index.ts CC_INDEXED_THREADS.
let cc_indexed_threads_sql : String =
  #|SELECT t.*,o.connect FROM json_each(?1) c
  #|  CROSS JOIN threads t ON t.id=CAST(json_extract(c.value,'$[0]') AS INTEGER)
  #|  CROSS JOIN thread_sessions o ON o.thread=t.id AND o.session=json_extract(c.value,'$[1]')
  #|  WHERE t.surface != 'ember'
  #|  ORDER BY (SELECT e.at FROM thread_state st JOIN entries e ON e.thread=st.thread AND e.n=st.last_n
  #|    WHERE st.thread=t.id) DESC, t.created_at DESC, t.id DESC LIMIT 20

///|
/// read/store.ts LATEST_TURNS.
let latest_turns_sql : String =
  #|SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT ?

///|
/// read/store.ts LATEST_JOBS.
let latest_jobs_sql : String =
  #|SELECT * FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? ORDER BY rowid DESC LIMIT ?

///|
/// read/store.ts UP_JOBS_OF.
let up_jobs_of_sql : String =
  #|SELECT * FROM jobs INDEXED BY jobs_up WHERE state = 'running' AND session_key = ?1 UNION ALL SELECT * FROM jobs INDEXED BY jobs_up WHERE state = 'exited' AND port IS NOT NULL AND session_key = ?1

///|
/// read/store.ts PREPARED_UP_JOBS_OF.
let prepared_up_jobs_of_sql : String =
  #|SELECT j.* FROM session_up_job_rows i CROSS JOIN jobs j ON j.rowid = i.job_rowid
  #|  WHERE i.session = ? ORDER BY (j.state <> 'running'), j.port, j.rowid

///|
/// store/rows.ts SESSION_JOBS.
let session_jobs_sql : String =
  #|SELECT * FROM jobs WHERE session_key = ? ORDER BY started_at DESC
