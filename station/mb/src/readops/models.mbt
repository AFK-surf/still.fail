// What models cost, as the usage page counts it (station/src/read/usage.ts `price`, `cost`, `priceTable`): the model
// catalog's prices (accounts/catalog.ts, as the pool gives it: `catalog`, kept from one read to the next), else the
// station's own table; a model by what it is, however it is spelt (client/core-ts/src/shapes/model.ts `key`).

///|
/// What the model catalog said last, by model key (catalog.ts `catalog().models`): given by the pool with a read as it
/// changes (read/worker.ts `learn`), kept until it changes again.
pub let model_catalog : Ref[Map[String, Json]] = { val: Map([]) }

///|
/// catalog.ts `learn` as the worker takes the pool's snapshot: what it names, in place of what it named before.
pub fn learn_catalog(models : Json) -> Unit {
  let next : Map[String, Json] = Map([])
  if models is Object(m) {
    for k, v in m {
      next[k] = v
    }
  }
  model_catalog.val = next
}

///|
fn sub(s : String, start : Int, end : Int) -> String {
  s.view(start_offset=start, end_offset=end).to_owned()
}

///|
fn from_at(s : String, start : Int) -> String {
  s.view(start_offset=start).to_owned()
}

///|
/// `s.split(sep)` of one character or more.
fn split_on(s : String, sep : String) -> Array[String] {
  let out = []
  let mut rest = s
  while rest.find(sep) is Some(at) {
    out.push(sub(rest, 0, at))
    rest = from_at(rest, at + sep.length())
  }
  out.push(rest)
  out
}

///|
fn last_index(s : String, part : String) -> Int? {
  let mut found = None
  let mut from = 0
  while from <= s.length() - part.length() {
    match from_at(s, from).find(part) {
      Some(at) => {
        found = Some(from + at)
        from = from + at + 1
      }
      None => break
    }
  }
  found
}

///|
fn ascii_digits(s : String) -> Bool {
  s.length() > 0 && s.iter().all(c => c >= '0' && c <= '9')
}

///|
fn ascii_alpha(s : String) -> Bool {
  s.length() > 0 && s.iter().all(c => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
}

///|
/// model.ts `stamp`: a version stamp, `<digits>:<digits>`.
fn version_stamp(s : String) -> Bool {
  match s.find(":") {
    Some(colon) => ascii_digits(sub(s, 0, colon)) && ascii_digits(from_at(s, colon + 1))
    None => false
  }
}

///|
let agy_levels : Array[String] = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]

///|
let devin_levels : Array[String] = ["low", "medium", "high", "xhigh", "max"]

///|
fn level_of(levels : Array[String], s : String) -> String? {
  for l in levels {
    if s.has_suffix("-" + l) && s.length() > l.length() + 1 {
      return Some(l)
    }
  }
  None
}

///|
/// model.ts `splitAgyTier`: an Antigravity tiered model id's base model, where it ends in a thinking level.
pub fn split_agy_tier(id : String) -> String? {
  let trimmed = @jscase.trim(id)
  match level_of(agy_levels, trimmed) {
    Some(l) => Some(sub(trimmed, 0, trimmed.length() - l.length() - 1))
    None => None
  }
}

///|
/// model.ts `splitDevinFusion`: a Devin Fusion model's normalised name.
fn devin_fusion_model(id : String) -> String? {
  let trimmed = @jscase.trim(id)
  guard trimmed.has_prefix("fusion-") else { return None }
  let mark = "-sidekick-"
  let at = match from_at(trimmed, 7).find(mark) {
    Some(a) => a + 7
    None => return None
  }
  if at <= 7 || at + mark.length() >= trimmed.length() {
    return None
  }
  let raw_lead = sub(trimmed, 7, at)
  let side = from_at(trimmed, at + mark.length())
  let lead = match level_of(devin_levels, raw_lead) {
    Some(l) => sub(raw_lead, 0, raw_lead.length() - l.length() - 1)
    None => raw_lead
  }
  Some("fusion-\{lead}-sidekick-\{side}")
}

