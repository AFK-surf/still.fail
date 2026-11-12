// An account's database: its tables, and the migrations that bring a database to this version, in
// order, by `PRAGMA user_version`. A database a newer core wrote (its version past ours) is opened to be read only.
//
// Each table keeps the station's payload of a row as JSON (`json`), passed through as it is, so a field a station adds
// needs no migration; next to it, the columns the core finds, sorts and filters rows by, and the fields that change
// often on their own (a thread's read position), which are columns only and updated in place.
import type { Sql } from "../host.ts";

/// The version this core writes.
export const VERSION = 1;

/// Each migration takes a database from the version before it to its own (index + 1).
export const MIGRATIONS: string[] = [
  `
  CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

  -- The account's own: its /v1/me ('me'), its signed-in devices ('login_sessions'), an operator's lists ('admin/<list>').
  CREATE TABLE IF NOT EXISTS account_doc (name TEXT PRIMARY KEY, json TEXT NOT NULL, confirmed INTEGER);
  CREATE TABLE IF NOT EXISTS workspace (id TEXT PRIMARY KEY, json TEXT NOT NULL, confirmed INTEGER);

  -- A station's single answers: its overview, footprint, usage.
  CREATE TABLE IF NOT EXISTS station (
    address TEXT NOT NULL, kind TEXT NOT NULL, json TEXT NOT NULL, confirmed INTEGER,
    PRIMARY KEY (address, kind)
  );
  CREATE TABLE IF NOT EXISTS slack_app (station TEXT NOT NULL, connect TEXT NOT NULL, json TEXT NOT NULL, confirmed INTEGER, PRIMARY KEY (station, connect));

  -- Which of a station's lists have been read (an empty one is not one never read), when, and how often its rows changed.
  CREATE TABLE IF NOT EXISTS list (station TEXT NOT NULL, list TEXT NOT NULL, confirmed INTEGER, rev INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (station, list));

  -- The chats the viewer's sidebar lists (archived = 0) and the archived ones (1), as GET /chats gives them.
  -- (desk: what the 奏 page listed; no longer written, left so that an older core reading the database still can.)
  CREATE TABLE IF NOT EXISTS chat (
    station TEXT NOT NULL, id TEXT NOT NULL, archived INTEGER NOT NULL, ord REAL NOT NULL,
    thread INTEGER, session TEXT, client_key TEXT,
    last_active INTEGER NOT NULL DEFAULT 0, pinned_at INTEGER,
    unread INTEGER, mine INTEGER NOT NULL DEFAULT 0, running INTEGER NOT NULL DEFAULT 0,
    tone TEXT, asks INTEGER NOT NULL DEFAULT 0, desk INTEGER NOT NULL DEFAULT 0,
    json TEXT NOT NULL,
    PRIMARY KEY (station, archived, id)
  );
  CREATE INDEX IF NOT EXISTS chat_recent ON chat (archived, pinned_at DESC, last_active DESC);
  CREATE INDEX IF NOT EXISTS chat_ord ON chat (station, archived, ord);
  CREATE INDEX IF NOT EXISTS chat_thread ON chat (station, thread) WHERE thread IS NOT NULL;
  CREATE INDEX IF NOT EXISTS chat_session ON chat (station, session);
  CREATE INDEX IF NOT EXISTS chat_running ON chat (station) WHERE running = 1;
  CREATE INDEX IF NOT EXISTS chat_marked ON chat (station) WHERE archived = 0 AND (tone IS NOT NULL OR asks = 1);
  CREATE INDEX IF NOT EXISTS chat_desk ON chat (station) WHERE archived = 0 AND desk = 1;

  -- Agents: the summary (GET /sessions, session events), listed while not archived; the detail (GET /sessions/:key) but
  -- its threads, which are the thread rows it takes part in (thread_member).
  CREATE TABLE IF NOT EXISTS session (
    station TEXT NOT NULL, key TEXT NOT NULL, listed INTEGER NOT NULL DEFAULT 0, ord REAL NOT NULL DEFAULT 0,
    last_active INTEGER, process TEXT, connect TEXT, archived_at INTEGER, turns INTEGER,
    summary TEXT, detail TEXT,
    PRIMARY KEY (station, key)
  );
  CREATE INDEX IF NOT EXISTS session_listed ON session (station, listed, ord);

  -- Threads (GET /threads, a session's detail, thread events); last, read and unread are columns only.
  CREATE TABLE IF NOT EXISTS thread (
    station TEXT NOT NULL, id INTEGER NOT NULL, listed INTEGER NOT NULL DEFAULT 0,
    last INTEGER, read INTEGER, unread INTEGER,
    sort_at INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL DEFAULT 0,
    surface TEXT, first_member TEXT,
    json TEXT NOT NULL,
    PRIMARY KEY (station, id)
  );
  CREATE INDEX IF NOT EXISTS thread_listed ON thread (station, listed, sort_at DESC, created_at DESC, id DESC);
  CREATE INDEX IF NOT EXISTS thread_first ON thread (station, first_member);
  CREATE TABLE IF NOT EXISTS thread_member (station TEXT NOT NULL, session TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY (station, session, thread));
  CREATE INDEX IF NOT EXISTS thread_member_thread ON thread_member (station, thread);

  -- A thread's messages and a session's transcript, item by item.
  CREATE TABLE IF NOT EXISTS entry (station TEXT NOT NULL, thread INTEGER NOT NULL, n INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, thread, n)) WITHOUT ROWID;
  CREATE TABLE IF NOT EXISTS transcript (station TEXT NOT NULL, session TEXT NOT NULL, i INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, session, i)) WITHOUT ROWID;

  -- Jobs: as each is now (job events, a session's detail), open = among the station's open ones (GET /jobs, with chat).
  CREATE TABLE IF NOT EXISTS job (
    station TEXT NOT NULL, id TEXT NOT NULL, session TEXT, open INTEGER NOT NULL DEFAULT 0, ord REAL NOT NULL DEFAULT 0,
    chat TEXT, json TEXT NOT NULL,
    PRIMARY KEY (station, id)
  );
  CREATE INDEX IF NOT EXISTS job_open ON job (station, open, ord);

  -- What this device did and its station has not confirmed yet (views/local.ts), and what is being written here.
  CREATE TABLE IF NOT EXISTS outbox (station TEXT NOT NULL, thread INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, thread));
  CREATE TABLE IF NOT EXISTS pending (key TEXT PRIMARY KEY, station TEXT NOT NULL, json TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS first (station TEXT NOT NULL, session TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, session));
  CREATE TABLE IF NOT EXISTS changing (station TEXT NOT NULL, id INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, id));
  CREATE TABLE IF NOT EXISTS draft (station TEXT NOT NULL, chat TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, chat));

  -- What this device keeps of a workspace: a new chat's picks (choose.ts), chats' links (refs.ts).
  CREATE TABLE IF NOT EXISTS workspace_pref (workspace TEXT NOT NULL, key TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (workspace, key));
  `,
];

