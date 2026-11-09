// What a search finds among documents, as station/src/search/match.ts finds it: the query's words (white space as a
// regular expression's `\s`, case as JavaScript's toLowerCase), every word in a document's title or body, whom it is
// for, and each kind's best `offset + limit` kept, those whose title has the first word first, then the newest, then
// in the order they came.

///|
/// A document (match.ts `Doc`): `ws` None the station's home workspace, `*` every workspace's; `refs` what opens it,
/// in the order the TypeScript writes them.
pub(all) struct Doc {
  key : String
  kind : String
  ws : String?
  scope : String?
  title : String
  body : String
  at : Double?
  refs : Array[(String, Json)]
}

///|
/// Whom a search is for (match.ts `Asker`).
pub(all) struct Asker {
  workspace : String
  home : Bool
  scopes : Array[String]
}

///|
pub fn Asker::from_json(j : Json) -> Asker {
  let workspace = match j {
    { "workspace": String(w), .. } => w
    _ => ""
  }
  let home = j is { "home": True, .. }
  let scopes = match j {
    { "scopes": Array(xs), .. } => xs.filter_map(x => if x is String(s) { Some(s) } else { None })
    _ => []
  }
  { workspace, home, scopes }
}

///|
/// match.ts `terms`.
pub fn terms(query : String) -> Array[String] {
  let out : Array[String] = []
  for t in @jscase.split_by(@jscase.trim(query), @jscase.is_space) {
    let w = @jscase.lower(t)
    if w != "" && !out.contains(w) {
      out.push(w)
    }
  }
  if out.length() > 8 {
    out.truncate(8)
  }
  out
}

///|
let before : Int = 80

///|
let after : Int = 240

///|
/// match.ts `excerpt`: the place of the first of the words in the lowered flat text, cut from the flat text there.
pub fn excerpt(body : String, words : Array[String]) -> String {
  let flat = flatten(body)
  let lower = @jscase.lower(flat)
  let mut at = -1
  for w in words {
    if lower.find(w) is Some(i) && (at < 0 || i < at) {
      at = i
    }
  }
  if at < 0 {
    at = 0
  }
  let from = if at - before > 0 { at - before } else { 0 }
  let to = if at + after < flat.length() { at + after } else { flat.length() }
  let from = if from > flat.length() { flat.length() } else { from }
  let cut = if to > from { flat.view(start_offset=from, end_offset=to).to_owned() } else { "" }
  (if from > 0 { "…" } else { "" }) + cut + (if to < flat.length() { "…" } else { "" })
}

///|
/// `body.replace(/\s+/gu, " ").trim()`.
fn flatten(body : String) -> String {
  let out = StringBuilder::new()
  let n = body.length()
  let mut i = 0
  while i < n {
    let c = body.unsafe_charcode_at(i)
    if @jscase.is_space(c) {
      out.write_char(' ')
      while i < n && @jscase.is_space(body.unsafe_charcode_at(i)) {
        i += 1
      }
    } else {
      out.write_char(c.unsafe_to_char())
      i += 1
    }
  }
  @jscase.trim(out.to_string())
}

///|
/// match.ts `sees`.
pub fn sees(ws : String?, scope : String?, asker : Asker) -> Bool {
  let place = match ws {
    Some("*") => true
    Some(w) => w == asker.workspace
    None => asker.home
  }
  place &&
  (match scope {
    None => true
    Some(s) => asker.scopes.contains(s)
  })
}

///|
/// match.ts `has`.
pub fn has(text : String, words : Array[String]) -> Bool {
  let lower = @jscase.lower(text)
  words.iter().all(w => lower.contains(w))
}

///|
priv struct Ranked {
  titled : Bool
  at : Double?
  order : Int
  hit : Json
}

///|
/// match.ts `compare`: negative when `a` comes first.
fn compare(a : Ranked, b : Ranked) -> Int {
  let titled = (if b.titled { 1 } else { 0 }) - (if a.titled { 1 } else { 0 })
  if titled != 0 {
    return titled
  }
  let none = (if a.at is None { 1 } else { 0 }) - (if b.at is None { 1 } else { 0 })
  if none != 0 {
    return none
  }
  let d = b.at.unwrap_or(0.0) - a.at.unwrap_or(0.0)
  if d < 0.0 {
    return -1
  }
  if d > 0.0 {
    return 1
  }
  a.order - b.order
}

///|
priv struct Kind {
  heap : Array[Ranked]
  mut count : Int
}

///|
/// match.ts `Pages`: each kind's worst kept at its heap's root.
pub struct Pages {
  priv words : Array[String]
  priv asker : Asker
  priv limit : Int
  priv offset : Int
  priv want : Int
  priv kinds : Map[String, Kind]
  priv mut order : Int
}

///|
pub fn Pages::new(words : Array[String], asker : Asker, limit : Int, offset : Int) -> Pages {
  { words, asker, limit, offset, want: offset + limit, kinds: Map([]), order: 0 }
}

///|
/// A limit as the worker clamps it (`Math.max(1, Math.min(limit ?? 8, 200))`).
pub fn clamp_limit(v : Json?) -> Int {
  match v {
    Some(Number(n, ..)) => if n.is_nan() { 1 } else if n < 1.0 { 1 } else if n > 200.0 { 200 } else { n.to_int() }
    _ => 8
  }
}

