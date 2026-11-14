// What the agents spent, as the usage page reads it (station/src/read/usage.ts `usage`, GET /usage) and as a Comma
// connect sends it (read/outflow.ts `outflowUsage`): the day's groups (usagegroups.mbt) with what they cost, the threads,
// people and accounts they name, the prices, the tasks other stations ran here and the page's year. The station's own
// words (the local page, the prices' note, an unnamed chat) the pool gives with the read (`words`).

///|
/// store.ts `usageSince` and usage-detail.ts `usageDetailSince`: from when every call was counted, and from when the
/// details hold every call.
fn detail_since(db : @sql.Db) -> Json raise {
  if has_compact(db) {
    return match
      one(db, "SELECT since FROM usage_compact_since WHERE id = 1", []) {
      Some(r) => field(r, "since")
      None =>
        raise Failure("Cannot read properties of undefined (reading 'since')")
    }
  }
  if usage_retired(db) || !table_installed(db, "usage_detail_live_since") {
    return Json::null()
  }
  match one(db, "SELECT since FROM usage_detail_live_since WHERE id = 1", []) {
    Some(r) => field(r, "since")
    None =>
      raise Failure("Cannot read properties of undefined (reading 'since')")
  }
}

///|
fn usage_number(v : Json) -> Double {
  match v {
    Number(n, ..) => n
    _ => 0.0
  }
}

///|
/// store.ts `usageSince`.
fn usage_since(db : @sql.Db) -> Json raise {
  if has_compact(db) {
    guard one(
        db,
        "SELECT since, first_at, first_unknown FROM usage_compact_since WHERE id = 1",
        [],
      )
      is Some(r) else {
      raise Failure(
        "Cannot read properties of undefined (reading 'first_unknown')",
      )
    }
    let since = field(r, "since")
    let first_at = field(r, "first_at")
    let unknown = match field(r, "first_unknown") {
      Null | Number(0.0, ..) => false
      String(s) => s != ""
      _ => true
    }
    return if unknown || first_at is Null {
      since
    } else if usage_number(first_at) > usage_number(since) {
      first_at
    } else {
      since
    }
  }
  guard one(db, "SELECT first_at FROM usage_span WHERE id = 1", [])
    is Some(span) else {
    raise Failure("Cannot read properties of undefined (reading 'first_at')")
  }
  let first = field(span, "first_at")
  let cutover = detail_since(db)
  if cutover is Null {
    return first
  }
  if first is Null || usage_number(cutover) >= usage_number(first) {
    cutover
  } else {
    first
  }
}

// ── the accounts of the config (usage.ts `configProfiles`, agents/profiles.ts `profileRuntimes`) ──

///|
/// What a provider speaks (agents/providers.ts SOURCES): whether it answers chat completions, OpenAI's responses and
/// Anthropic's messages where it is at an address of its own, and the protocols one at the person's own address takes.
priv struct Source {
  id : String
  chat : Bool
  responses : Bool
  anthropic : Bool
  at_address : Bool
  protocols : Array[String]
}

