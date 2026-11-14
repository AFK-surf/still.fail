// What of a list a client does not hold as it is (station/src/read/digest.ts `changedOf`, POST /changed/<list>): the
// list as the client's runtimes see it (station/src/read/runtime-view.ts `runtimeList`), its ids in order, and the
// rows whose digest (the core's own, client/core-ts/src/digest.ts) is not what the client holds.

///|
/// runtime-view.ts `runtimeList` of the three lists asked so: what of the client shapes (client/core-ts/src/shapes)
/// names a runtime there is a session's `runtime` (`Session`) and each agent's of a chat's row (`ChatItem.agents`,
/// `RowAgent.runtime`); a session of a runtime the client does not have is left out, and so is such an agent of a row.
/// A thread (`ChatThread`) names none. test/mb-reader-changed.test.ts holds this to the shapes.
fn runtime_list(op : String, value : Json, runtimes : Array[String]?) -> Json {
  guard runtimes is Some(supported) else { return value }
  let unsupported = (v : Json?) => v is Some(String(r)) && !supported.contains(r)
  match (op, value) {
    ("sessions", Array(rows)) => Json::array(rows.filter(r => !(r is Object(o) && unsupported(o.get("runtime")))))
    ("chats", Array(rows)) =>
      Json::array(
        rows.map(r => match r {
          Object(o) =>
            match o.get("agents") {
              Some(Array(agents)) => {
                let out = Map::from_iter(o.iter())
                out["agents"] = Json::array(agents.filter(a => !(a is Object(x) && unsupported(x.get("runtime")))))
                Json::object(out)
              }
              _ => r
            }
          _ => r
        }),
      )
    _ => value
  }
}

///|
/// Two strings in the order of their UTF-16 code units (Array.prototype.sort's).
fn by_units(a : String, b : String) -> Int {
  let n = @cmp.minimum(a.length(), b.length())
  for i in 0..<n {
    let x = a.unsafe_charcode_at(i)
    let y = b.unsafe_charcode_at(i)
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
/// JSON.stringify of a string or a number.
fn json_text(v : Json) -> String {
  match v {
    String(s) => @jsjson.stringify(Str(@jsjson.units(s)))
    Number(n, ..) => @jsjson.stringify(Num(n))
    True => "true"
    False => "false"
    _ => "null"
  }
}

///|
/// digest.ts `canonical`: JSON with every object's keys sorted.
fn canonical(out : StringBuilder, v : Json) -> Unit {
  match v {
    Array(xs) => {
      out.write_char('[')
      for i, x in xs {
        if i > 0 {
          out.write_char(',')
        }
        canonical(out, x)
      }
      out.write_char(']')
    }
    Object(o) => {
      let keys = o.keys().collect()
      keys.sort_by(by_units)
      out.write_char('{')
      for i, k in keys {
        if i > 0 {
          out.write_char(',')
        }
        out.write_string(json_text(Json::string(k)))
        out.write_char(':')
        canonical(out, o.get(k).unwrap())
      }
      out.write_char('}')
    }
    _ => out.write_string(json_text(v))
  }
}

///|
/// digest.ts `hash`: cyrb53, 53 bits of a string's UTF-16 units.
fn cyrb53(s : String) -> Int64 {
  let mut h1 = -559038737 // 0xdeadbeef
  let mut h2 = 0x41c6ce57
  for i in 0..<s.length() {
    let c = s.unsafe_charcode_at(i)
    h1 = (h1 ^ c) * -1640531535 // 2654435761
    h2 = (h2 ^ c) * 1597334677
  }
  h1 = (h1 ^ (h1.reinterpret_as_uint() >> 16).reinterpret_as_int()) * -2048144789 // 2246822507
  h1 = h1 ^ ((h2 ^ (h2.reinterpret_as_uint() >> 13).reinterpret_as_int()) * -1028477387) // 3266489909
  h2 = (h2 ^ (h2.reinterpret_as_uint() >> 16).reinterpret_as_int()) * -2048144789
  h2 = h2 ^ ((h1 ^ (h1.reinterpret_as_uint() >> 13).reinterpret_as_int()) * -1028477387)
  4294967296L * (2097151 & h2).to_int64() + h1.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
}

///|
fn base36(n : Int64) -> String {
  if n == 0L {
    return "0"
  }
  let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  let out = []
  let mut m = n
  while m > 0L {
    out.push(digits.unsafe_charcode_at((m % 36L).to_int()))
    m = m / 36L
  }
  let b = StringBuilder::new()
  for i = out.length() - 1; i >= 0; i = i - 1 {
    b.write_char(out[i].unsafe_to_char())
  }
  b.to_string()
}

///|
/// digest.ts `digest`: a row's canonical JSON hashed, in base 36.
pub fn digest(v : Json) -> String {
  let out = StringBuilder::new()
  canonical(out, v)
  base36(cyrb53(out.to_string()))
}

///|
/// String(key), as the held rows are named by.
fn key_text(v : Json) -> String {
  match v {
    String(s) => s
    Array(_) => "" // (as String([...]) of what a list's id is never)
    Object(_) => "[object Object]"
    _ => json_text(v)
  }
}

///|
/// digest.ts `changedOf`: `list` as the client's runtimes see it, its ids (`id`) in order, and its rows not held so.
pub fn changed_of(op : String, list : Json, args : Json) -> Json {
  let id = match args.value("id") { Some(String(i)) => i; _ => "" }
  let runtimes = match args.value("runtimes") {
    Some(Array(rs)) => Some(rs.filter_map(r => if r is String(s) { Some(s) } else { None }))
    _ => None
  }
  let have : Map[String, Json] = match args.value("held") {
    Some(Object(h)) => Map::from_iter(h.iter())
    _ => Map([])
  }
  let rows = match runtime_list(op, list, runtimes) {
    Array(rows) => rows
    _ => []
  }
  let order = []
  let out = []
  for row in rows {
    let key = match row {
      Object(o) => o.get(id)
      _ => None
    }
    order.push(key.unwrap_or(Json::null()))
    match key {
      None | Some(Null) => out.push(row)
      Some(k) =>
        match have.get(key_text(k)) {
          Some(String(d)) if d == digest(row) => ()
          _ => out.push(row)
        }
    }
  }
  { "order": Json::array(order), "rows": Json::array(out) }
}
