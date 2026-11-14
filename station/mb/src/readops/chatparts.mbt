// What the chat list is made of besides its chats' summaries (station/src/read/store.ts): where each chat's latest
// message stands for unread (`saidOf`), its sessions' latest turns (`sessionActivity`) and watches (`watching`), the
// cards it waits on and those answered lately (`threadsWithCards`, `requireCardPosts`, `askingMessage`,
// `answersSince`), the archive review's marks, and the chats opened, opened from and shared. Refused as the
// TypeScript refuses while an old store's lookup is being prepared, with the same words, so the pool prepares it.

///|
let closed_cards_pending : String = "closed cards pending:"

///|
let people_time_pending : String = "people time pending:"

///|
/// store.ts ANSWER_CARD_SAMPLE_SIZE, and the old lookups' samples (CLOSED_SAMPLE_LIMIT, PEOPLE_TIME_SAMPLE_LIMIT).
let answer_card_sample : Int = 65

///|
let sample_limit : Double = 65.0

///|
fn num(v : Json) -> Double {
  match v {
    Number(n, ..) => n
    _ => 0.0
  }
}

///|
fn ids_json(ids : Array[Json]) -> Json {
  Json::string(Json::array(ids).stringify())
}

///|
/// Whether a number is an integer (Number.isInteger).
fn is_integer(v : Json) -> Bool {
  v is Number(n, ..) && n == n.floor() && !n.is_inf()
}

// ── where a chat's latest message stands ──

///|
/// legacy-said-build.ts `legacySaidReadHead`: (known, the head row).
fn legacy_said_head(db : @sql.Db, thread : Json) -> (Bool, Map[String, Json]?) raise {
  guard one(db, legacy_said_head_first_sql, [thread]) is Some(first) else { return (true, None) }
  if !(field(first, "n") is Null) {
    return (true, Some(first))
  }
  if one(db, legacy_said_needs_drain_sql, [thread]) is None {
    return (true, one(db, legacy_said_latest_sql, [thread]))
  }
  guard one(db, legacy_said_head_tail_sql, [thread]) is Some(tail) else { return (true, None) }
  if !(field(tail, "n") is Null) {
    return (true, Some(tail))
  }
  (num(field(tail, "count")) < 65.0, None)
}

///|
/// store.ts `saidOf`: a chat's latest message that counts as unread and the latest before it its author did not write.
fn said_of(db : @sql.Db, legacy : Bool, thread : Json) -> Json raise {
  if legacy {
    db.exec("SAVEPOINT said_read")
  }
  defer (if legacy { db.exec("RELEASE said_read") catch { _ => () } })
  let (known, head) = if legacy { legacy_said_head(db, thread) } else { (true, one(db, said_latest_sql, [thread])) }
  if !known {
    raise Refused(503, said_pending + Json::array([thread]).stringify())
  }
  guard head is Some(r) else { return Json::null() }
  let person = field(r, "author_kind") == Json::string("person")
  let state = if person { one(db, said_state_sql, [thread]) } else { None }
  // said-state.ts `saidBoundary`
  let (bknown, bother) = if !person {
    (true, field(r, "n"))
  } else {
    match state {
      Some(s) if field(s, "said_n") == field(r, "n") && field(s, "said_other_known") == Json::number(1.0) =>
        (true, field(s, "said_other_n"))
      Some(s) if field(s, "guard_ready") == Json::number(1.0) && field(s, "guard_author") == field(r, "author") =>
        (true, field(s, "guard_other_n"))
      _ => (false, Json::null())
    }
  }
  let mut other = bother
  if !bknown {
    if legacy && one(db, legacy_said_needs_drain_sql, [thread]) is Some(_) {
      guard one(db, legacy_said_boundary_tail_sql, [thread, field(r, "n"), field(r, "author")]) is Some(near) else {
        raise Refused(503, said_pending + Json::array([thread]).stringify())
      }
      if field(near, "n") is Null && num(field(near, "count")) >= 65.0 {
        raise Refused(503, said_pending + Json::array([thread]).stringify())
      }
      other = field(near, "n")
    } else {
      let nearby = db.all(if legacy { legacy_said_scan_sql } else { said_scan_sql }, [thread, field(r, "n"), Json::number(64.0)])
      match nearby.search_by(p => field(p, "author_kind") != Json::string("person") || field(p, "author") != field(r, "author")) {
        Some(i) => other = field(nearby[i], "n")
        None =>
          if nearby.length() == 64 {
            raise Refused(503, said_pending + Json::array([thread]).stringify())
          }
      }
    }
  }
  { "n": field(r, "n"), "authorKind": field(r, "author_kind"), "author": field(r, "author"), "other": other }
}

