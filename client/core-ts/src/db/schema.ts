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

/// What a chat's page reads of its station's overview, the JSON `j` (views.ts #chatOverview: its agents' accounts and
/// connects, `#peopleOf`, `#shown`, `#whereIn`, `#sentElsewhere`, its station's update and context), as SQL: its
/// `profiles`, `connects`, `disk`, `slackUsers`, `updates`, `feedback` and `context`, each as the overview has it, one
/// absent left out; NULL where the overview is not an object. Kept apart from the list's part and the row's
/// (`station_part.chat`): a chat's first answer read the whole overview of its station (25-27 KB of the real-size
/// workspace's). Its accounts are most of it (`profiles`, some 13 KB of the 17): what an agent's account shows is made
/// of its profile whole, as on every page that shows one (present.ts profile, models.ts runnableOn), not of a copy.
export const overviewChatOf = (j: string) => `CASE WHEN json_type(${j}) = 'object'
    THEN json((SELECT json_group_object(o.key, ${j} -> o.fullkey) FROM json_each(${j}) AS o
      WHERE o.key IN ('profiles', 'connects', 'disk', 'slackUsers', 'updates', 'feedback', 'context')))
    END`;

/// The fields of an overview a chat's page reads (overviewChatOf), for where it is made of an overview in the core (one
/// shown with what is being done to it here: data.ts overviewChat).
export const OVERVIEW_CHAT = ["profiles", "connects", "disk", "slackUsers", "updates", "feedback", "context"] as const;

/// The stations a station took the place of, as its overview says (`copies.formerly`, its strings), the JSON `j`, as
/// SQL: what a link to a chat of one of them is taken to (views.ts `stationNow`), read of every station of a
/// workspace as a chat with links in it is made; `[]` where it says none. Kept in a column of its own
/// (`station_part.formerly`): read of the chat's part, it was 17 KB parsed a station for these few bytes.
export const overviewFormerlyOf = (j: string) => `CASE WHEN json_type(${j}, '$.copies.formerly') = 'array'
    THEN json((SELECT json_group_array(f.value ORDER BY f.key) FROM json_each(${j}, '$.copies.formerly') AS f WHERE f.type = 'text'))
    ELSE json_array() END`;

/// Each column of an overview's part (`station_part`) and how SQLite makes it of the overview's JSON.
export const PART_COLUMNS: [string, (j: string) => string][] = [["part", overviewPartOf], ["row", overviewRowOf], ["chat", overviewChatOf], ["formerly", overviewFormerlyOf]];
/// What makes each column of a station's part of the overview `j` (the triggers', and where one is missing).
const partInsert = (j: string, address: string) =>
  `INSERT INTO station_part (address, ${PART_COLUMNS.map(([c]) => c).join(", ")}) SELECT ${address}, ${PART_COLUMNS.map(([, of]) => of(j)).join(", ")}`;

/// The triggers keeping each overview's part (station_part) and dropping its readers' verdicts (station_fit) as it
/// changes or goes, whoever writes it, by name, as sqlite_master keeps them (no `IF NOT EXISTS`: SQLite keeps the
/// statement without it).
const overviewTriggers = (): [string, string][] => [
  ["station_part_put", `CREATE TRIGGER station_part_put AFTER INSERT ON station WHEN new.kind = 'overview'
      BEGIN
        DELETE FROM station_part WHERE address = new.address;
        ${partInsert("new.json", "new.address")} WHERE json_valid(new.json);
      END`],
  ["station_part_set", `CREATE TRIGGER station_part_set AFTER UPDATE OF json ON station WHEN new.kind = 'overview' AND old.json IS NOT new.json
      BEGIN
        DELETE FROM station_part WHERE address = new.address;
        ${partInsert("new.json", "new.address")} WHERE json_valid(new.json);
      END`],
  ["station_part_drop", `CREATE TRIGGER station_part_drop AFTER DELETE ON station WHEN old.kind = 'overview'
      BEGIN
        DELETE FROM station_part WHERE address = old.address;
      END`],
  ["station_fit_put", `CREATE TRIGGER station_fit_put AFTER INSERT ON station WHEN new.kind = 'overview'
      BEGIN
        DELETE FROM station_fit WHERE address = new.address;
      END`],
  ["station_fit_set", `CREATE TRIGGER station_fit_set AFTER UPDATE OF json ON station WHEN new.kind = 'overview' AND old.json IS NOT new.json
      BEGIN
        DELETE FROM station_fit WHERE address = new.address;
      END`],
  ["station_fit_drop", `CREATE TRIGGER station_fit_drop AFTER DELETE ON station WHEN old.kind = 'overview'
      BEGIN
        DELETE FROM station_fit WHERE address = old.address;
      END`],
];

/// A statement as compared with sqlite_master's: its spaces and line breaks one space.
const spaced = (s: string) => s.replace(/\s+/g, " ").trim();

/// Each station's overview's part the chat list reads (overviewPartOf), what a station's row reads (overviewRowOf, its
/// own column), what a chat's page reads (overviewChatOf) and the stations it took the place of (overviewFormerlyOf),
/// each its own column, beside it in a table of its own: they
/// read a few hundred bytes, or a chat's page some of the overview, not an overview of some 150 KB (nor walk its pages
/// to a column after it). Kept by triggers on `station`, as `said` is, so a core that knows nothing of it (a web page
/// still open from before, an app put back to an older one) keeps it too: nothing it holds is older than its overview.
/// And whether this core can read each overview (`station_fit`), judged as it is written (account.ts #overviewWritten)
/// by the id of the shapes that judged it (views.ts OVERVIEW_FIT), dropped by triggers as the overview changes or goes,
/// whoever writes it, so a core that knows nothing of it leaves no verdict on an overview it wrote. Made where missing
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
      CREATE TABLE IF NOT EXISTS station_part (address TEXT PRIMARY KEY, part TEXT NOT NULL, row TEXT, chat TEXT, formerly TEXT);
      CREATE TABLE IF NOT EXISTS station_fit (address TEXT NOT NULL, shapes TEXT NOT NULL, readable INTEGER NOT NULL, PRIMARY KEY (address, shapes)) WITHOUT ROWID;
    `);
    const had = new Map(sql.all("SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'station'").map((r) => [String(r[0]), String(r[1])]));
    let remade = false;
    // (a table an earlier core made: the columns it has not added, every part made again with them)
    const columns = sql.all("PRAGMA table_info(station_part)").map((r) => r[1]);
    for (const [column] of PART_COLUMNS) {
      if (columns.includes(column)) continue;
      sql.exec(`ALTER TABLE station_part ADD COLUMN ${column} TEXT`);
      remade = true;
    }
    for (const [name, statement] of overviewTriggers()) {
      const was = had.get(name);
      if (was !== undefined && spaced(was) === spaced(statement)) continue;
      if (was !== undefined) {
        sql.exec(`DROP TRIGGER ${name}`);
        if (name.startsWith("station_part_")) remade = true;
      }
      sql.exec(statement);
    }
    // (an earlier core's parts: all made again, of the overviews, by SQLite)
    if (remade) sql.exec("DELETE FROM station_part");
    // (asked first by the rows' keys alone: an overview is read only where its part is missing)
    const missing = sql.all("SELECT s.address FROM station s WHERE s.kind = 'overview' AND NOT EXISTS (SELECT 1 FROM station_part p WHERE p.address = s.address)");
    for (const [address] of missing) {
      sql.run(`${partInsert("st.json", "st.address")} FROM station AS st WHERE st.address = ? AND st.kind = 'overview' AND json_valid(st.json)`, [address]);
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
