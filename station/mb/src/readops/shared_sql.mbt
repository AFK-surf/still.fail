// The statements the chat list reads by, as the TypeScript station makes them (each names where it is made there).

///|
/// store/said-state.ts SAID_LATEST.
let said_latest_sql : String =
  #|SELECT n, author_kind, author FROM entries INDEXED BY entries_said WHERE thread = ?1 AND kind = 'message' AND letter IS NULL ORDER BY n DESC LIMIT 1

///|
/// store/said-state.ts SAID_STATE.
let said_state_sql : String =
  #|SELECT s.said_n, s.said_other_n, s.said_other_known,
  #|    g.author AS guard_author, g.other_n AS guard_other_n, g.ready AS guard_ready
  #|  FROM thread_state s LEFT JOIN said_state_guard g ON g.thread = s.thread WHERE s.thread = ?1
  #|  UNION ALL SELECT NULL, NULL, NULL, g.author, g.other_n, g.ready FROM said_state_guard g
  #|    WHERE g.thread = ?1 AND NOT EXISTS (SELECT 1 FROM thread_state s WHERE s.thread = ?1) LIMIT 1

///|
/// store/said-state.ts SAID_SCAN.
let said_scan_sql : String =
  #|SELECT n, author_kind, author FROM entries INDEXED BY entries_said
  #|  WHERE thread = ?1 AND kind = 'message' AND letter IS NULL AND n < ?2 ORDER BY n DESC LIMIT ?3

///|
/// store/legacy-said-build.ts LEGACY_SAID_LATEST.
let legacy_said_latest_sql : String =
  #|WITH dirty_latest AS MATERIALIZED (
  #|    SELECT e.n,e.author_kind,e.author FROM legacy_said_meta m CROSS JOIN legacy_said_dirty d
  #|      CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
  #|    WHERE m.id=1 AND m.scanned=1 AND d.thread=?1 AND e.kind='message' AND e.letter IS NULL
  #|    ORDER BY d.n DESC LIMIT 1
  #|  )
  #|  SELECT n,author_kind,author FROM dirty_latest
  #|  UNION ALL
  #|  SELECT n,author_kind,author FROM (
  #|    SELECT s.n,s.author_kind,s.author FROM legacy_said_meta m CROSS JOIN legacy_said_build s
  #|    WHERE m.id=1 AND m.scanned=1 AND s.thread=?1
  #|      AND s.n >= COALESCE((SELECT n FROM dirty_latest), -9223372036854775808)
  #|      AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)
  #|    ORDER BY s.n DESC LIMIT 1
  #|  )
  #|  UNION ALL
  #|  SELECT n,author_kind,author FROM (
  #|    SELECT e.n,e.author_kind,e.author FROM legacy_said_meta m CROSS JOIN entries e
  #|    WHERE m.id=1 AND m.scanned=0 AND e.thread=?1 AND e.kind='message' AND e.letter IS NULL
  #|    ORDER BY e.n DESC LIMIT 1
  #|  )
  #|  ORDER BY n DESC LIMIT 1

///|
/// store/legacy-said-build.ts LEGACY_SAID_SCAN.
let legacy_said_scan_sql : String =
  #|SELECT n, author_kind, author FROM legacy_said WHERE thread = ?1 AND n < ?2 ORDER BY n DESC LIMIT ?3

///|
/// store/legacy-said-build.ts LEGACY_SAID_NEEDS_DRAIN.
let legacy_said_needs_drain_sql : String =
  #|SELECT 1 FROM legacy_said_meta m WHERE m.id=1 AND m.scanned=1 AND EXISTS (
  #|    SELECT 1 FROM legacy_said_dirty WHERE thread=?1 LIMIT 1 OFFSET 64)

///|
/// store/legacy-said-build.ts LEGACY_SAID_HEAD_FIRST.
let legacy_said_head_first_sql : String =
  #|SELECT CASE WHEN e.kind='message' AND e.letter IS NULL THEN e.n END AS n,
  #|    CASE WHEN e.kind='message' AND e.letter IS NULL THEN e.author_kind END AS author_kind,
  #|    CASE WHEN e.kind='message' AND e.letter IS NULL THEN e.author END AS author
  #|    FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT 1