// An entry's part in what was said (`e` the entry row): whether it says something (a message, or an edit of one), the
// message it is of, when that was said (a message's own time), and its words.
const kind = (e: string) => `json_extract(${e}.json, '$.kind')`;
const SAYS = (e: string) => `(${kind(e)} = 'message' OR (${kind(e)} = 'edit' AND json_type(${e}.json, '$.target') = 'integer'))`;
const SEQ = (e: string) => `(CASE ${kind(e)} WHEN 'message' THEN ${e}.n ELSE json_extract(${e}.json, '$.target') END)`;
const AT = (e: string) => `(CASE ${kind(e)} WHEN 'message' THEN json_extract(${e}.json, '$.at') END)`;
const TEXT = (e: string) => `coalesce(CASE json_type(${e}.json, '$.text') WHEN 'text' THEN json_extract(${e}.json, '$.text') END, '')`;
// The latest words win, whichever came first (a thread's older pages are read after its newer ones).
const UPSERT = `ON CONFLICT (station, thread, seq) DO UPDATE SET
  text = CASE WHEN excluded.n >= said.n THEN excluded.text ELSE said.text END,
  n = max(said.n, excluded.n),
  at = coalesce(excluded.at, said.at)`;

/// What was said in the threads, for finding messages by their words (`said`): each message's latest text (an edit's
/// replaces it), kept by triggers on `entry`, so whatever writes entries keeps it, a core that knows nothing of it too.
/// Searched by scanning it (a few MB of words: no index, as a workspace's search builds none). Not a migration (a
/// version bump would leave an older core the database only to read): made where missing at every open, filled once
/// from the entries held.
export function ensureSaid(sql: Sql): void {
  const had = sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'said'").length > 0;
  sql.exec("BEGIN IMMEDIATE");
  try {
    sql.exec(`
      CREATE TABLE IF NOT EXISTS said (
        id INTEGER PRIMARY KEY, station TEXT NOT NULL, thread INTEGER NOT NULL, seq INTEGER NOT NULL,
        n INTEGER NOT NULL, at INTEGER, text TEXT NOT NULL,
        UNIQUE (station, thread, seq)
      );
      -- A message's edits, by the message (for when the entry its words came from goes).
      CREATE INDEX IF NOT EXISTS entry_edit ON entry (station, thread, json_extract(json, '$.target')) WHERE json_extract(json, '$.kind') = 'edit';
      CREATE TRIGGER IF NOT EXISTS said_put AFTER INSERT ON entry WHEN ${SAYS("new")}
      BEGIN
        INSERT INTO said (station, thread, seq, n, at, text) VALUES (new.station, new.thread, ${SEQ("new")}, new.n, ${AT("new")}, ${TEXT("new")})
        ${UPSERT};
      END;
      -- The entry a message's words came from gone: its words are those of what is left of it (nothing, when it went).
      CREATE TRIGGER IF NOT EXISTS said_drop AFTER DELETE ON entry WHEN ${SAYS("old")}
      BEGIN
        DELETE FROM said WHERE station = old.station AND thread = old.thread AND seq = ${SEQ("old")} AND n = old.n;
        INSERT INTO said (station, thread, seq, n, at, text)
        SELECT * FROM (
          SELECT e.station, e.thread, e.n AS seq, e.n, ${AT("e")}, ${TEXT("e")} FROM entry e
          WHERE e.station = old.station AND e.thread = old.thread AND e.n = ${SEQ("old")} AND ${kind("e")} = 'message'
          UNION ALL
          SELECT e.station, e.thread, json_extract(e.json, '$.target'), e.n, NULL, ${TEXT("e")} FROM entry e
          WHERE e.station = old.station AND e.thread = old.thread AND json_extract(e.json, '$.target') = ${SEQ("old")} AND json_extract(e.json, '$.kind') = 'edit'
        )
        WHERE NOT EXISTS (SELECT 1 FROM said WHERE station = old.station AND thread = old.thread AND seq = ${SEQ("old")})
        ORDER BY 4
        ${UPSERT};
      END;
    `);
    if (!had) {
      // Oldest first, as they came.
      sql.exec(`
        INSERT INTO said (station, thread, seq, n, at, text)
        SELECT e.station, e.thread, ${SEQ("e")}, e.n, ${AT("e")}, ${TEXT("e")} FROM entry e
        WHERE ${SAYS("e")}
        ORDER BY e.station, e.thread, e.n
        ${UPSERT};
      `);
    }
    sql.exec("COMMIT");
  } catch (e) {
    try {
      sql.exec("ROLLBACK");
    } catch {
      // Rolled back already.
    }
    throw e;
  }
  dropSaidIndex(sql);
}