// ── sessions' turns and watches ──

///|
/// store.ts `turnSummary` with the turn's id (`latestTurn`): null for a session with no turn.
fn latest_turn(r : Map[String, Json]) -> Json {
  if field(r, "started_at") is Null {
    return Json::null()
  }
  let declared = field(r, "declared")
  let v : Map[String, Json] = {
    "kind": field(r, "kind"),
    "outcome": field(r, "outcome"),
    "declared": match declared { String(d) => Json::string(said_before(d)); _ => Json::null() },
  }
  if declared is String(d) {
    v["ending"] = Json::string(ending_of(d))
  }
  if !(field(r, "need") is Null) {
    v["need"] = field(r, "need")
  }
  if !(field(r, "about_thread") is Null) && !(field(r, "about_n") is Null) && !(field(r, "about_ts") is Null) {
    v["about"] = { "thread": field(r, "about_thread"), "seq": field(r, "about_n"), "ts": field(r, "about_ts") }
  }
  if !(field(r, "wait_seconds") is Null) {
    v["waitSeconds"] = field(r, "wait_seconds")
  }
  if !(field(r, "wait_for") is Null) {
    v["waitFor"] = field(r, "wait_for")
  }
  if !(field(r, "wait_watch") is Null) {
    v["waitWatch"] = Json::boolean(field(r, "wait_watch") == Json::number(1.0))
  }
  v["detail"] = field(r, "detail")
  v["startedAt"] = field(r, "started_at")
  v["endedAt"] = field(r, "ended_at")
  v["id"] = field(r, "turn_id")
  Json::object(v)
}

///|
/// store.ts `sessionActivity` of some sessions: each one's messages not delivered yet and its latest turn.
fn session_activity(db : @sql.Db, keys : Array[String]) -> Map[String, (Json, Json)] raise {
  let out : Map[String, (Json, Json)] = Map([])
  if keys.length() == 0 {
    return out
  }
  for r in db.all("\{session_activity_sql} WHERE s.key IN (SELECT value FROM json_each(?))", [ids_json(keys.map(Json::string))]) {
    out[js_text(field(r, "key"))] = (field(r, "pending"), latest_turn(r))
  }
  out
}

///|
/// store.ts `watching`: the sessions keeping watch, each with its watches' names, since when, and when one last said
/// something; of `sessions` alone, or of all.
fn watching(db : @sql.Db, sessions : Array[String]?) -> Map[String, Json] raise {
  let out : Map[String, Json] = Map([])
  if sessions is Some([]) {
    return out
  }
  let list = match sessions { Some(s) => [ids_json(s.map(Json::string))]; None => [] }
  let running = db.all(if sessions is Some(_) { watching_of_sql } else { watching_all_sql }, list) catch {
    e => {
      guard sql_message(e).contains("no such table: active_watch_jobs") else { raise e }
      db.all(if sessions is Some(_) { running_of_sql } else { jobs_running_sql }, list)
    }
  }
  let by : Map[String, Array[Map[String, Json]]] = Map([])
  for j in running {
    if field(j, "watch") == Json::number(0.0) {
      continue
    }
    let key = js_text(field(j, "session_key"))
    match by.get(key) {
      Some(a) => a.push(j)
      None => by[key] = [j]
    }
  }
  for key, jobs in by {
    let sorted = stable_sort(jobs, (a, b) => {
      let (x, y) = (num(field(a, "started_at")), num(field(b, "started_at")))
      if x < y { -1 } else if x > y { 1 } else { 0 }
    })
    let mut at = -1.0 / 0.0
    for j in sorted {
      let started = num(field(j, "started_at"))
      let said = match one(db, "SELECT at, text FROM job_notices WHERE job_id = ? ORDER BY at DESC, rowid DESC LIMIT ?", [field(j, "id"), Json::number(1.0)]) {
        Some(n) => num(field(n, "at"))
        None => started
      }
      let one_at = if said > started { said } else { started }
      if one_at > at {
        at = one_at
      }
    }
    out[key] = { "names": Json::array(sorted.map(j => field(j, "name"))), "since": field(sorted[0], "started_at"), "at": Json::number(at) }
  }
  out
}