///|
/// store/legacy-said-build.ts LEGACY_SAID_HEAD_TAIL.
let legacy_said_head_tail_sql : String =
  #|WITH tail AS MATERIALIZED (
  #|      SELECT n,kind,letter,author_kind,author FROM entries WHERE thread=? ORDER BY n DESC LIMIT 65
  #|    ), latest AS MATERIALIZED (
  #|      SELECT n,author_kind,author FROM tail WHERE kind='message' AND letter IS NULL ORDER BY n DESC LIMIT 1
  #|    ) SELECT (SELECT n FROM latest) AS n,(SELECT author_kind FROM latest) AS author_kind,
  #|      (SELECT author FROM latest) AS author,(SELECT COUNT(*) FROM tail) AS count

///|
/// store/legacy-said-build.ts LEGACY_SAID_BOUNDARY_TAIL.
let legacy_said_boundary_tail_sql : String =
  #|WITH tail AS MATERIALIZED (
  #|      SELECT n,kind,letter,author_kind,author FROM entries WHERE thread=?1 AND n<?2 ORDER BY n DESC LIMIT 65
  #|    ) SELECT (SELECT n FROM tail WHERE kind='message' AND letter IS NULL
  #|      AND NOT (author_kind='person' AND author=?3) ORDER BY n DESC LIMIT 1) AS n,
  #|      (SELECT COUNT(*) FROM tail) AS count

///|
/// read/store.ts ASKED_DURING.
let asked_during_sql : String =
  #|SELECT max(n) AS n FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'agent' AND at >= ? AND at <= ?

///|
/// store/legacy-agent-build.ts LEGACY_ASKED_DURING.
let legacy_asked_during_sql : String =
  #|SELECT MAX(n) AS n FROM (
  #|  SELECT e.n FROM legacy_agent_meta m CROSS JOIN entries e
  #|    WHERE m.id=1 AND m.scanned=0 AND e.thread=?1 AND e.kind='message' AND e.author_kind='agent' AND e.at>=?2 AND e.at<=?3
  #|  UNION ALL
  #|  SELECT s.n FROM legacy_agent_meta m CROSS JOIN legacy_agent_build s
  #|    WHERE m.id=1 AND m.scanned=1 AND s.thread=?1 AND s.at>=?2 AND s.at<=?3
  #|      AND NOT EXISTS (SELECT 1 FROM legacy_agent_dirty d WHERE d.thread=s.thread AND d.n=s.n)
  #|  UNION ALL
  #|  SELECT e.n FROM legacy_agent_meta m CROSS JOIN legacy_agent_times t
  #|    CROSS JOIN entries e ON e.thread=t.thread AND e.n=t.n
  #|    WHERE m.id=1 AND m.scanned=1 AND t.thread=?1 AND t.at>=?2 AND t.at<=?3
  #|      AND e.kind='message' AND e.author_kind='agent' AND e.at=t.at
  #|)

///|
/// store/legacy-closed-cards.ts CLOSED_CARDS_INDEXED.
let closed_cards_indexed_sql : String =
  #|SELECT thread,n,viewer,at,rowid AS ordering
  #|  FROM closed_cards INDEXED BY closed_cards_thread_at WHERE thread=? AND at>=?

///|
/// store/legacy-closed-cards.ts LEGACY_CLOSED_CARDS.
let legacy_closed_cards_sql : String =
  #|SELECT c.thread,c.n,c.viewer,c.at,c.rowid AS ordering
  #|  FROM legacy_closed_cards k INDEXED BY legacy_closed_by_time CROSS JOIN closed_cards c ON c.rowid=k.source_rowid
  #|  WHERE k.thread=? AND k.at>=? AND c.thread=k.thread AND c.n=k.n AND c.at=k.at

///|
/// store/legacy-closed-cards.ts CLOSED_CHAT_SAMPLE.
let closed_chat_sample_sql : String =
  #|SELECT * FROM (SELECT c.thread,CASE WHEN c.at>=?2 THEN c.n END AS n,
  #|  CASE WHEN c.at>=?2 THEN c.viewer END AS viewer,CASE WHEN c.at>=?2 THEN c.at END AS at,
  #|  CASE WHEN c.at>=?2 THEN c.rowid END AS ordering FROM closed_cards c
  #|  WHERE c.thread=?1 ORDER BY c.n LIMIT 65) ORDER BY at,ordering