/// What the chat list reads of a station's overview, the JSON `j` (views.ts #chats), as SQL: who the viewer is in Slack
/// (`slackUsers`, its strings), each connect's id, kind, connection state and Slack workspace and Feishu domain (a row's
/// signature, its menu's links there; one not an object as it is), and how many agents its station runs (`running`, its
/// state's line and the glyph's count). A field not there is null. Made by SQLite itself, so that the triggers below
/// keep it whoever writes the overview; `ORDER BY` keeps each list in its order; json() takes a subquery's answer as
/// JSON again (a scalar subquery loses that it is, and would be put in as a string). `j` is qualified by its table:
/// json_each has a hidden column `json` of its own.
export const overviewPartOf = (j: string) => `json_object(
  'running', ${j} -> '$.counts.running',
  'slackUsers', CASE WHEN json_type(${j}, '$.slackUsers') = 'array'
    THEN json((SELECT json_group_array(u.value ORDER BY u.key) FROM json_each(${j}, '$.slackUsers') AS u WHERE u.type = 'text'))
    ELSE json_array() END,
  'connects', CASE WHEN json_type(${j}, '$.connects') = 'array'
    THEN json((SELECT json_group_array(CASE c.type WHEN 'object' THEN json_object(
        'id', c.value -> '$.id',
        'kind', c.value -> '$.kind',
        'connection', CASE json_type(c.value, '$.connection') WHEN 'object'
          THEN json_object('state', c.value -> '$.connection.state', 'workspace', c.value -> '$.connection.workspace')
          ELSE c.value -> '$.connection' END,
        'feishu', CASE json_type(c.value, '$.feishu') WHEN 'object'
          THEN json_object('domain', c.value -> '$.feishu.domain')
          ELSE c.value -> '$.feishu' END)
      ELSE ${j} -> c.fullkey END ORDER BY c.key) FROM json_each(${j}, '$.connects') AS c))
    ELSE json_array() END)`;

/// What a station's row reads of its overview, the JSON `j` (views.ts rowOf, OverviewRow), as SQL: its `viewer` and
/// `counts`, its `disk` and `drive` where they are not null, each as the overview has it, one absent left out; NULL
/// where the overview is not an object. Kept apart from the chat list's part (`station_part.row`), which the list reads
/// and parses for every station of a workspace as it is first shown: the row's fields in it made that 1.4-1.7 KB a
/// station for 0.8-1.1 KB (the real-size workspace), and the list's first answer later by as much.
export const overviewRowOf = (j: string) => `CASE WHEN json_type(${j}) = 'object'
    THEN json((SELECT json_group_object(o.key, ${j} -> o.fullkey) FROM json_each(${j}) AS o
      WHERE o.key IN ('viewer', 'counts') OR (o.key IN ('disk', 'drive') AND o.type <> 'null')))
    END`;

/// What a chat's page reads of its station's overview, the JSON `j` (views.ts #chatOverview: its agents' connects,
/// `#peopleOf`, `#shown`, `#whereIn`, `#sentElsewhere`, its station's update and context), as SQL: its `connects`,
/// `disk`, `slackUsers`, `updates`, `feedback` and `context`, each as the overview has it, one absent left out; NULL
/// where the overview is not an object. Kept apart from the list's part and the row's (`station_part.chat`): a chat's
/// first answer read the whole overview of its station (25-27 KB of the real-size workspace's). Its agents' accounts
/// are not in it: each agent's own profile is read alone (overviewProfilesOf).
export const overviewChatOf = (j: string) => `CASE WHEN json_type(${j}) = 'object'
    THEN json((SELECT json_group_object(o.key, ${j} -> o.fullkey) FROM json_each(${j}) AS o
      WHERE o.key IN ('connects', 'disk', 'slackUsers', 'updates', 'feedback', 'context')))
    END`;

/// The fields of an overview a chat's page reads (overviewChatOf), for where it is made of an overview in the core (one
/// shown with what is being done to it here: data.ts overviewChat).
export const OVERVIEW_CHAT = ["connects", "disk", "slackUsers", "updates", "feedback", "context"] as const;