///|
let sources : Array[Source] = [
  {
    id: "openai",
    chat: false,
    responses: true,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "anthropic",
    chat: false,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "google",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "xai",
    chat: false,
    responses: true,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "mistral",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "deepseek",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "qwen",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "moonshotai",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "kimi-code",
    chat: true,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "zai",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "minimax",
    chat: false,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "xiaomi",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "ant-ling",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "jev",
    chat: false,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "qwen-cn",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "moonshotai-cn",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "zai-coding-cn",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "minimax-cn",
    chat: false,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "openrouter",
    chat: true,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "vercel-ai-gateway",
    chat: false,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "opencode",
    chat: true,
    responses: true,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "opencode-go",
    chat: true,
    responses: true,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "cloudflare-ai-gateway",
    chat: false,
    responses: false,
    anthropic: false,
    at_address: true,
    protocols: ["chat_completions", "responses", "anthropic"],
  },
  {
    id: "azure-openai",
    chat: false,
    responses: false,
    anthropic: false,
    at_address: true,
    protocols: ["responses"],
  },
  {
    id: "groq",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "together",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "fireworks",
    chat: true,
    responses: false,
    anthropic: true,
    at_address: false,
    protocols: [],
  },
  {
    id: "cerebras",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "huggingface",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "nvidia",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "baseten",
    chat: true,
    responses: false,
    anthropic: false,
    at_address: false,
    protocols: [],
  },
  {
    id: "cloudflare-workers-ai",
    chat: false,
    responses: false,
    anthropic: false,
    at_address: true,
    protocols: ["chat_completions"],
  },
  {
    id: "ollama",
    chat: false,
    responses: false,
    anthropic: false,
    at_address: true,
    protocols: ["chat_completions"],
  },
  {
    id: "custom",
    chat: false,
    responses: false,
    anthropic: false,
    at_address: true,
    protocols: ["chat_completions", "responses", "anthropic"],
  },
]

///|
/// runtime.ts RUNTIME_KINDS.
let runtime_kinds : Array[String] = [
  "claude", "codex", "dsh", "grok", "cursor", "devin", "hermes", "agy",
]

///|
/// providers.ts `cleanEndpoint`: an address trimmed, without a trailing slash; none unless it is an http(s) one. A value
/// that is no string throws there (`text.trim`).
fn clean_endpoint(v : @jsjson.JValue) -> String? raise {
  guard v is Str(s) else { raise Failure("text.trim is not a function") }
  let mut trimmed = @jscase.trim(@jsjson.raw_text(s))
  while trimmed.has_suffix("/") {
    trimmed = trimmed.view(end_offset=trimmed.length() - 1).to_owned()
  }
  let rest = if trimmed.has_prefix("https://") {
    Some(trimmed.view(start_offset=8).to_owned())
  } else if trimmed.has_prefix("http://") {
    Some(trimmed.view(start_offset=7).to_owned())
  } else {
    None
  }
  match rest {
    Some(r) if r != "" => {
      for i in 0..<r.length() {
        if @jscase.is_space(r.unsafe_charcode_at(i)) {
          return None
        }
      }
      Some(trimmed)
    }
    _ => None
  }
}

///|
/// What an address-speaking source answers there (providers.ts `endpoints`): (chat, responses, anthropic), none where
/// its address is needed and is no usable one, or the protocol chosen is not one it takes.
fn endpoints_of(
  source : Source,
  endpoint : String?,
  protocol : String?,
) -> (Bool, Bool, Bool)? raise {
  if !source.at_address {
    return Some((source.chat, source.responses, source.anthropic))
  }
  guard endpoint is Some(e) &&
    clean_endpoint(Str(@jsjson.units(e))) is Some(base) else {
    return None
  }
  let chosen = match protocol {
    Some(p) if ["chat_completions", "responses", "anthropic"].contains(p) =>
      Some(p)
    _ => None
  }
  if chosen is Some(c) && !source.protocols.contains(c) {
    return None
  }
  match (source.id, chosen) {
    ("cloudflare-ai-gateway", None) => Some((true, true, true))
    ("cloudflare-ai-gateway", Some(c)) =>
      Some((c == "chat_completions", c == "responses", c == "anthropic"))
    ("azure-openai", _) => Some((false, true, false))
    ("cloudflare-workers-ai" | "ollama", _) => Some((true, false, false))
    (_, Some("chat_completions")) => Some((true, false, false))
    (_, Some("responses")) => Some((false, true, false))
    (_, Some(_)) => Some((false, false, true))
    (_, None) => Some((true, true, base.has_suffix("/v1")))
  }
}