// ── cards ──

///|
/// store.ts `threadsWithCards`.
fn threads_with_cards(db : @sql.Db, threads : Array[Json]) -> Array[Json] raise {
  threads.filter(t => has_cards(db, t)) catch { e => raise e }
}

///|
/// store.ts `requireCardPosts`: the card posts' index of these chats all prepared, else refused naming those that are not.
fn require_card_posts(db : @sql.Db, threads : Array[Json]) -> Unit raise {
  let seen : Set[String] = Set::new()
  let missing : Array[Json] = []
  for t in threads {
    if seen.contains(t.stringify()) {
      continue
    }
    seen.add(t.stringify())
    if !@cards.ready(db, t) {
      missing.push(t)
    }
  }
  if missing.length() > 0 {
    raise Refused(503, card_posts_pending + Json::array(missing).stringify())
  }
}

///|
/// store.ts `askingMessage`: the message an agent's need without a card asks with, while no person has written after
/// it, with the two before it.
fn asking_message(db : @sql.Db, thread : Json, about : Json, from : Json, to : Json) -> (Json, Array[Json])? raise {
  let n = match about {
    Null =>
      match one(db, if @legacy.has_legacy_agent(db) { legacy_asked_during_sql } else { asked_during_sql }, [thread, from, to]) {
        Some(r) => field(r, "n")
        None => Json::null()
      }
    n => n
  }
  if n is Null {
    return None
  }
  let answered = one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", [thread, n]) is Some(_)
  let carded = one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND n = ? AND (card IS NOT NULL OR options IS NOT NULL)", [thread, n]) is Some(_)
  if answered || carded {
    return None
  }
  guard messages_before(db, thread, Json::number(num(n) + 1.0), Some(Json::number(3.0))) is Array(messages) else { return None }
  guard messages.last() is Some(m) else { return None }
  let earlier = messages[:messages.length() - 1].to_array()
  if m.value("n") == Some(n) && m.value("authorKind") == Some(Json::string("agent")) {
    Some((m, earlier))
  } else {
    None
  }
}

// ── cards answered lately ──

///|
fn exists_index(db : @sql.Db, name : String) -> Bool raise {
  exists_in(db, "index", name)
}

///|
/// legacy-closed-cards.ts `hasLegacyClosedCards`.
fn has_legacy_closed(db : @sql.Db) -> Bool raise {
  if !exists_in(db, "table", "legacy_closed_meta") {
    return false
  }
  guard one(db, "SELECT version FROM legacy_closed_meta WHERE id=1", []) is Some(r) && field(r, "version") == Json::number(1.0) else {
    raise Failure("legacy closed-card lookup has an unsupported version")
  }
  true
}

///|
/// legacy-closed-cards.ts `closedCardsReady`.
fn closed_ready(db : @sql.Db, thread : Json) -> Bool raise {
  if exists_index(db, "closed_cards_thread_at") {
    return true
  }
  if has_legacy_closed(db) {
    match one(db, "SELECT CAST(last_n AS TEXT) AS last_n,\n  CAST(end_n AS TEXT) AS end_n,complete FROM legacy_closed_scopes WHERE thread=?", [thread]) {
      Some(s) => return field(s, "complete") == Json::number(1.0)
      None => ()
    }
  }
  one(db, "SELECT 1 AS x FROM closed_cards WHERE thread=? LIMIT 1", [thread]) is None
}

///|
/// legacy-people-since.ts `hasLegacyPeopleSince`.
fn has_legacy_people(db : @sql.Db) -> Bool raise {
  if !exists_in(db, "table", "legacy_people_time_meta") {
    return false
  }
  guard one(db, "SELECT version FROM legacy_people_time_meta WHERE id=1", []) is Some(r) && field(r, "version") == Json::number(1.0) else {
    raise Failure("legacy people-time lookup has an unsupported version")
  }
  true
}