/// An overview's profiles (the JSON `j`), each whole, by its id, as SQL: what a chat's agent reads of the one it runs
/// on, read by its key (account.ts overviewProfile: `profiles -> '$."<id>"'`, SQLite taking that one of them), never
/// the station's every profile (13 KB of the 17 of a chat's part, #5634, for its one or two agents); `{}` where it has
/// none. A profile with no id is no agent's.
export const overviewProfilesOf = (j: string) => `CASE WHEN json_type(${j}, '$.profiles') = 'array'
    THEN json((SELECT json_group_object(p.value ->> '$.id', p.value) FROM json_each(${j}, '$.profiles') AS p
      WHERE p.type = 'object' AND json_type(p.value, '$.id') = 'text'))
    ELSE json_object() END`;

/// The stations a station took the place of, as its overview says (`copies.formerly`, its strings), the JSON `j`, as
/// SQL: what a link to a chat of one of them is taken to (views.ts `stationNow`), read of every station of a
/// workspace as a chat with links in it is made; `[]` where it says none. Kept in a column of its own
/// (`station_part.formerly`): read of the chat's part, it was 17 KB parsed a station for these few bytes.
export const overviewFormerlyOf = (j: string) => `CASE WHEN json_type(${j}, '$.copies.formerly') = 'array'
    THEN json((SELECT json_group_array(f.value ORDER BY f.key) FROM json_each(${j}, '$.copies.formerly') AS f WHERE f.type = 'text'))
    ELSE json_array() END`;

/// What the workspace's profiles read of a station's overview, the JSON `j` (views.ts `#profilesView`: profiles.ts
/// `workspaceProfiles`, and the machines' own logins offered beside them), as SQL: its `profiles` in their order, its
/// `sharing`, its `mesh` (whether still.fail cloud reached it) and its `machineLogins`, each as the overview has it, one
/// absent left out; NULL where the overview is not an object. Kept in a column of its own (`station_part.profiled`):
/// the list read every station's whole overview and decorated a copy of it for these (15 of the 32 ms the core spent
/// after a workspace was switched to on 小屏, in Hermes on a Mac Studio, 2026-11-12).
export const overviewProfiledOf = (j: string) => `CASE WHEN json_type(${j}) = 'object'
    THEN json((SELECT json_group_object(o.key, ${j} -> o.fullkey) FROM json_each(${j}) AS o
      WHERE o.key IN ('profiles', 'sharing', 'mesh', 'machineLogins')))
    END`;

/// The fields of an overview the workspace's profiles read (overviewProfiledOf), for where they are made of an overview
/// in the core (one shown with what is being done to it here: data.ts overviewProfiled).
export const OVERVIEW_PROFILED = ["profiles", "sharing", "mesh", "machineLogins"] as const;

/// Each column of an overview's part (`station_part`) and how SQLite makes it of the overview's JSON.
export const PART_COLUMNS: [string, (j: string) => string][] = [["part", overviewPartOf], ["row", overviewRowOf], ["chat", overviewChatOf], ["formerly", overviewFormerlyOf], ["profiles", overviewProfilesOf], ["profiled", overviewProfiledOf]];
/// The revision of a column of the part (`<column>_rev`), beside it: raised by the triggers as its text changes, so that
/// a write is told what of the part changed by a few numbers, the texts not read (account.ts #overviewWritten). NULL
/// where no trigger of this core counted it (a row a core that knows nothing of them put in).
export const partRev = (column: string) => `${column}_rev`;
/// What makes each column of a station's part of the overview `j` (`address` its station, `from` what the overview is
/// read of; `key` the station as the second statement says it), the triggers' and where one is missing: the row kept in
/// place where there is one, each column's revision raised where its text is another; one put in now counted from 0.
const partPut = (j: string, address: string, from: string, key: string): [string, string] => [
  `INSERT INTO station_part (address, ${PART_COLUMNS.map(([c]) => c).join(", ")}) SELECT ${address}, ${PART_COLUMNS.map(([, of]) => of(j)).join(", ")} ${from}
        ON CONFLICT (address) DO UPDATE SET ${PART_COLUMNS.map(([c]) => `${c} = excluded.${c}, ${partRev(c)} = coalesce(station_part.${partRev(c)}, 0) + (station_part.${c} IS NOT excluded.${c})`).join(", ")}`,
  `UPDATE station_part SET ${PART_COLUMNS.map(([c]) => `${partRev(c)} = 0`).join(", ")} WHERE address = ${key} AND ${partRev(PART_COLUMNS[0][0])} IS NULL`,
];
const triggerPut = () => partPut("new.json", "new.address", "WHERE json_valid(new.json)", "new.address").map((s) => `${s};`).join("\n        ");

/// The triggers keeping each overview's part (station_part) as it changes or goes, whoever writes it, by name, as sqlite_master keeps them (no `IF NOT EXISTS`: SQLite keeps the
/// statement without it). An overview that is not JSON has none.
const overviewTriggers = (): [string, string][] => [
  ["station_part_put", `CREATE TRIGGER station_part_put AFTER INSERT ON station WHEN new.kind = 'overview'
      BEGIN
        DELETE FROM station_part WHERE address = new.address AND NOT json_valid(new.json);
        ${triggerPut()}
      END`],
  ["station_part_set", `CREATE TRIGGER station_part_set AFTER UPDATE OF json ON station WHEN new.kind = 'overview' AND old.json IS NOT new.json
      BEGIN
        DELETE FROM station_part WHERE address = new.address AND NOT json_valid(new.json);
        ${triggerPut()}
      END`],
  ["station_part_drop", `CREATE TRIGGER station_part_drop AFTER DELETE ON station WHEN old.kind = 'overview'
      BEGIN
        DELETE FROM station_part WHERE address = old.address;
      END`],
];