///|
/// The first runtime an account of config.json runs (profiles.ts `profileRuntimes`, of `{runtime, access}`), Claude's
/// in name for one that runs none.
fn first_runtime(p : @jsjson.JValue) -> String raise {
  let access = match jget(Some(p), "access") {
    Some(Obj(_) | Arr(_) as a) => Some(a)
    _ => None
  }
  let text = (v : @jsjson.JValue?) => {
    match v {
      Some(Str(s)) => Some(@jsjson.raw_text(s))
      _ => None
    }
  }
  let str = (v : @jsjson.JValue?) => {
    match text(v) {
      Some(s) if s != "" => Some(s)
      _ => None
    }
  }
  let kind = match jget(access, "kind") {
    None | Some(Null) => Some("env")
    v => text(v)
  }
  if kind == Some("api-provider") {
    let provider = str(jget(access, "provider"))
    let endpoint = match jget(access, "endpoint") {
      None => None
      Some(e) => clean_endpoint(e)
    }
    let protocol = str(jget(access, "protocol"))
    guard provider is Some(id) else { return "claude" }
    guard sources.search_by(s => s.id == id) is Some(at) else {
      return "claude"
    }
    let source = sources[at]
    guard endpoints_of(source, endpoint, protocol)
      is Some((chat, responses, anthropic)) else {
      return "claude"
    }
    if id == "kimi-code" && jget(access, "login") is Some(Bool(true)) {
      return "claude"
    }
    return if anthropic {
      "claude"
    } else if responses {
      "codex"
    } else if chat {
      "dsh"
    } else if id == "xai" {
      "grok"
    } else if id == "google" {
      "agy"
    } else {
      "claude"
    }
  }
  if kind == Some("opencode-go") || kind == Some("anthropic-api") {
    return "claude"
  }
  match text(jget(Some(p), "runtime")) {
    Some(own) if runtime_kinds.contains(own) =>
      if own == "dsh" && kind == Some("subscription") {
        "claude"
      } else {
        own
      }
    _ => "claude"
  }
}

///|
/// usage.ts `configProfiles`: each account's name (trimmed, else its id) and the runtime it runs, by its id; none
/// without a config that reads.
fn config_profiles(
  host : @host.Host,
  data : String,
  sep : String,
) -> Json raise {
  let raw = match
    read_text(host, join_path(sep, data, "config.json"), strict=false) {
    Some(t) => @jsjson.parse(t) catch { _ => return Json::object(Map([])) }
    None => return Json::object(Map([]))
  }
  let out : Array[(Array[Int32], @jsjson.JValue)] = []
  if jget(Some(raw), "profiles") is Some(Arr(profiles)) {
    for p in profiles {
      guard jget(Some(p), "id") is Some(Str(id)) else { continue }
      let runtime = first_runtime(p)
      let name = match jget(Some(p), "name") {
        Some(Str(n)) if @jscase.trim(@jsjson.raw_text(n)) != "" =>
          @jscase.trim(@jsjson.raw_text(n))
        _ => @jsjson.raw_text(id)
      }
      let value : @jsjson.JValue = Obj([
        (@jsjson.units("name"), Str(@jsjson.units(name))),
        (@jsjson.units("runtime"), Str(@jsjson.units(runtime))),
      ])
      match out.search_by(e => e.0 == id) {
        Some(i) => out[i] = (id, value)
        None => out.push((id, value))
      }
    }
  }
  // As JSON.stringify orders an object's keys (an index first).
  @json.parse(@jsjson.stringify(Obj(out))) catch {
    _ => Json::object(Map([]))
  }
}

// ── the page's year (usage.ts `usageHistory`) ──

///|
let history_pending_chats : String = "usage chat statistics are still being filled"

///|
let remote_runs_pending : String = "remote task statistics are still being filled"

///|
/// store.ts `remoteRunsReady`.
fn remote_runs_ready(db : @sql.Db) -> Unit raise {
  match one(db, "SELECT done FROM remote_run_progress WHERE id = 1", []) {
    Some(r) if field(r, "done") == Json::number(1.0) => ()
    _ => raise Failure(remote_runs_pending)
  }
}

///|
fn is_pending(e : Error, message : String) -> Bool {
  e is Failure(m) && m == message
}