///|
/// store/legacy-closed-cards.ts CLOSED_TIME_SAMPLE.
let closed_time_sample_sql : String =
  #|WITH recent AS MATERIALIZED (
  #|  SELECT thread,n,viewer,at,rowid AS ordering FROM closed_cards INDEXED BY closed_cards_at
  #|  WHERE at>=? ORDER BY at,rowid LIMIT 65
  #|), selected AS MATERIALIZED (
  #|  SELECT *,thread IN (SELECT value FROM json_each(?2)) AS wanted FROM recent
  #|)
  #|SELECT CASE WHEN wanted THEN thread END AS thread,CASE WHEN wanted THEN n END AS n,
  #|  CASE WHEN wanted THEN viewer END AS viewer,CASE WHEN wanted THEN at END AS at,
  #|  CASE WHEN wanted THEN ordering END AS ordering FROM selected

///|
/// store/legacy-people-since.ts LEGACY_HAS_PEOPLE_SINCE.
let legacy_has_people_since_sql : String =
  #|SELECT 1 FROM legacy_people_time_rows k INDEXED BY legacy_people_time_by_at
  #|  CROSS JOIN entries e ON e.rowid=k.source_rowid
  #|  WHERE k.thread=?1 AND k.at>=?2 AND e.thread=k.thread AND e.n=k.n AND e.at=k.at
  #|    AND e.kind='message' AND e.author_kind='person' LIMIT 1

///|
/// store/legacy-people-since.ts LEGACY_FIRST_PERSON_SINCE.
let legacy_first_person_since_sql : String =
  #|SELECT MIN(e.n) AS n FROM legacy_people_time_rows k INDEXED BY legacy_people_time_by_at
  #|  CROSS JOIN entries e ON e.rowid=k.source_rowid
  #|  WHERE k.thread=?1 AND k.at>=?2 AND e.thread=k.thread AND e.n=k.n AND e.at=k.at
  #|    AND e.kind='message' AND e.author_kind='person'

///|
/// store/legacy-people-since.ts LEGACY_PEOPLE_AFTER.
let legacy_people_after_sql : String =
  #|SELECT e.thread,e.n FROM legacy_people_time_rows k INDEXED BY legacy_people_time_by_at
  #|  CROSS JOIN entries e ON e.rowid=k.source_rowid
  #|  WHERE k.thread=?1 AND k.at>=?2 AND e.thread=k.thread AND e.n=k.n AND e.at=k.at
  #|    AND e.kind='message' AND e.author_kind='person' AND e.n>?3 ORDER BY e.n

///|
/// store/legacy-people-since.ts SMALL_PEOPLE_HAS.
let small_people_has_sql : String =
  #|WITH sample AS MATERIALIZED (SELECT n,kind,author_kind,at FROM entries WHERE thread=?1 ORDER BY n LIMIT 65) SELECT COUNT(*) AS seen,MAX(CASE WHEN kind='message' AND author_kind='person' AND at>=?2 THEN 1 ELSE 0 END) AS yes FROM sample

///|
/// store/legacy-people-since.ts SMALL_PEOPLE_FIRST.
let small_people_first_sql : String =
  #|WITH sample AS MATERIALIZED (SELECT n,kind,author_kind,at FROM entries WHERE thread=?1 ORDER BY n LIMIT 65) SELECT COUNT(*) AS seen,
  #|  CASE WHEN COUNT(*)<65 THEN MIN(CASE WHEN kind='message' AND author_kind='person' AND at>=?2 THEN n END) END AS n FROM sample

///|
/// store/legacy-people-since.ts SMALL_PEOPLE_AFTER.
let small_people_after_sql : String =
  #|WITH sample AS MATERIALIZED (SELECT n,kind,author_kind,at FROM entries WHERE thread=?1 ORDER BY n LIMIT 65)
  #|  SELECT ?1 AS thread,CASE WHEN (SELECT COUNT(*) FROM sample)<65 THEN n END AS n,
  #|    (SELECT COUNT(*) FROM sample) AS seen FROM sample WHERE kind='message' AND author_kind='person' AND at>=?2 AND n>?3
  #|  UNION ALL SELECT ?1,NULL,(SELECT COUNT(*) FROM sample) ORDER BY n