///|
/// model.ts `key`: what a model is, however it is spelt: lower case, without its provider's prefix, region, version
/// stamp or date.
pub fn model_key(id : String) -> String {
  let lower = @jscase.lower(@jscase.trim(id))
  let (base, context) = match lower.find("[") {
    Some(at) => (sub(lower, 0, at), from_at(lower, at))
    None => (lower, "")
  }
  let mut m = match last_index(base, "/") {
    Some(at) => from_at(base, at + 1)
    None => base
  }
  m = match m.find("@") {
    Some(at) => sub(m, 0, at)
    None => m
  }
  while m.find(".") is Some(dot) {
    let head = sub(m, 0, dot)
    let rest = from_at(m, dot + 1)
    if !ascii_alpha(head) || rest == "" {
      break
    }
    m = rest
  }
  if last_index(m, "-v") is Some(v) && version_stamp(from_at(m, v + 2)) {
    m = sub(m, 0, v)
  }
  let parts = split_on(m, "-")
  let n = parts.length()
  let digits = (s : String, k : Int) => s.length() == k && ascii_digits(s)
  if n > 1 && digits(parts[n - 1], 8) {
    m = parts[0:n - 1].to_array().join("-")
  } else if n > 3 && digits(parts[n - 3], 4) && digits(parts[n - 2], 2) && digits(parts[n - 1], 2) {
    m = parts[0:n - 3].to_array().join("-")
  }
  if m.has_prefix("fusion-") && m.contains("-sidekick-") {
    if devin_fusion_model(m) is Some(model) {
      m = model
    }
  }
  m + context
}

///|
/// catalog.ts `facts`: what the catalog says of a model, however it is spelt (its effort level falls back to the
/// model); none for one it does not name.
fn facts(model : String) -> Json? {
  let key = model_key(model)
  let bare = match key.find("[") {
    Some(at) => sub(key, 0, at)
    None => key
  }
  match model_catalog.val.get(bare) {
    Some(f) => Some(f)
    None =>
      match split_agy_tier(bare) {
        Some(m) => model_catalog.val.get(m)
        None => None
      }
  }
}

///|
/// A model's API prices, dollars per million tokens: input, output, what reading the cache costs.
priv struct Price {
  input : Double
  output : Double
  cache_read : Double
}

///|
/// usage.ts PRICES: the standard short-context list prices, for a model the catalog has no price for. Longer names
/// first.
let prices : Array[(String, Price)] = [
  ("gpt-6-astra", { input: 10.0, output: 50.0, cache_read: 1.0 }),
  ("gpt-6.1-sol", { input: 2.0, output: 10.0, cache_read: 0.1 }),
  ("gpt-6.1-terra", { input: 1.0, output: 5.0, cache_read: 0.05 }),
  ("gpt-6-sol", { input: 2.0, output: 10.0, cache_read: 0.2 }),
  ("gpt-6-luna", { input: 0.1, output: 0.5, cache_read: 0.01 }),
  ("gpt-5.6-sol", { input: 4.0, output: 20.0, cache_read: 0.4 }),
  ("claude-fable-5-2", { input: 8.0, output: 40.0, cache_read: 0.2 }),
  ("claude-fable-5-1", { input: 10.0, output: 50.0, cache_read: 0.25 }),
  ("claude-mythos-5-1", { input: 10.0, output: 50.0, cache_read: 0.25 }),
  ("claude-fable-5", { input: 10.0, output: 50.0, cache_read: 1.0 }),
  ("claude-mythos-5", { input: 10.0, output: 50.0, cache_read: 1.0 }),
  ("claude-opus-5-5", { input: 4.0, output: 20.0, cache_read: 0.2 }),
  ("claude-opus-5", { input: 5.0, output: 25.0, cache_read: 0.5 }),
  ("claude-opus-4-8", { input: 5.0, output: 25.0, cache_read: 0.5 }),
  ("claude-opus-4-7", { input: 5.0, output: 25.0, cache_read: 0.5 }),
  ("claude-opus-4-6", { input: 5.0, output: 25.0, cache_read: 0.5 }),
  ("claude-opus-4-5", { input: 5.0, output: 25.0, cache_read: 0.5 }),
  ("claude-sonnet-5-5", { input: 2.0, output: 10.0, cache_read: 0.1 }),
  ("claude-sonnet-5", { input: 2.0, output: 10.0, cache_read: 0.2 }),
  ("claude-sonnet-4-6", { input: 3.0, output: 15.0, cache_read: 0.3 }),
  ("claude-sonnet-4-5", { input: 3.0, output: 15.0, cache_read: 0.3 }),
  ("claude-haiku-4-5", { input: 1.0, output: 5.0, cache_read: 0.1 }),
]