///|
/// usage-chat-stats.ts `usageChatStatsReady` with the cards' own coverage left to the caller (`allowIncompleteCards`).
fn chat_stats_ready(db : @sql.Db, viewer : Viewer?) -> Bool raise {
  guard one(db, "SELECT done FROM usage_chat_progress WHERE id = 1", [])
    is Some(r) &&
    field(r, "done") == Json::number(1.0) else {
    return false
  }
  match viewer {
    None => one(db, "SELECT 1 FROM usage_chat_dirty LIMIT 1", []) is None
    Some(v) => {
      if one(
          db,
          "SELECT 1 FROM usage_chat_dirty_scope WHERE kind = 2 AND ws = ? LIMIT 1",
          [Json::string(v.workspace)],
        )
        is Some(_) {
        return false
      }
      !v.home ||
      one(
        db,
        "SELECT 1 FROM usage_chat_dirty_scope WHERE kind = 1 AND ws = '' LIMIT 1",
        [],
      )
      is None
    }
  }
}

///|
/// store.ts `usageChatTotals`: the chats of each place, those archived, the decision cards and those answered by an
/// option pressed.
fn chat_totals(
  db : @sql.Db,
  viewer : Viewer?,
) -> (Array[(String, Double)], Double, Double, Double) raise {
  if !chat_stats_ready(db, viewer) {
    raise Failure(history_pending_chats)
  }
  let places : Array[(String, Double)] = []
  let mut archived = 0.0
  let mut cards = 0.0
  let mut picked = 0.0
  let scopes : Array[(Int32, String, Double)] = match viewer {
    None => [(0, "", 1.0)]
    Some(v) =>
      if v.home {
        [(1, "", 1.0), (2, v.workspace, 1.0), (3, v.workspace, -1.0)]
      } else {
        [(2, v.workspace, 1.0)]
      }
  }
  for scope in scopes {
    let (kind, workspace, sign) = scope
    for
      row in db.all(
        "SELECT place, chats, archived, cards, picked FROM usage_chat_totals WHERE kind = ? AND ws = ?",
        [Json::number(kind.to_double()), Json::string(workspace)],
      ) {
      let place = js_text(field(row, "place"))
      let n = sign * usage_number(field(row, "chats"))
      match places.search_by(p => p.0 == place) {
        Some(i) => places[i] = (place, places[i].1 + n)
        None => places.push((place, 0.0 + n))
      }
      archived += sign * usage_number(field(row, "archived"))
      cards += sign * usage_number(field(row, "cards"))
      picked += sign * usage_number(field(row, "picked"))
    }
  }
  (places.filter(p => p.1 != 0.0), archived, cards, picked)
}

///|
/// The quarter hour `at` (ms) is in (usage-history.ts `quarter`).
fn quarter_of(at : Int64) -> Int64 {
  floor_div(at, 900_000L)
}

///|
/// usage.ts `validHistoryRange`.
fn valid_history_range(range : (Int64, Int64)?, offset : Int64) -> Bool {
  let day = 86_400_000L
  guard range is Some((from, to)) else { return false }
  let local = to + offset * 60_000L
  from <= to &&
  to - from <= 370L * day &&
  from % 60_000L == 0L &&
  to % 60_000L == 0L &&
  local % day == 0L &&
  local >= -8_640_000_000_000_000L &&
  local <= 8_640_000_000_000_000L
}