///|
/// legacy-people-since.ts `peopleSinceReady`.
fn people_ready(db : @sql.Db, thread : Json) -> Bool raise {
  if exists_index(db, "entries_people_since") {
    return true
  }
  if !has_legacy_people(db) {
    return false
  }
  match one(db, "SELECT CAST(last_n AS TEXT) AS last_n,\n  CAST(end_n AS TEXT) AS end_n,complete FROM legacy_people_time_scopes WHERE thread=?", [thread]) {
    Some(s) => field(s, "complete") == Json::number(1.0)
    None => false
  }
}

///|
fn people_pending(threads : Array[Json]) -> Refused {
  Refused(503, people_time_pending + Json::array(threads).stringify())
}

///|
/// store.ts `smallPeople`.
fn small_people(db : @sql.Db, thread : Json, since : Json) -> Map[String, Json] raise {
  guard one(db, small_people_has_sql, [thread, since]) is Some(row) else { raise Failure("no sample") }
  if num(field(row, "seen")) >= sample_limit {
    raise people_pending([thread])
  }
  row
}

///|
/// store.ts `hasRecentPeople`; mode "native", "legacy" or "small".
fn has_recent_people(db : @sql.Db, thread : Json, since : Json, mode : String) -> Bool raise {
  if mode == "small" {
    return field(small_people(db, thread, since), "yes") == Json::number(1.0)
  }
  one(db, if mode == "native" { has_answer_people_since_sql } else { legacy_has_people_since_sql }, [thread, since]) is Some(_)
}

///|
/// store.ts `firstRecentPerson`.
fn first_recent_person(db : @sql.Db, thread : Json, since : Json, mode : String) -> Json raise {
  let sql = match mode {
    "native" => first_answer_person_since_sql
    "legacy" => legacy_first_person_since_sql
    _ => small_people_first_sql
  }
  guard one(db, sql, [thread, since]) is Some(row) else { return Json::null() }
  if mode == "small" && num(field(row, "seen")) >= sample_limit {
    raise people_pending([thread])
  }
  field(row, "n")
}

///|
/// store.ts `peopleAfter`.
fn people_after(db : @sql.Db, thread : Json, since : Json, n : Json, mode : String) -> Array[(Json, Json)] raise {
  let sql = match mode {
    "native" => answer_people_after_sql
    "legacy" => legacy_people_after_sql
    _ => small_people_after_sql
  }
  let result = db.all(sql, [thread, since, n])
  if mode == "small" && result.iter().any(r => num(field(r, "seen")) >= sample_limit) {
    raise people_pending([thread])
  }
  result.filter(r => !(field(r, "n") is Null)).map(r => (field(r, "thread"), field(r, "n")))
}

///|
/// store.ts `answersOf`: the people's messages since `since` that each are the first after a card; mode as above, or
/// "cards".
fn answers_of(db : @sql.Db, thread : Json, since : Json, mode : String) -> Array[(Json, Json)] raise {
  if mode != "cards" && !has_recent_people(db, thread, since, mode) {
    return []
  }
  let card_rows = db.all(card_post_sample_sql, [thread])
  if card_rows.length() >= answer_card_sample {
    let time_mode = if mode == "cards" { raise people_pending([thread]) } else { mode }
    let next_card = (n : Json) => match one(db, card_post_next_sql, [thread, n]) {
      Some(r) => field(r, "n")
      None => Json::null()
    }
    let first_card = next_card(Json::number(0.0))
    if first_card is Null {
      return []
    }
    guard one(db, answer_next_person_sql, [thread, first_card]) is Some(first_person) else { return [] }
    let first = if num(field(first_person, "at")) >= num(since) {
      field(first_person, "n")
    } else {
      first_recent_person(db, thread, since, time_mode)
    }
    if first is Null {
      return []
    }
    let out = [(thread, first)]
    let mut n = first
    let mut older = 0
    while true {
      let card = next_card(n)
      if card is Null {
        return out
      }
      guard one(db, answer_next_person_sql, [thread, card]) is Some(person) else { return out }
      n = field(person, "n")
      if num(field(person, "at")) >= num(since) {
        out.push((thread, n))
      } else {
        older += 1
        if older >= answer_card_sample {
          return out + people_after(db, thread, since, n, time_mode)
        }
      }
    }
    return out
  }
  let cards = card_rows.map(r => field(r, "n"))
  let out : Array[(Json, Json)] = []
  for i, card in cards {
    guard one(db, "SELECT n, at FROM entries WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND n > ? ORDER BY n LIMIT 1", [thread, card]) is Some(next) else {
      continue
    }
    if num(field(next, "at")) < num(since) {
      continue
    }
    if i + 1 < cards.length() && num(cards[i + 1]) < num(field(next, "n")) {
      continue
    }
    out.push((thread, field(next, "n")))
  }
  out
}