/// A statement as compared with sqlite_master's: its spaces and line breaks one space.
const spaced = (s: string) => s.replace(/\s+/g, " ").trim();

/// Each station's overview's part the chat list reads (overviewPartOf), what a station's row reads (overviewRowOf, its
/// own column), what a chat's page reads (overviewChatOf), the stations it took the place of (overviewFormerlyOf), its
/// profiles by id (overviewProfilesOf) and what the workspace's profiles read of it (overviewProfiledOf), each its own
/// column, beside it in a table of its own: they
/// read a few hundred bytes, or a chat's page some of the overview, not an overview of some 150 KB (nor walk its pages
/// to a column after it). Kept by triggers on `station`, as `said` is, so a core that knows nothing of it (a web page
/// still open from before, an app put back to an older one) keeps it too: nothing it holds is older than its overview.
/// Its row is kept in place as the overview is written, each column beside its revision (partRev), raised where its
/// text is another, so a write is told what changed without a text read; an older core's triggers put the row in anew,
/// its revisions none, and what reads them takes that as anything changed.
/// (What is made of an overview and kept beside it, whether this core can read it, is db/kept.ts's.) Made where missing
/// at every open, as `said`; a trigger whose statement is not this core's (an earlier core's, without a column of
/// these) made again, the columns added where they are not there, and every part made again with them; overviews
/// from before get theirs at once, SQLite reading them itself (no overview crosses to the core). An older core opening
/// the database after keeps these triggers (one before the row's: it makes its own only where they are missing), or
/// makes its own again in place of them (one since: these are not its statements), every part with them, the columns
/// it does not know left empty: what is read of one is then made of the overview by SQLite as it is read (account.ts
/// #columnText), till this core opens it again. Either reads of a part the fields it knows (its `part`, as it was).
export function ensureOverviewParts(sql: Sql): void {
  sql.exec("BEGIN IMMEDIATE");
  try {
    sql.exec(`
      CREATE TABLE IF NOT EXISTS station_part (address TEXT PRIMARY KEY, part TEXT NOT NULL, row TEXT, chat TEXT, formerly TEXT, profiles TEXT);
    `);
    const had = new Map(sql.all("SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'station'").map((r) => [String(r[0]), String(r[1])]));
    let remade = false;
    // (a table an earlier core made: the columns it has not added, every part made again with them)
    const columns = sql.all("PRAGMA table_info(station_part)").map((r) => r[1]);
    for (const [column, type] of PART_COLUMNS.flatMap(([c]) => [[c, "TEXT"], [partRev(c), "INTEGER"]])) {
      if (columns.includes(column)) continue;
      sql.exec(`ALTER TABLE station_part ADD COLUMN ${column} ${type}`);
      remade = true;
    }
    for (const [name, statement] of overviewTriggers()) {
      const was = had.get(name);
      if (was !== undefined && spaced(was) === spaced(statement)) continue;
      if (was !== undefined) {
        sql.exec(`DROP TRIGGER ${name}`);
        remade = true;
      }
      sql.exec(statement);
    }
    // (an earlier core's parts: all made again, of the overviews, by SQLite)
    if (remade) sql.exec("DELETE FROM station_part");
    // (asked first by the rows' keys alone: an overview is read only where its part is missing)
    const missing = sql.all("SELECT s.address FROM station s WHERE s.kind = 'overview' AND NOT EXISTS (SELECT 1 FROM station_part p WHERE p.address = s.address)");
    const [put, counted] = partPut("st.json", "st.address", "FROM station AS st WHERE st.address = ? AND st.kind = 'overview' AND json_valid(st.json)", "?");
    for (const [address] of missing) {
      sql.run(put, [address]);
      sql.run(counted, [address]);
    }
    sql.exec("COMMIT");
  } catch (e) {
    try {
      sql.exec("ROLLBACK");
    } catch {
      // Rolled back already.
    }
    throw e;
  }
}

/// How this core derives a chat record's columns beyond those every core writes (CHAT_COLUMNS, `state`): another number
/// whenever one of them would come out otherwise of the same record, so that rows derived before are derived again.
export const CHAT_MADE = 1;

/// The columns of a chat's record that SQLite makes of its JSON (`j`, an expression of it), as the record is put and as a
/// row another core put is derived again: whether it is hidden; its title; whether it is marked archived, and when
/// (archive.ts: the mark's `at`, else its last activity; null where that is not a number). What reads by them reads what
/// the JS reading the record would (views.ts, archive.ts, fleet.ts): list-rows.test.ts holds each to it. What only the
/// core says of a record (`state`, `watched`: what its agents do, whether one keeps watch) is the core's (Derive).
export const CHAT_COLUMNS: [name: string, of: (j: string) => string][] = [
  ["hidden", (j) => `(json_type(${j}, '$.hidden') IS 'true')`],
  ["title", (j) => `(CASE json_type(${j}, '$.title') WHEN 'text' THEN json_extract(${j}, '$.title') END)`],
  ["archived_mark", (j) => `(json_type(${j}, '$.archived') IS 'object')`],
  ["archived_at", (j) => `(CASE WHEN json_type(${j}, '$.archived') IS NOT 'object' THEN NULL
    WHEN coalesce(json_type(${j}, '$.archived.at'), 'null') = 'null' THEN (CASE WHEN json_type(${j}, '$.lastActiveAt') IN ('integer', 'real') THEN json_extract(${j}, '$.lastActiveAt') END)
    WHEN json_type(${j}, '$.archived.at') IN ('integer', 'real') THEN json_extract(${j}, '$.archived.at') END)`],
];

