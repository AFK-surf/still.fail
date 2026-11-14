// The statements the open jobs read by, as the TypeScript station makes them.

///|
/// read/store.ts HAS_NAMING_ORIGIN.
let has_naming_origin_sql : String =
  #|SELECT 1 FROM thread_sessions origin
  #|  CROSS JOIN threads t ON t.id = origin.thread
  #|  WHERE origin.session = ?1 AND t.surface IS NOT ?2 AND EXISTS (
  #|    SELECT 1 FROM thread_sessions member
  #|    CROSS JOIN sessions live ON live.key = member.session
  #|    WHERE member.thread = t.id
  #|  ) LIMIT 1

///|
/// read/store.ts HAS_NAMING_ORIGIN_PREPARED.
let has_naming_origin_prepared_sql : String =
  #|SELECT 1 FROM cc_session_rows INDEXED BY cc_session_order
  #|  WHERE session = ?1 AND surface != 'ember' LIMIT 1

///|
/// read/store.ts HAS_NAMING_ORIGIN_POSSIBLE.
let has_naming_origin_possible_sql : String =
  #|SELECT 1 FROM cc_sessions c CROSS JOIN sessions live ON live.key = c.session
  #|      WHERE c.session = ?1 AND c.complete = 1 AND EXISTS (
  #|        SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session WHERE session = c.session LIMIT 1 OFFSET 8
  #|      )

///|
/// read/store.ts LATEST_NAMING_ORIGIN.
let latest_naming_origin_sql : String =
  #|SELECT (SELECT t.id FROM thread_sessions m
  #|  CROSS JOIN threads t ON t.id = m.thread
  #|  LEFT JOIN thread_state st ON st.thread = t.id
  #|  LEFT JOIN entries e ON e.thread = t.id AND e.n = st.said_n AND e.kind = 'message'
  #|  WHERE m.session = requested.value AND t.surface IS NOT ?2 AND EXISTS (
  #|    SELECT 1 FROM thread_sessions member CROSS JOIN sessions live ON live.key = member.session
  #|    WHERE member.thread = t.id
  #|  ) ORDER BY COALESCE(e.at, 0) DESC, t.created_at DESC, t.id DESC LIMIT 1) AS id
  #|  FROM json_each(?1) requested

///|
/// read/store.ts LATEST_NAMING_ORIGIN_POSSIBLE.
let latest_naming_origin_possible_sql : String =
  #|SELECT requested.key AS ordinal FROM json_each(?1) requested
  #|  CROSS JOIN cc_sessions c ON c.session=requested.value CROSS JOIN sessions live ON live.key=c.session
  #|  WHERE c.complete=1 AND EXISTS (SELECT 1 FROM thread_sessions INDEXED BY thread_sessions_session
  #|    WHERE session=c.session LIMIT 1 OFFSET 8)

///|
/// read/store.ts LATEST_NAMING_ORIGIN_PREPARED.
let latest_naming_origin_prepared_sql : String =
  #|WITH candidates AS MATERIALIZED (
  #|    SELECT thread FROM cc_session_rows INDEXED BY cc_session_order
  #|    WHERE session=?1 AND surface != 'ember' LIMIT 9
  #|  ) SELECT (SELECT COUNT(*) FROM candidates) AS count,
  #|    CASE WHEN (SELECT COUNT(*) FROM candidates)<9 THEN (SELECT t.id FROM candidates r
  #|      CROSS JOIN threads t ON t.id=r.thread LEFT JOIN thread_state st ON st.thread=t.id
  #|      LEFT JOIN entries e ON e.thread=t.id AND e.n=st.said_n AND e.kind='message'
  #|      ORDER BY COALESCE(e.at,0) DESC,t.created_at DESC,t.id DESC LIMIT 1) END AS id

///|
/// store/job-name-first.ts JOB_NAME_FIRST_LARGE.
let job_name_first_large_sql : String =
  #|SELECT 1 FROM thread_sessions WHERE thread=? LIMIT 1 OFFSET 64

///|
/// store/job-name-first.ts JOB_NAME_FIRST_ROW.
let job_name_first_row_sql : String =
  #|SELECT m.* FROM thread_sessions m WHERE m.rowid=(SELECT best FROM job_name_first
  #|  WHERE owner=?1 AND thread=?2 AND ready=1 AND restart=0)

///|
/// store/workspace-up-jobs.ts WORKSPACE_UP_JOBS.
let workspace_up_jobs_sql : String =
  #|WITH wanted AS (
  #|  SELECT session FROM workspace_up_sessions INDEXED BY workspace_up_sessions_scope WHERE scope=0 AND ws=?1
  #|  UNION ALL SELECT session FROM workspace_up_sessions INDEXED BY workspace_up_sessions_scope WHERE scope=1 AND ws='' AND ?2
  #|  UNION ALL SELECT session FROM workspace_up_sessions INDEXED BY workspace_up_sessions_scope WHERE scope=2 AND ws=''
  #|) SELECT j.* FROM wanted w CROSS JOIN session_up_job_rows u ON u.session=w.session
  #|  CROSS JOIN jobs j ON j.rowid=u.job_rowid
  #|  ORDER BY j.started_at DESC, (j.state <> 'running'), j.port, j.rowid

///|
/// read/store.ts JOBS_UP_IN_WORKSPACE.
let jobs_up_in_workspace_sql : String =
  #|SELECT j.* FROM jobs j LEFT JOIN sessions s ON s.key = j.session_key
  #|  WHERE j.state = 'running' AND (s.ws = ?1 OR (?2 AND s.ws IS NULL)
  #|  OR typeof(j.session_key) <> 'text' OR instr(CAST(j.session_key AS BLOB), x'00') > 0
  #|  OR j.session_key GLOB '*[^ -~]*'
  #|  OR (s.ws IS NOT NULL AND (typeof(s.ws) <> 'text' OR instr(CAST(s.ws AS BLOB), x'00') > 0
  #|    OR s.ws GLOB '*[^ -~]*')))
  #|  UNION ALL
  #|  SELECT j.* FROM jobs j LEFT JOIN sessions s ON s.key = j.session_key
  #|  WHERE j.state = 'exited' AND j.port IS NOT NULL AND (s.ws = ?1 OR (?2 AND s.ws IS NULL)
  #|  OR typeof(j.session_key) <> 'text' OR instr(CAST(j.session_key AS BLOB), x'00') > 0
  #|  OR j.session_key GLOB '*[^ -~]*'
  #|  OR (s.ws IS NOT NULL AND (typeof(s.ws) <> 'text' OR instr(CAST(s.ws AS BLOB), x'00') > 0
  #|    OR s.ws GLOB '*[^ -~]*')))
  #|  ORDER BY started_at DESC

///|
/// store/rows.ts JOBS_UP.
let jobs_up_sql : String =
  #|SELECT * FROM (SELECT * FROM jobs WHERE state = 'running' UNION ALL SELECT * FROM jobs WHERE state = 'exited' AND port IS NOT NULL) ORDER BY started_at DESC

///|
/// store/cc-thread-index.ts CC_INDEX_VERSION.
let cc_index_version : Double = 1

///|
let job_name_first_pending : String = "job name first member pending: "