///|
/// A card answered (store/rows.ts CardAnswer): the question as merged, its card, who and when, and the answer (none: a
/// choice closed it).
priv struct Answer {
  question : Json
  card : Json
  by : Json
  at : Json
  answer : Json
}

///|
/// store.ts `answersSince`: the cards of `threads` answered since `since` (ms), whoever answered them.
fn answers_since(db : @sql.Db, since : Json, threads : Array[Json]) -> Array[Answer] raise {
  if threads.length() == 0 {
    return []
  }
  db.exec("SAVEPOINT answers_since_read")
  defer (db.exec("RELEASE answers_since_read") catch { _ => () })
  let out : Array[Answer] = []
  let scope : Array[Json] = []
  let seen : Set[String] = Set::new()
  for t in threads {
    if !seen.contains(t.stringify()) {
      seen.add(t.stringify())
      scope.push(t)
    }
  }
  let native_closed = exists_index(db, "closed_cards_thread_at")
  let legacy_closed = !native_closed && has_legacy_closed(db)
  let small_closed : Map[String, Array[Map[String, Json]]] = Map([])
  let mut recent_closed : Array[Map[String, Json]]? = None
  if !native_closed {
    let missing = scope.filter(t => !closed_ready(db, t)) catch { e => raise e }
    if missing.length() > 0 && exists_index(db, "closed_cards_at") {
      let recent = try {
        Some(db.all(closed_time_sample_sql, [since, ids_json(scope)]))
      } catch {
        e => {
          guard sql_message(e).contains("no such index: closed_cards_at") else { raise e }
          None
        }
      }
      if recent is Some(recent) && recent.length().to_double() < sample_limit {
        let by : Map[String, Array[Map[String, Json]]] = Map([])
        for row in recent {
          let k = field(row, "thread").stringify()
          if seen.contains(k) {
            match by.get(k) {
              Some(a) => a.push(row)
              None => by[k] = [row]
            }
          }
        }
        let all : Array[Map[String, Json]] = []
        for t in scope {
          if by.get(t.stringify()) is Some(a) {
            all.append(a)
          }
        }
        recent_closed = Some(all)
      }
    }
    if recent_closed is None {
      let waiting : Array[Json] = []
      for t in missing {
        let sample = db.all(closed_chat_sample_sql, [t, since])
        if sample.length().to_double() < sample_limit {
          small_closed[t.stringify()] = sample.filter(r => !(field(r, "n") is Null))
        } else {
          waiting.push(t)
        }
      }
      if waiting.length() > 0 {
        raise Refused(503, closed_cards_pending + Json::array(waiting).stringify())
      }
    }
  }
  let native_people = exists_index(db, "entries_people_since")
  let modes : Map[String, String] = Map([])
  let said = try {
    let relevant : Array[Json] = []
    if native_people {
      let with_people = scope.filter(t => has_recent_people(db, t, since, "native")) catch { e => raise e }
      let carded = threads_with_cards(db, with_people).map(t => t.stringify())
      for t in with_people {
        if carded.contains(t.stringify()) {
          relevant.push(t)
          modes[t.stringify()] = "native"
        }
      }
    } else {
      let waiting : Array[Json] = []
      for t in threads_with_cards(db, scope) {
        if @cards.ready(db, t) && db.all(card_post_sample_sql, [t]).length() < answer_card_sample {
          modes[t.stringify()] = "cards"
          relevant.push(t)
          continue
        }
        let mode = if has_legacy_people(db) && people_ready(db, t) { "legacy" } else { "small" }
        if mode == "small" {
          guard one(db, small_people_has_sql, [t, since]) is Some(probe) else { continue }
          if num(field(probe, "seen")) >= sample_limit {
            waiting.push(t)
            continue
          }
          if field(probe, "yes") != Json::number(1.0) {
            continue
          }
        } else if !has_recent_people(db, t, since, mode) {
          continue
        }
        modes[t.stringify()] = mode
        relevant.push(t)
      }
      if waiting.length() > 0 {
        raise people_pending(waiting)
      }
    }
    require_card_posts(db, relevant)
    let all : Array[(Json, Json)] = []
    for t in relevant {
      all.append(answers_of(db, t, since, modes.get(t.stringify()).unwrap()))
    }
    all
  } catch {
    e => {
      if native_people && sql_message(e).contains("no such index: entries_people_since") {
        raise people_pending(scope)
      }
      raise e
    }
  }
  let card_at_n = (thread : Json, n : Json) => {
    guard one(db, "SELECT card, options FROM entries WHERE thread = ? AND n = ?", [thread, n]) is Some(row) else {
      return None
    }
    guard card_of(field(row, "card"), field(row, "options")) is Some(card) else { return None }
    match merged(db, thread, n) {
      Some(m) => Some((m, card))
      None => None
    }
  }
  for pair in said {
    let (thread, n) = pair
    let asked = match one(db, card_post_before_sql, [thread, n]) {
      Some(r) => field(r, "n")
      None => Json::null()
    }
    if asked is Null {
      continue
    }
    let earlier = one(db, "SELECT 1 AS x FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? AND n < ? LIMIT 1", [thread, asked, n]) is Some(_)
    let closed = one(db, "SELECT 1 AS x FROM closed_cards WHERE thread = ? AND n = ?", [thread, asked]) is Some(_)
    if earlier || closed {
      continue
    }
    guard card_at_n(thread, asked) is Some((question, card)) else { continue }
    guard merged(db, thread, n) is Some(answer) else { continue }
    out.push({
      question,
      card,
      by: answer.value("author").unwrap_or(Json::null()),
      at: answer.value("createdAt").unwrap_or(Json::null()),
      answer,
    })
  }
  let closed_rows = match recent_closed {
    Some(r) => r
    None => {
      let rows : Array[Map[String, Json]] = []
      for t in scope {
        if native_closed {
          let got = db.all(closed_cards_indexed_sql, [t, since]) catch {
            e => {
              if sql_message(e).contains("no such index: closed_cards_thread_at") {
                raise Refused(503, closed_cards_pending + Json::array(scope).stringify())
              }
              raise e
            }
          }
          rows.append(got)
        } else {
          match small_closed.get(t.stringify()) {
            Some(s) => rows.append(s)
            None => if legacy_closed { rows.append(db.all(legacy_closed_cards_sql, [t, since])) }
          }
        }
      }
      rows
    }
  }
  let sorted = stable_sort(closed_rows, (a, b) => {
    let d = num(field(a, "at")) - num(field(b, "at"))
    let d = if d != 0.0 { d } else { num(field(a, "ordering")) - num(field(b, "ordering")) }
    if d < 0.0 { -1 } else if d > 0.0 { 1 } else { 0 }
  })
  for row in sorted {
    guard card_at_n(field(row, "thread"), field(row, "n")) is Some((question, card)) else { continue }
    // Withdrawn by its own agent: no one answered it.
    if question.value("author") == Some(field(row, "viewer")) {
      continue
    }
    out.push({ question, card, by: field(row, "viewer"), at: field(row, "at"), answer: Json::null() })
  }
  out
}