///|
/// usage.ts `usageHistory`: the page's year by day, its tokens in all before the year's end, the chats of each place, the
/// decision cards and the tasks other stations' chats ran here; none where the history is not installed.
fn usage_history(
  db : @sql.Db,
  offset : Int64,
  viewer : Viewer?,
  requested : (Int64, Int64)?,
) -> Json raise {
  if !table_installed(db, "usage_history_since") {
    return Json::null()
  }
  let range = if valid_history_range(requested, offset) {
    requested
  } else {
    None
  }
  let scopes : Array[String] = match viewer {
    None =>
      db
      .all("SELECT scope, tokens FROM usage_history_total", [])
      .map(r => js_text(field(r, "scope")))
    Some(v) => if v.home { [v.workspace, ""] } else { [v.workspace] }
  }
  let (from, to) = match range {
    Some((f, t)) => (quarter_of(f), quarter_of(t))
    None => (-(1L << 62), 1L << 62)
  }
  let days : Array[(Json, Double, Double)] = []
  let mut tokens = 0.0
  for scope in scopes {
    for
      r in db.all(
        "SELECT strftime('%Y-%m-%d', quarter * 900 + ?4 * 60, 'unixepoch') AS day, SUM(calls) AS calls, SUM(tokens) AS tokens\n  FROM usage_history WHERE scope = ?1 AND quarter >= ?2 AND quarter < ?3 GROUP BY day",
        [Json::string(scope), i64_json(from), i64_json(to), i64_json(offset)],
      ) {
      let day = field(r, "day")
      match days.search_by(d => d.0 == day) {
        Some(i) =>
          days[i] = (
            day,
            days[i].1 + usage_number(field(r, "tokens")),
            days[i].2 + usage_number(field(r, "calls")),
          )
        None =>
          days.push(
            (
              day,
              0.0 + usage_number(field(r, "tokens")),
              0.0 + usage_number(field(r, "calls")),
            ),
          )
      }
    }
    if range is Some(_) {
      let total = match
        one(db, "SELECT tokens FROM usage_history_total WHERE scope = ?1", [
          Json::string(scope),
        ]) {
        Some(r) => usage_number(field(r, "tokens"))
        None => 0.0
      }
      let after = match
        one(
          db,
          "SELECT SUM(tokens) AS tokens FROM usage_history WHERE scope = ?1 AND quarter >= ?2",
          [Json::string(scope), i64_json(to)],
        ) {
        Some(r) => usage_number(field(r, "tokens"))
        None => 0.0
      }
      tokens += total - after
    }
  }
  let since = match
    one(db, "SELECT since FROM usage_history_since WHERE id = 1", []) {
    Some(r) => field(r, "since")
    None =>
      raise Failure("Cannot read properties of undefined (reading 'since')")
  }
  let chats = Some(chat_totals(db, viewer)) catch {
    e => if is_pending(e, history_pending_chats) { None } else { raise e }
  }
  let remote = try {
    remote_runs_ready(db)
    Some(
      match viewer {
        None =>
          match one(db, "SELECT n FROM remote_run_total WHERE id = 1", []) {
            Some(r) if !(field(r, "n") is Null) => usage_number(field(r, "n"))
            _ => 0.0
          }
        Some(v) =>
          match
            one(db, "SELECT n FROM remote_run_counts WHERE ws = ?", [
              Json::string(v.workspace),
            ]) {
            Some(r) if !(field(r, "n") is Null) => usage_number(field(r, "n"))
            _ => 0.0
          }
      },
    )
  } catch {
    e => if is_pending(e, remote_runs_pending) { None } else { raise e }
  }
  let sorted = days.copy()
  sorted.sort_by((a, b) => {
    match (a.0, b.0) {
      (String(x), String(y)) => x.compare(y)
      _ => 0
    }
  })
  let out : Map[String, Json] = {
    "days": Json::array(
      sorted.map(d => {
        (
          {
            "day": d.0,
            "runtime": "",
            "model": Json::null(),
            "tokens": Json::number(d.1),
            "calls": Json::number(d.2),
          } : Json)
      }),
    ),
  }
  if range is Some((_, t)) {
    out["tokens"] = Json::number(tokens)
    out["beforeDay"] = Json::string(
      @history.date_iso((t + offset * 60_000L).to_double())
      .view(end_offset=10)
      .to_owned(),
    )
  }
  if !(since is Null) {
    out["since"] = since
  }
  match chats {
    Some((_, _, cards, picked)) if !table_installed(
        db, "card_outcomes_incomplete",
      ) => {
      out["cards"] = Json::number(cards)
      out["picked"] = Json::number(picked)
    }
    _ => out["cardsIncomplete"] = Json::boolean(true)
  }
  match chats {
    None => {
      out["chatsIncomplete"] = Json::boolean(true)
      out["places"] = Json::object(Map([]))
    }
    Some((places, archived, _, _)) => {
      let m : Map[String, Json] = Map([])
      for p in places {
        m[p.0] = Json::number(p.1)
      }
      out["places"] = Json::object(m)
      out["archived"] = Json::number(archived)
    }
  }
  if remote is Some(n) {
    out["remoteRuns"] = Json::number(n)
  }
  Json::object(out)
}