/// The chats each agent's session is among the agents of (its row's `agents[].key`), listed or archived: what finds the
/// chat a session takes part in without reading the station's rows (screens.ts chatOf, views.ts #ranFrom, fleet.ts).
/// Kept by triggers on `chat`, as `chat_row` is, so whoever writes a record (an older core too) keeps it.
const chatAgentsOf = (row: "new" | "old") => `INSERT OR IGNORE INTO chat_agent (station, session, archived, id)
        SELECT ${row}.station, json_extract(a.value, '$.key'), ${row}.archived, ${row}.id
        FROM json_each(CASE json_type(${row}.json, '$.agents') WHEN 'array' THEN ${row}.json ELSE '{"agents":[]}' END, '$.agents') AS a
        WHERE json_type(CASE a.type WHEN 'object' THEN a.value ELSE '{}' END, '$.key') = 'text';`;
const chatTriggers = (): [string, string][] => [
  ["chat_agent_put", `CREATE TRIGGER chat_agent_put AFTER INSERT ON chat
      BEGIN
        DELETE FROM chat_agent WHERE station = new.station AND archived = new.archived AND id = new.id;
        ${chatAgentsOf("new")}
      END`],
  ["chat_agent_set", `CREATE TRIGGER chat_agent_set AFTER UPDATE OF station, archived, id, json ON chat
      BEGIN
        DELETE FROM chat_agent WHERE station = old.station AND archived = old.archived AND id = old.id;
        ${chatAgentsOf("new")}
      END`],
  ["chat_agent_drop", `CREATE TRIGGER chat_agent_drop AFTER DELETE ON chat
      BEGIN
        DELETE FROM chat_agent WHERE station = old.station AND archived = old.archived AND id = old.id;
      END`],
  // (a record's JSON changed in place: never by this core's writer, which puts it whole; by another core, its columns
  // made of it again at once, and it marked to be derived again at the next open)
  ["chat_made_set", `CREATE TRIGGER chat_made_set AFTER UPDATE OF json ON chat
      BEGIN
        UPDATE chat SET made = NULL, ${CHAT_COLUMNS.map(([c, of]) => `${c} = ${of("new.json")}`).join(", ")} WHERE rowid = new.rowid;
      END`],
];

/// What deriving a database's chat columns again took at its open (ensureChatColumns): the rows SQLite derived, those
/// whose JSON was read here (`state`), the bytes of that JSON. Zero where nothing was to be derived.
export type ChatColumnsMade = { rows: number; read: number; bytes: number };