// ── the archive review, chats opened and shared ──

///|
fn last_entry(db : @sql.Db, thread : Json) -> Json raise {
  match one(db, "SELECT MAX(n) AS n FROM entries WHERE thread = ?", [thread]) {
    Some(r) if !(field(r, "n") is Null) => field(r, "n")
    _ => Json::number(0.0)
  }
}

///|
/// store.ts `archiveSuggested`.
fn archive_suggested(db : @sql.Db, thread : Json) -> Bool raise {
  match one(db, "SELECT version FROM archive_suggestions WHERE thread = ?", [thread]) {
    Some(r) if !(field(r, "version") is Null) => field(r, "version") == last_entry(db, thread)
    _ => false
  }
}

///|
/// store.ts `archiveVerdict`: what the latest review found, while the chat stands as it was then.
fn archive_verdict(db : @sql.Db, thread : Json) -> Json raise {
  guard one(db, "SELECT version, at, verdict FROM archive_verdicts WHERE thread = ?", [thread]) is Some(r) else {
    return Json::null()
  }
  if field(r, "version") != last_entry(db, thread) {
    return Json::null()
  }
  match parsed(field(r, "verdict")) {
    Some(Obj(_) as v) =>
      match to_json(v) {
        Object(m) => {
          let out = Map::from_array(m.to_array())
          out["at"] = field(r, "at")
          Json::object(out)
        }
        _ => Json::null()
      }
    Some(Arr(xs)) => {
      // (an array spread as an object: its indices)
      let out : Map[String, Json] = Map([])
      for i, x in xs {
        out[i.to_string()] = to_json(x)
      }
      out["at"] = field(r, "at")
      Json::object(out)
    }
    _ => Json::null()
  }
}