// ── the page ──

///|
/// What a usage read is asked (usage.ts `usage`'s parameters).
priv struct Asked {
  from : Int64
  to : Int64
  offset : Int64
  reading : Bool
  viewer : Json?
  history : Bool
  history_range : (Int64, Int64)?
  details_preparing : Bool
  remote_runs : Bool
  metadata : Bool
}

///|
/// store.ts `remoteRunsSince`.
fn remote_runs_since(
  db : @sql.Db,
  from : Int64,
  viewer : Viewer?,
) -> Json raise {
  remote_runs_ready(db)
  let rows = match viewer {
    None =>
      db.all(
        "SELECT at, session FROM remote_run_by_time WHERE at >= ? ORDER BY at, seq",
        [i64_json(from)],
      )
    Some(v) =>
      db.all(
        "SELECT at, session FROM remote_run_lookup WHERE ws = ?1 AND at >= ?2 ORDER BY at, seq",
        [Json::string(v.workspace), i64_json(from)],
      )
  }
  Json::array(
    rows.map(r => {
      (
        {
          "at": Json::number(usage_number(field(r, "at"))),
          "session": Json::string(js_text(field(r, "session"))),
        } : Json)
    }),
  )
}

///|
/// usage.ts `usage`: what the agents spent from `from` until `to`, by day in the asker's time zone, with what the rows
/// name. `batched`: the groups the summary blocks gave (read/worker.ts, `usageGroupsBatched`), where they did.
fn usage_answer(
  db : @sql.Db,
  known : Known,
  a : Asked,
  batched : Array[Group]?,
  words : Json,
) -> Json raise {
  let viewer = viewer_of(a.viewer)
  let groups = if a.details_preparing {
    []
  } else {
    match batched {
      Some(g) => g
      None => usage_groups(db, a.from, a.to, a.offset, viewer)
    }
  }
  let visible = match a.viewer {
    Some(Object(_) as v) if !has_compact(db) => {
      let seen = seen_by(db, v, groups.map(g => js_text(g.session)))
      groups.filter(g => seen(js_text(g.session)))
    }
    _ => groups
  }
  let rows = visible.map(g => {
    (
      {
        "day": Json::string(g.day),
        "session": g.session,
        "thread": g.thread,
        "person": g.person,
        "profile": g.profile,
        "runtime": g.runtime,
        "model": g.model,
        "calls": Json::number(g.calls),
        "input": Json::number(g.input),
        "cacheRead": Json::number(g.cache_read),
        "cacheWrite": Json::number(g.cache_write + g.cache_write_long),
        "output": Json::number(g.output),
        "cost": cost(g),
      } : Json)
  })
  let word = (k : String) => {
    match words.value(k) {
      Some(String(s)) => s
      _ => ""
    }
  }
  let threads : Map[String, Json] = Map([])
  let people : Map[String, Json] = Map([])
  if a.metadata {
    let wanted : Array[Json] = []
    for g in visible {
      if g.thread is Number(_, ..) && !wanted.contains(g.thread) {
        wanted.push(g.thread)
      }
    }
    // (an object's index-like keys as JSON.stringify orders them: by their number)
    wanted.sort_by((x, y) => usage_number(x).compare(usage_number(y)))
    for id in wanted {
      guard one(db, "SELECT * FROM threads WHERE id = ?", [id]) is Some(t) else {
        continue
      }
      let own = field(t, "surface") == Json::string("ember")
      let first = if !own &&
        field(t, "title") is Null &&
        field(t, "auto_title") is Null {
        first_text(db, id) catch {
          _ => Json::null()
        }
      } else {
        Json::null()
      }
      let channel = if own {
        Json::null()
      } else {
        let connect = match
          one(
            db,
            "SELECT connect FROM thread_sessions WHERE thread = ? AND connect != 'ember' ORDER BY joined_at, rowid LIMIT 1",
            [id],
          ) {
          Some(r) =>
            match field(r, "connect") {
              String(c) => Some(c)
              _ => None
            }
          None => None
        }
        known.channel(connect, field(t, "channel"))
      }
      threads[js_text(id)] = {
        "title": Json::string(
          chat_title(
            thread_json(t),
            first,
            channel,
            word("untitled"),
            word("directMessage"),
          ),
        ),
        "surface": field(t, "surface"),
        "home": field(t, "home"),
        "archived": Json::boolean(!(field(t, "hidden_at") is Null)),
      }
    }
    let refs : Array[String] = []
    for g in visible {
      if g.person is String(p) && !refs.contains(p) {
        refs.push(p)
      }
    }
    refs.sort_by(utf8_order)
    for r in refs {
      people[r] = known.creator(Json::string(r))
    }
  }
  let since = usage_since(db)
  let detail = if a.metadata { detail_since(db) } else { Json::null() }
  let prices = if a.metadata {
    Some(price_table(word("priceNote"), visible.map(g => g.model)))
  } else {
    None
  }
  let profiles = if a.metadata {
    Some(config_profiles(known.host, known.data, known.sep))
  } else {
    None
  }
  let remote = if a.remote_runs {
    Some(remote_runs_since(db, a.from, viewer)) catch {
      e => if is_pending(e, remote_runs_pending) { None } else { raise e }
    }
  } else {
    Some(Json::array([]))
  }
  let history = if a.history {
    Some(usage_history(db, a.offset, viewer, a.history_range))
  } else {
    None
  }
  let out : Map[String, Json] = {
    "from": i64_json(a.from),
    "to": i64_json(a.to),
    "since": since,
  }
  if !(detail is Null) {
    out["detailSince"] = detail
  }
  out["reading"] = Json::boolean(a.reading)
  if a.details_preparing {
    out["detailsPreparing"] = Json::boolean(true)
  }
  if prices is Some(p) {
    out["prices"] = p
  }
  out["rows"] = Json::array(rows)
  if a.metadata {
    out["threads"] = Json::object(threads)
    out["people"] = Json::object(people)
    out["profiles"] = profiles.unwrap_or(Json::object(Map([])))
  }
  if remote is Some(r) {
    out["remoteRuns"] = r
  }
  match history {
    Some(Null) => out["historyUnavailable"] = Json::boolean(true)
    Some(h) => out["history"] = h
    None => ()
  }
  Json::object(out)
}