/// The columns of a chat's record that only this core can say (`state`, `watched`: through Derive) or that SQLite
/// makes of its JSON (CHAT_COLUMNS), each row marked with the derivation it was made by (`made`, CHAT_MADE), and the
/// chats each session takes part in (`chat_agent`). This core's writer puts them with every record (account.ts
/// #putChatRow). An older core's write puts its own columns only, `made` left NULL; and every core opens its database
/// alone (locking_mode EXCLUSIVE, every host), so what an older core wrote is all there before this one reads anything:
/// at every open the rows whose `made` is not CHAT_MADE are derived again, SQLite making its columns itself (no JSON
/// crosses to the core for them), the core reading only those rows' agents for `state` and `watched` (present.rowState
/// and present.watches read no more). Whether there are any is asked of
/// the index on `made` alone. `chat_agent` is kept by triggers (SQL says all of it), made again whole where a trigger
/// was missing or not this core's. Made where missing at every open, as `said`.
export function ensureChatColumns(sql: Sql, derive: (agents: unknown) => { state: string | null; watched: boolean }): ChatColumnsMade {
  sql.exec("BEGIN IMMEDIATE");
  try {
    const has = new Set(sql.all("PRAGMA table_info(chat)").map((r) => String(r[1])));
    for (const column of ["state", "watched", "made", ...CHAT_COLUMNS.map(([c]) => c)]) if (!has.has(column)) sql.exec(`ALTER TABLE chat ADD COLUMN ${column}`);
    // The indexes the declared reads are found by (chat-reads.ts; chat-plans.test.ts holds each read's plan to its
    // bound): `chat_listed` the window's counts and the chats at work, of it alone; `chat_marks` the marked rows, of it
    // alone (in the place of `chat_marked`, which held their stations only; `chat_running` and `chat_desk`, which no read
    // reads any more, go: each cost every write); `chat_client` a chat by the key it was
    // asked for here by; `chat_archive` the archive's newest in its order, across stations; `chat_archived_at` the
    // archive's counts, of it alone. Partial, each holds only the rows its reads are of; one read of an index alone has
    // every column its statement names in it, those of the index's own WHERE too (SQLite takes it as covering only so),
    // and is searched by more terms than `chat_ord` (`chat_archived_at`'s `archived_mark`: else the device's SQLite
    // took `chat_ord`, and the table's rows).
    sql.exec(`
      CREATE INDEX IF NOT EXISTS chat_made ON chat (made);
      CREATE INDEX IF NOT EXISTS chat_archived_at ON chat (station, archived, archived_mark, archived_at DESC, thread, session) WHERE archived_mark = 1;
      CREATE INDEX IF NOT EXISTS chat_archive ON chat (archived, coalesce(archived_at, 0) DESC) WHERE archived_mark = 1;
      CREATE INDEX IF NOT EXISTS chat_listed ON chat (station, archived, state, mine, hidden, watched, last_active, thread, session, id) WHERE archived = 0;
      CREATE INDEX IF NOT EXISTS chat_marks ON chat (station, archived, id, tone, asks) WHERE archived = 0 AND (tone IS NOT NULL OR asks = 1);
      DROP INDEX IF EXISTS chat_marked;
      DROP INDEX IF EXISTS chat_running;
      DROP INDEX IF EXISTS chat_desk;
      CREATE INDEX IF NOT EXISTS chat_client ON chat (station, client_key) WHERE client_key IS NOT NULL;
      CREATE TABLE IF NOT EXISTS chat_agent (station TEXT NOT NULL, session TEXT NOT NULL, archived INTEGER NOT NULL, id TEXT NOT NULL, PRIMARY KEY (station, session, archived, id)) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS chat_agent_row ON chat_agent (station, archived, id);
    `);
    const had = new Map(sql.all("SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'chat'").map((r) => [String(r[0]), String(r[1])]));
    let remade = false;
    for (const [name, statement] of chatTriggers()) {
      const was = had.get(name);
      if (was !== undefined && spaced(was) === spaced(statement)) continue;
      if (was !== undefined) sql.exec(`DROP TRIGGER ${name}`);
      sql.exec(statement);
      remade = true;
    }
    if (remade) {
      sql.exec("DELETE FROM chat_agent");
      sql.exec(`INSERT OR IGNORE INTO chat_agent (station, session, archived, id)
        SELECT c.station, json_extract(a.value, '$.key'), c.archived, c.id
        FROM chat AS c, json_each(CASE json_type(c.json, '$.agents') WHEN 'array' THEN c.json ELSE '{"agents":[]}' END, '$.agents') AS a
        WHERE json_type(CASE a.type WHEN 'object' THEN a.value ELSE '{}' END, '$.key') = 'text'`);
    }
    const out: ChatColumnsMade = { rows: 0, read: 0, bytes: 0 };
    // (by the index on `made` alone: no row read)
    const unmade = "made IS NULL OR made < ? OR made > ?";
    const any = sql.all(`SELECT 1 FROM chat WHERE made IS NULL UNION ALL SELECT 1 FROM chat WHERE made < ? UNION ALL SELECT 1 FROM chat WHERE made > ? LIMIT 1`, [CHAT_MADE, CHAT_MADE]).length > 0;
    if (any) {
      out.rows = sql.run(`UPDATE chat SET ${CHAT_COLUMNS.map(([c, of]) => `${c} = ${of("chat.json")}`).join(", ")} WHERE ${unmade}`, [CHAT_MADE, CHAT_MADE]);
      for (;;) {
        // (of each its agents alone, as SQLite reads them of its JSON)
        const page = sql.all(`SELECT rowid, json_extract(json, '$.agents') FROM chat WHERE ${unmade} LIMIT 256`, [CHAT_MADE, CHAT_MADE]);
        if (page.length === 0) break;
        for (const [rowid, agents] of page) {
          out.read++;
          out.bytes += typeof agents === "string" ? agents.length : 0;
          const d = derive(typeof agents === "string" ? JSON.parse(agents) : agents);
          sql.run("UPDATE chat SET state = ?, watched = ?, made = ? WHERE rowid = ?", [d.state, d.watched ? 1 : 0, CHAT_MADE, rowid as number]);
        }
      }
    }
    sql.exec("COMMIT");
    return out;
  } catch (e) {
    try {
      sql.exec("ROLLBACK");
    } catch {
      // Rolled back already.
    }
    throw e;
  }
}

/// A thread's letters (what its agents and other chats' wrote each other), item by item: their own log beside its
/// entries (the station's GET /threads/:id/letters, numbered from 1 in it). Made where missing at every open, as `said`.
export function ensureLetters(sql: Sql): void {
  sql.exec("CREATE TABLE IF NOT EXISTS letter (station TEXT NOT NULL, thread INTEGER NOT NULL, n INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (station, thread, n)) WITHOUT ROWID");
}

/// What is kept of each log (a thread's entries, `entry`; an agent's transcript, `transcript`) as the device holds
/// within its room (data.ts KEPT): when its chat was last opened here, and whether its items were let go for room.
/// Made where missing at every open, as `said`.
export function ensureKept(sql: Sql): void {
  sql.exec("CREATE TABLE IF NOT EXISTS log_use (kind TEXT NOT NULL, station TEXT NOT NULL, id TEXT NOT NULL, opened INTEGER, evicted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (kind, station, id))");
}