///|
/// read/store.ts HAS_ANSWER_PEOPLE_SINCE.
let has_answer_people_since_sql : String =
  #|SELECT 1 FROM entries INDEXED BY entries_people_since
  #|  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ? LIMIT 1

///|
/// read/store.ts FIRST_ANSWER_PERSON_SINCE.
let first_answer_person_since_sql : String =
  #|SELECT MIN(n) AS n FROM entries INDEXED BY entries_people_since
  #|  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ?

///|
/// read/store.ts ANSWER_PEOPLE_AFTER.
let answer_people_after_sql : String =
  #|SELECT thread, n FROM entries INDEXED BY entries_people_since
  #|  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ? AND n > ? ORDER BY n

///|
/// read/store.ts ANSWER_NEXT_PERSON.
let answer_next_person_sql : String =
  #|SELECT n, at FROM entries INDEXED BY entries_people_by_n
  #|  WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND n > ? ORDER BY n LIMIT 1

///|
/// store/card-post-index.ts CARD_POST_BEFORE.
let card_post_before_sql : String =
  #|SELECT MAX(n) AS n FROM card_posts WHERE thread=? AND n<?

///|
/// store/card-post-index.ts CARD_POST_NEXT.
let card_post_next_sql : String =
  #|SELECT n FROM card_posts WHERE thread=? AND n>=? ORDER BY n LIMIT 1

///|
/// store/card-post-index.ts CARD_POST_SAMPLE.
let card_post_sample_sql : String =
  #|SELECT n FROM card_posts WHERE thread=? ORDER BY n LIMIT 65

///|
/// read/store.ts SESSION_ACTIVITY.
let session_activity_sql : String =
  #|SELECT s.key, ((SELECT COUNT(*) FROM deliveries d INDEXED BY deliveries_pending WHERE d.session = s.key AND d.delivered_at IS NULL) +
  #|         (SELECT COUNT(*) FROM letter_deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL)) AS pending, l.id AS turn_id, l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.wait_watch, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at FROM sessions s
  #|     LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)

///|
/// read/store.ts WATCHING_OF.
let watching_of_sql : String =
  #|SELECT j.* FROM active_watch_jobs w INDEXED BY active_watch_jobs_session
  #|  CROSS JOIN jobs j ON j.id = w.job WHERE w.session IN (SELECT value FROM json_each(?)) ORDER BY j.started_at DESC, j.rowid

///|
/// read/store.ts WATCHING_ALL.
let watching_all_sql : String =
  #|SELECT j.* FROM active_watch_jobs w
  #|  CROSS JOIN jobs j ON j.id = w.job ORDER BY j.started_at DESC, j.rowid

///|
/// read/store.ts RUNNING_OF.
let running_of_sql : String =
  #|SELECT * FROM jobs WHERE session_key IN (SELECT value FROM json_each(?)) AND state = 'running' ORDER BY started_at DESC

///|
/// store/rows.ts JOBS_RUNNING.
let jobs_running_sql : String =
  #|SELECT * FROM jobs WHERE state = 'running' ORDER BY started_at DESC, port, rowid

///|
/// read/store.ts SHARES_OF.
let shares_of_sql : String =
  #|SELECT * FROM chat_shares WHERE session IN (SELECT value FROM json_each(?))

///|
/// read/store.ts OPENERS_OF.
let openers_of_sql : String =
  #|SELECT o.child, o.parent_station, o.parent, o.opener_title, p.title AS parent_title FROM opened_chats o LEFT JOIN sessions p ON o.parent_station = '' AND p.key = o.parent WHERE o.child_station = '' AND o.child IN (SELECT value FROM json_each(?))

///|
/// read/store.ts OPENED_OF.
let opened_of_sql : String =
  #|SELECT o.parent, o.child_station, o.child, o.title, c.title AS child_title FROM opened_chats o LEFT JOIN sessions c ON o.child_station = '' AND c.key = o.child WHERE o.parent_station = '' AND o.parent IN (SELECT value FROM json_each(?)) ORDER BY o.created_at, o.rowid

///|
/// read/store.ts SHOWN_SESSIONS.
let shown_sessions_sql : String =
  #|SELECT * FROM sessions INDEXED BY sessions_live WHERE archived_at IS NULL ORDER BY last_active_at DESC