///|
/// BigInt(v) of what is given: undefined refused, as BigInt refuses it.
fn big_given(v : Json?) -> Int64 raise {
  match v {
    None => raise Failure("Cannot convert undefined to a BigInt")
    Some(Null) => raise Failure("Cannot convert null to a BigInt")
    Some(Number(n, ..)) if n != n.floor() =>
      raise Failure(
        "The number \{n} cannot be converted to a BigInt because it is not an integer",
      )
    Some(True) => 1L
    Some(False) => 0L
    v => big_of(v)
  }
}

///|
/// ops-usage.ts `usage` (GET /usage), with what read/worker.ts reads before it: the summary blocks' groups where the page
/// does not wait for its details (`usageGroupsBatched`).
pub fn usage_page(
  db : @sql.Db,
  host : @host.Host,
  data : String,
  sep : String,
  ask : Json,
) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let details_preparing = args.value("detailsPreparing") is Some(True)
  let viewer = match args.value("viewer") {
    None | Some(Null) => None
    v => v
  }
  let batched = if details_preparing {
    None
  } else {
    let prepared = if args.value("summaryStrict") is Some(True) {
      Some(args.value("summaryPrepared") is Some(True))
    } else {
      None
    }
    usage_groups_batched(
      db,
      big_given(args.value("from")),
      big_given(args.value("to")),
      big_given(args.value("tz")),
      viewer_of(viewer),
      prepared,
    )
  }
  let from = big_given(args.value("from"))
  let to = big_given(args.value("to"))
  let offset = big_given(args.value("tz"))
  let history_range = match args.value("historyRange") {
    None | Some(Null | False) | Some(Number(0.0, ..)) | Some(String("")) => None
    Some(r) => Some((big_given(r.value("from")), big_given(r.value("to"))))
  }
  let asked : Asked = {
    from,
    to,
    offset,
    reading: match args.value("reading") {
      Some(True) => true
      Some(False) => false
      _ => true
    },
    viewer,
    history: args.value("history") is Some(True),
    history_range,
    details_preparing,
    remote_runs: true,
    metadata: true,
  }
  usage_answer(
    db,
    Known::of(host, data, sep, ask),
    asked,
    batched,
    args.value("words").unwrap_or(Json::null()),
  )
}