/// What a chat shows small (an image's thumbnail, a video's poster), kept on the device as its station sent it (base64,
/// as the calls answer it): a file sent never changes, and a chat opened again, the app started anew, shows it without
/// reading it again (on a slow link a chat of screenshots took seconds). `size`: the characters of `bytes`; `used`: when
/// it was last shown (to the day), the least lately shown let go first past FILES_KEPT (account.ts). Both ahead of
/// `bytes`, so what is counted and let go is read without the images. Made as the first is kept (account.ts).
export function ensureFilesKept(sql: Sql): void {
  sql.exec(`CREATE TABLE IF NOT EXISTS file_kept (
    station TEXT NOT NULL, session TEXT NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL, type TEXT NOT NULL,
    size INTEGER NOT NULL, used INTEGER NOT NULL, bytes TEXT NOT NULL, PRIMARY KEY (station, session, name, kind)
  ); CREATE INDEX IF NOT EXISTS file_kept_used ON file_kept (used);`);
}

/// The trees of what agents said (markdown.ts), as read here: a chat's page shows its Markdown read, and reading it is
/// a substantial part of opening a chat, so it is read once on the
/// device, not again each time the app starts. By the text's key (markdown.ts mdKey: the reading that made it, so a
/// core that reads otherwise reads afresh); `of`, the chat (`t:<thread>`) or agent (`s:<session>`) it was read for,
/// let go with it; `size` and `used` as file_kept's (the least lately shown let go first past MD_KEPT, account.ts).
/// Made as the first is kept.
export function ensureMdKept(sql: Sql): void {
  sql.exec(`CREATE TABLE IF NOT EXISTS md_kept (
    station TEXT NOT NULL, key TEXT NOT NULL, of TEXT NOT NULL, size INTEGER NOT NULL, used INTEGER NOT NULL,
    json TEXT NOT NULL, PRIMARY KEY (station, key)
  ) WITHOUT ROWID; CREATE INDEX IF NOT EXISTS md_kept_used ON md_kept (used); CREATE INDEX IF NOT EXISTS md_kept_of ON md_kept (station, of);`);
}

/// What agents said in Slack and heard from it, read from their transcripts as they are written (elsewhere.ts): kept
/// beyond the transcript's items (let go for room, they are still shown in their chats). Made where missing at every
/// open, as `said`; answers whether it was made now (to be filled from the transcripts held).
export function ensureSlackSaid(sql: Sql): boolean {
  const had = sql.all("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'slack_said'").length > 0;
  sql.exec(`CREATE TABLE IF NOT EXISTS slack_said (
    station TEXT NOT NULL, session TEXT NOT NULL, i INTEGER NOT NULL, k INTEGER NOT NULL, out INTEGER NOT NULL, call TEXT,
    user TEXT, who TEXT, at INTEGER NOT NULL, dest TEXT NOT NULL, text TEXT NOT NULL, failed INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (station, session, i, k)
  )`);
  return !had;
}

/// The full-text index an earlier core kept of `said` (`said_index`, FTS5) taken away: a row's words went from it only
/// as its segments merged, so a chat's messages let go and read again over and over left it some 200 times the words it
/// found (86 MB for 0.46 MB on a Mac), the room it took letting go the messages themselves.
function dropSaidIndex(sql: Sql): void {
  const has = (name: string) => sql.all("SELECT 1 FROM sqlite_master WHERE name = ?", [name]).length > 0;
  for (const trigger of ["said_index_put", "said_index_drop", "said_index_set"]) if (has(trigger)) sql.exec(`DROP TRIGGER ${trigger}`);
  try {
    if (has("said_index")) sql.exec("DROP TABLE said_index");
  } catch {
    // A build without FTS5 cannot take it away: left as it is, nothing writes or reads it.
  }
}

/// The room the database's file holds and no longer uses given back to the device, at every open: what is let go (an
/// earlier core's search index, transcripts past KEPT) left its pages free in the file, which stayed as large as it
/// ever was (a phone's at 150 MB once the index was gone). A database made before is rewritten once (VACUUM) to keep
/// its free pages at the end (auto_vacuum INCREMENTAL); then only those free are cut off. The log the rewrite went
/// through is emptied too, or the room would only have moved there.
export function giveBackRoom(sql: Sql): void {
  const one = (q: string) => Number(sql.all(q)[0]?.[0] ?? 0);
  if (one("PRAGMA auto_vacuum") !== 2) {
    sql.exec("PRAGMA auto_vacuum = INCREMENTAL");
    sql.exec("VACUUM");
  } else if (one("PRAGMA freelist_count") > 0) {
    sql.exec("PRAGMA incremental_vacuum");
  } else {
    return;
  }
  sql.all("PRAGMA wal_checkpoint(TRUNCATE)");
}

/// The database's version.
export function versionOf(sql: Sql): number {
  const v = sql.all("PRAGMA user_version")[0]?.[0];
  return typeof v === "number" ? v : 0;
}

/// Brings the database to VERSION, each migration in a transaction of its own. A database past it is left as it is:
/// false then (it is read only).
export function migrate(sql: Sql): boolean {
  let version = versionOf(sql);
  if (version > VERSION) return false;
  while (version < VERSION) {
    sql.exec("BEGIN IMMEDIATE");
    try {
      sql.exec(MIGRATIONS[version]);
      sql.exec(`PRAGMA user_version = ${version + 1}`);
      sql.exec("COMMIT");
    } catch (e) {
      try {
        sql.exec("ROLLBACK");
      } catch {
        // Rolled back already.
      }
      throw e;
    }
    version++;
  }
  return true;
}
