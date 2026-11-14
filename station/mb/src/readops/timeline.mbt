// A session's history (station/src/read/sessions.ts `timeline`, `transcriptState`): the pages of its transcripts'
// entries and where their reading stands, read as read/transcripts.ts reads them (station/mb src/history's
// transcripts.mbt). The words a Codex script's calls are said in come from the pool in the language asked
// (`words.inScriptOutput`).

///|
/// sessions.ts `transcriptsOf`: a session's transcripts, those of the runtime sessions it ran in before first; None:
/// none found.
fn transcripts_of(db : @sql.Db, host : @host.Host, data : String, sep : String, finder : @locate.Finder, key : Json) -> (String, Array[(String, String)])? raise {
  let row = session_row(db, key)
  guard field(row, "runtime") is String(runtime) && @locate.runtime_kind(runtime) else { return None }
  let sources = runtime_session_sources(db, key, row)
  if sources.length() == 0 {
    return None
  }
  let cwd = field(row, "cwd")
  let workspace = match field(row, "workspace") { String(w) => w; _ => "" }
  let places = match cwd {
    String(c) if c != workspace => [c, workspace]
    _ => [workspace]
  }
  Some((runtime, finder.sources(data, profiles(host, data, sep), sources, places, anywhere=true).0))
}

///|
/// store.ts `runtimeSessionSources`: the runtime and profile of each transcript, the current one last.
fn runtime_session_sources(db : @sql.Db, key : Json, row : Map[String, Json]) -> Array[@locate.Source] raise {
  let rows = db.all(
    "SELECT r.id, COALESCE(r.runtime, s.original_runtime, s.runtime) AS runtime, r.profile FROM sessions s CROSS JOIN runtime_sessions r ON r.session_key = s.key WHERE s.key = ? ORDER BY r.at, r.rowid",
    [key],
  )
  let sources = rows.map(r => source_of(field(r, "id"), field(r, "runtime"), field(r, "profile")))
  guard field(row, "runtime_session_id") is String(current) else { return sources }
  let found = match sources.search_by(s => s.id == current) {
    Some(i) => sources[i]
    None => source_of(Json::string(current), field(row, "runtime"), field(row, "profile"))
  }
  sources.filter(s => s.id != current) + [found]
}

///|
/// sessions.ts `timeline`: entries before `before` (0), up to `limit` (200, from 1 to 1000); `after` instead, those just
/// after it; `from` and `to` instead, those (both included, at most 1000); in brief with `brief=1`. `end`: how many the
/// transcripts have.
pub fn timeline(db : @sql.Db, host : @host.Host, data : String, sep : String, finder : @locate.Finder, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  // (put back as it is read: a search says them in Chinese)
  let before_said = @history.in_script_output.val
  defer {
    @history.in_script_output.val = before_said
  }
  if args.value("words") is Some({ "inScriptOutput": String(said), .. }) {
    @history.in_script_output.val = said
  }
  let before = parse_usize(args.value("before")).unwrap_or(0.0)
  let limit = @cmp.minimum(@cmp.maximum(parse_usize(args.value("limit")).unwrap_or(200.0), 1.0), 1000.0)
  guard transcripts_of(db, host, data, sep, finder, args.value("key").unwrap_or(Json::null())) is Some((runtime, paths)) else {
    return { "start": 0, "entries": [], "end": 0 }
  }
  let chain = @history.chain_of(host, sep, paths, Some(@history.marks_dir(sep, data)))
  let end = @history.length_of(chain).to_double()
  let in_brief = args.value("brief") is Some(String("1"))
  let between = (a : Double, b : Double) => Json::array(@history.entries_of(host, runtime, chain, a, b, in_brief))
  let page = fn(start : Double, b : Double) -> Json {
    { "start": Json::number(start), "entries": between(start, b), "end": Json::number(end) }
  }
  let from = parse_usize(args.value("from"))
  let to = parse_usize(args.value("to"))
  if from is Some(f) && to is Some(t) {
    return page(f, @cmp.minimum(t, f + 999.0) + 1.0)
  }
  if parse_usize(args.value("after")) is Some(after) {
    let start = @cmp.minimum(after + 1.0, end)
    return page(start, start + limit)
  }
  let upto = @cmp.minimum(before, end)
  let start = @cmp.maximum(0.0, upto - limit)
  page(start, upto)
}

///|
/// sessions.ts `transcriptState`: where the reading of a session's transcripts stands, for its live view to go on from;
/// `states` null: none found.
pub fn transcript_state(db : @sql.Db, host : @host.Host, data : String, sep : String, finder : @locate.Finder, args : Json) -> Json raise {
  guard transcripts_of(db, host, data, sep, finder, args.value("key").unwrap_or(Json::null())) is Some((_, paths)) else {
    return { "states": Json::null() }
  }
  let chain = @history.chain_of(host, sep, paths, Some(@history.marks_dir(sep, data)))
  { "states": Json::array(chain.map(m => @history.state_json(m.state))) }
}