///|
/// usage.ts `price`: a model's prices, the catalog's, else the station's table's; none without a list price in either.
fn price(model : String) -> Price? {
  if facts(model) is Some(f) && f.value("cost") is Some(Object(_) as told) {
    let n = (k : String) => match told.value(k) { Some(Number(v, ..)) => Some(v); _ => None }
    match (n("input"), n("output")) {
      (Some(input), Some(output)) => return Some({ input, output, cache_read: n("cacheRead").unwrap_or(input) })
      _ => ()
    }
  }
  let name = model_key(model)
  let listed = (candidate : String) => {
    for p in prices {
      if candidate == p.0 || (candidate.has_prefix(p.0) && from_at(candidate, p.0.length()).has_prefix("[")) {
        return Some(p.1)
      }
    }
    None
  }
  if listed(name) is Some(p) {
    return Some(p)
  }
  let at = name.find("[")
  let bare = match at {
    Some(a) => sub(name, 0, a)
    None => name
  }
  match split_agy_tier(bare) {
    None => None
    Some(model) =>
      listed(
        match at {
          Some(a) => model + from_at(name, a)
          None => model
        },
      )
  }
}

///|
/// A day's calls of one model, added up (store/usage.ts UsageGroup).
priv struct Group {
  day : String
  session : Json
  thread : Json
  person : Json
  profile : Json
  runtime : Json
  model : Json
  fast : Bool
  calls : Double
  input : Double
  cache_read : Double
  cache_write : Double
  cache_write_long : Double
  output : Double
}

///|
/// usage.ts `cost`: what a group's calls would cost at its model's API prices, dollars, in the same order of operations.
fn cost(g : Group) -> Json {
  guard g.model is String(model) else { return Json::null() }
  guard price(model) is Some(p) else { return Json::null() }
  let tokens = g.input * p.input + g.cache_write * p.input * 1.25 + g.cache_write_long * p.input * 2.0 +
    g.cache_read * p.cache_read +
    g.output * p.output
  Json::number(tokens / 1.0e6 * (if g.fast { 2.0 } else { 1.0 }))
}

///|
/// usage.ts `priceTable`: the prices `cost` uses, of the station's table and of the models the rows name.
fn price_table(note : String, models : Array[Json]) -> Json {
  let keys : Array[String] = []
  let seen : Set[String] = Set::new()
  let add = (k : String) => if !seen.contains(k) {
    seen.add(k)
    keys.push(k)
  }
  for p in prices {
    add(p.0)
  }
  for m in models {
    if m is String(s) {
      add(split_on(model_key(s), "[")[0])
    }
  }
  let rows : Array[Json] = []
  for model in keys {
    guard price(model) is Some(p) else { continue }
    let claude = model.has_prefix("claude-")
    rows.push({
      "model": Json::string(model),
      "input": Json::number(p.input),
      "cacheRead": Json::number(p.cache_read),
      "cacheWrite": if claude { Json::number(p.input * 1.25) } else { Json::null() },
      "cacheWriteLong": if claude { Json::number(p.input * 2.0) } else { Json::null() },
      "output": Json::number(p.output),
    })
  }
  { "note": Json::string(note), "rows": Json::array(rows) }
}