///|
/// An offset as the worker clamps it (`Math.max(0, offset ?? 0)`).
pub fn clamp_offset(v : Json?) -> Int {
  match v {
    Some(Number(n, ..)) => if n.is_nan() || n < 0.0 { 0 } else { n.to_int() }
    _ => 0
  }
}

///|
fn at_json(at : Double?) -> Json {
  match at {
    Some(v) => Json::number(v)
    None => Json::null()
  }
}

///|
pub fn Pages::add(self : Pages, d : Doc) -> Unit {
  if !sees(d.ws, d.scope, self.asker) {
    return
  }
  if !has(d.title + "\n" + d.body, self.words) {
    return
  }
  let list = match self.kinds.get(d.kind) {
    Some(k) => k
    None => {
      let k = { heap: [], count: 0 }
      self.kinds[d.kind] = k
      k
    }
  }
  list.count += 1
  let order = self.order
  self.order += 1
  let titled = @jscase.lower(d.title).contains(self.words[0])
  let key = { titled, at: d.at, order, hit: Json::null() }
  let heap = list.heap
  if heap.length() >= self.want && compare(key, heap[0]) >= 0 {
    return
  }
  let source = if d.kind == "chat" && has(d.title, self.words) { d.title } else { d.body }
  let hit : Map[String, Json] = Map([])
  for r in d.refs {
    hit[r.0] = r.1
  }
  hit["kind"] = Json::string(d.kind)
  hit["key"] = Json::string(d.key)
  hit["title"] = Json::string(d.title)
  hit["text"] = Json::string(excerpt(source, self.words))
  hit["at"] = at_json(d.at)
  let ranked = { ..key, hit: Json::object(hit) }
  if heap.length() < self.want {
    heap.push(ranked)
    let mut i = heap.length() - 1
    while i > 0 {
      let parent = (i - 1) / 2
      if compare(heap[i], heap[parent]) <= 0 {
        break
      }
      let t = heap[i]
      heap[i] = heap[parent]
      heap[parent] = t
      i = parent
    }
  } else {
    heap[0] = ranked
    let mut i = 0
    while true {
      let left = i * 2 + 1
      let right = left + 1
      if left >= heap.length() {
        break
      }
      let worst = if right < heap.length() && compare(heap[right], heap[left]) > 0 { right } else { left }
      if compare(heap[worst], heap[i]) <= 0 {
        break
      }
      let t = heap[i]
      heap[i] = heap[worst]
      heap[worst] = t
      i = worst
    }
  }
}

///|
/// The groups, by kind in UTF-16 order (JavaScript's sort), each its page.
pub fn Pages::result(self : Pages) -> Array[Json] {
  let names = self.kinds.keys().collect()
  names.sort_by((a, b) => compare_units(a, b))
  let out : Array[Json] = []
  for name in names {
    guard self.kinds.get(name) is Some(k) else { continue }
    k.heap.sort_by(compare)
    let hits : Array[Json] = []
    for i = self.offset; i < k.heap.length() && i < self.offset + self.limit; i = i + 1 {
      hits.push(k.heap[i].hit)
    }
    if hits.length() > 0 {
      out.push({ "kind": Json::string(name), "more": Json::boolean(k.count > self.want), "hits": Json::array(hits) })
    }
  }
  out
}

///|
/// Strings by their UTF-16 units, as JavaScript compares them.
pub fn compare_units(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let d = a.unsafe_charcode_at(i) - b.unsafe_charcode_at(i)
    if d != 0 {
      return d
    }
  }
  a.length() - b.length()
}

///|
/// One search asked of the program (search/worker.ts `answer`, its execution histories aside): its groups.
pub async fn answer(
  db : @sql.Db,
  host : @host.Host,
  data : String,
  sep : String,
  told : Json,
  cancelled : () -> Bool,
) -> Array[Json] {
  let query = match told {
    { "query": String(q), .. } => q
    _ => ""
  }
  let words = terms(query)
  if words.length() == 0 {
    return []
  }
  let kinds = match told {
    { "kinds": Array(ks), .. } if ks.length() > 0 => Some(ks.filter_map(k => if k is String(s) { Some(s) } else { None }))
    _ => None
  }
  let asker = Asker::from_json(told.value("asker").unwrap_or(Json::null()))
  let pages = Pages::new(words, asker, clamp_limit(told.value("limit")), clamp_offset(told.value("offset")))
  let said = [false, false]
  let reading : Ref[Reading?] = Ref(None)
  let pause = async fn() {
    if reading.val is Some(r) {
      let (scope, sessions) = r.pending()
      if scope && !said[0] {
        said[0] = true
        host.say(({ "scopePending": true } : Json).stringify())
      }
      if sessions && !said[1] {
        said[1] = true
        host.say(({ "sessionListPending": true } : Json).stringify())
      }
    }
    @effect.pause()
    if cancelled() {
      fail("the search took too long")
    }
  }
  let r = Reading::new(db, host, data, sep, kinds, asker, told is { "archived": True, .. }, words, d => pages.add(d), pause)
  reading.val = Some(r)
  r.run()
  pause()
  pages.result()
}