///|
/// A span of usage read at once, at most (ops-usage.ts SPAN_MAX_MS).
let span_max_ms : Double = 31.0 * 24.0 * 60.0 * 60_000.0

///|
/// outflow.ts `outflowUsage` (`outflow.read` v1 `usage`): the model calls from `from` until `to`, by day in UTC+`tz`
/// minutes, chat, session, person, account and model, with what they cost; `people` the rows' persons.
pub fn outflow_usage(
  db : @sql.Db,
  host : @host.Host,
  data : String,
  sep : String,
  ask : Json,
) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let from = whole(args.value("from"))
  let asked_to = whole(args.value("to"))
  let to = if asked_to < from + span_max_ms {
    asked_to
  } else {
    from + span_max_ms
  }
  let asked_tz = whole(args.value("tz"))
  let tz = if asked_tz < -1440.0 {
    -1440.0
  } else if asked_tz > 1440.0 {
    1440.0
  } else {
    asked_tz
  }
  let of = outflow_of(args.value("ws"))
  let asked : Asked = {
    from: from.to_int64(),
    to: to.to_int64(),
    offset: tz.to_int64(),
    reading: false,
    viewer: Some({ "workspace": of.0, "home": Json::boolean(of.1) }),
    history: false,
    history_range: None,
    details_preparing: false,
    remote_runs: false,
    metadata: false,
  }
  let read = usage_answer(
    db,
    Known::of(host, data, sep, ask),
    asked,
    None,
    Json::null(),
  )
  let teams_cache : Ref[Map[String, Team]?] = Ref(None)
  let teams_of = () => {
    match teams_cache.val {
      Some(t) => t
      None => {
        let t = teams(host, data, sep)
        teams_cache.val = Some(t)
        t
      }
    }
  }
  let rows : Array[Json] = []
  let people : Map[String, Json] = Map([])
  if read.value("rows") is Some(Array(rs)) {
    for r in rs {
      let get = (k : String) => r.value(k).unwrap_or(Json::null())
      rows.push({
        "day": get("day"),
        "thread": get("thread"),
        "session": get("session"),
        "person": get("person"),
        "account": get("profile"),
        "runtime": get("runtime"),
        "model": get("model"),
        "calls": get("calls"),
        "input": get("input"),
        "cacheRead": get("cacheRead"),
        "cacheWrite": get("cacheWrite"),
        "output": get("output"),
        "cost": get("cost"),
      })
      if get("person") is String(p) && !people.contains(p) {
        people[p] = outflow_person(host, data, sep, teams_of, p)
      }
    }
  }
  {
    "from": Json::number(from),
    "to": Json::number(to),
    "tz": Json::number(tz),
    "since": read.value("since").unwrap_or(Json::null()),
    "rows": Json::array(rows),
    "people": Json::object(people),
  }
}