///|
/// views.ts `named`: a chat opened or opened from, as a row names it.
fn opened_named(station : Json, session : Json, title : Json) -> Json {
  let out : Map[String, Json] = Map([])
  if !(station is Null) {
    out["station"] = station
  }
  out["session"] = session
  if !(title is Null) {
    out["title"] = title
  }
  Json::object(out)
}

///|
/// store.ts `openers` and `openedChats` of some sessions (none: of all): by session, the chat it was opened from and
/// those it opened, the first first; none on a database from before.
fn openers_opened(db : @sql.Db, ids : Array[String]?) -> (Map[String, Json], Map[String, Array[Json]]) raise {
  let openers : Map[String, Json] = Map([])
  let opened : Map[String, Array[Json]] = Map([])
  let list = match ids { Some(i) => [ids_json(i.map(Json::string))]; None => [] }
  let base_openers = "SELECT o.child, o.parent_station, o.parent, o.opener_title, p.title AS parent_title FROM opened_chats o LEFT JOIN sessions p ON o.parent_station = '' AND p.key = o.parent"
  let base_opened = "SELECT o.parent, o.child_station, o.child, o.title, c.title AS child_title FROM opened_chats o LEFT JOIN sessions c ON o.child_station = '' AND c.key = o.child"
  let station = (v : Json) => if v == Json::string("") { Json::null() } else { v }
  let or_else = (a : Json, b : Json) => if a is Null { b } else { a }
  let rows = try {
    Some(db.all(if ids is Some(_) { openers_of_sql } else { "\{base_openers} WHERE o.child_station = ''" }, list))
  } catch {
    _ => None
  }
  if rows is Some(rows) {
    for r in rows {
      openers[js_text(field(r, "child"))] = opened_named(station(field(r, "parent_station")), field(r, "parent"), or_else(field(r, "opener_title"), field(r, "parent_title")))
    }
  }
  let rows = try {
    Some(db.all(if ids is Some(_) { opened_of_sql } else { "\{base_opened} WHERE o.parent_station = '' ORDER BY o.created_at, o.rowid" }, list))
  } catch {
    _ => None
  }
  if rows is Some(rows) {
    for r in rows {
      let item = opened_named(station(field(r, "child_station")), field(r, "child"), or_else(field(r, "title"), field(r, "child_title")))
      let key = js_text(field(r, "parent"))
      match opened.get(key) {
        Some(a) => a.push(item)
        None => opened[key] = [item]
      }
    }
  }
  (openers, opened)
}

///|
/// store.ts `chatShares` of some sessions (none: of all), as a row says them: the workspaces each is still shared with
/// (used within 6 hours, rows.ts `liveShare`) and whether they may write.
fn chat_shares(db : @sql.Db, ids : Array[String]?, now : Double) -> Map[String, Json] raise {
  let out : Map[String, Json] = Map([])
  let rows = try {
    match ids {
      Some(i) => db.all(shares_of_sql, [ids_json(i.map(Json::string))])
      None => db.all("SELECT * FROM chat_shares", [])
    }
  } catch {
    _ => return out
  }
  for r in rows {
    let to = match parsed(field(r, "shared")) {
      Some(Arr(xs)) => xs
      _ => []
    }
    let live : Array[Json] = []
    for t in to {
      guard jget(Some(t), "workspace") is Some(Str(ws)) else { continue }
      let used = match jget(Some(t), "used") {
        Some(Num(u)) => u
        _ => num(field(r, "at"))
      }
      if now - used < 6.0 * 3600000.0 {
        live.push(Json::string(@jsjson.text(ws)))
      }
    }
    if live.length() > 0 {
      out[js_text(field(r, "session"))] = { "to": Json::array(live), "write": Json::boolean(field(r, "write") == Json::number(1.0)) }
    }
  }
  out
}
