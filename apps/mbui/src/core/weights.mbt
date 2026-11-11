// Where a value's bytes are, by field: what a topic's value weighs and which of its fields weigh most, said with the
// bar's timing (still.fail's src/stillfail/reports.mbt) so that what a page is sent can be set beside what it draws.
// Names and numbers alone: a field's path as the shapes name it (client/core-ts/src/shapes/schema.ts), a list's items
// as one (`days[].items[].people`), a key that is no field's name (a map by an id, an address, a name) as `{}`; never a
// value. Counted as the JSON's text would be long (a string by its UTF-8 bytes, unescaped), with no text made.

///|
/// How deep a path goes (fields; a list's items are of their list's depth).
let weights_deep : Int = 4

///|
/// Whether `k` reads as a field's name (letters alone, 24 at most): another key is one of a map's.
fn field_name(k : String) -> Bool {
  let n = k.length()
  if n == 0 || n > 24 {
    return false
  }
  for i in 0..<n {
    let ch = k.unsafe_get(i).to_int()
    if !((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)) {
      return false
    }
  }
  true
}

///|
/// How many bytes `s` is in UTF-8, by its UTF-16 units (a pair of surrogates four).
fn utf8_bytes(s : String) -> Int {
  let mut n = 0
  for i in 0..<s.length() {
    let u = s.unsafe_get(i).to_int()
    n += if u < 0x80 {
      1
    } else if u < 0x800 {
      2
    } else if u >= 0xD800 && u <= 0xDFFF {
      // (half of a pair: four bytes the two)
      2
    } else {
      3
    }
  }
  n
}

///|
/// How long `j`'s JSON is (bytes, its strings unescaped), each path under `path` at most `weights_deep` fields deep
/// added to `by` with what is under it; `path` itself too unless `own` says not (a list's item: its list has it).
fn weigh(j : Json, path : String, deep : Int, by : Map[String, Int], own? : Bool = true) -> Int {
  let n = match j {
    Null => 4
    True => 4
    False => 5
    Number(_, ..) => j.stringify().length()
    String(s) => utf8_bytes(s) + 2
    Array(a) => {
      let mut n = 2
      // (its items one path)
      let under = path + "[]"
      for i, x in a {
        n += weigh(x, under, deep, by, own=false) + (if i > 0 { 1 } else { 0 })
      }
      n
    }
    Object(m) => {
      let mut n = 2
      // (a map by something else than fields' names: its keys one)
      let fields = m.length() <= 48 && m.keys().all(field_name)
      let mut i = 0
      for k, x in m {
        let under = if !fields {
          path + "{}"
        } else if path == "" {
          k
        } else {
          path + "." + k
        }
        n += utf8_bytes(k) + 3 + weigh(x, under, deep + 1, by) + (if i > 0 { 1 } else { 0 })
        i += 1
      }
      n
    }
  }
  if own && path != "" && deep <= weights_deep {
    by[path] = by.get(path).unwrap_or(0) + n
  }
  n
}

///|
/// What `j` weighs (the bytes of its JSON), and its `most` heaviest paths with what each weighs, the heaviest first (of
/// as heavy, by name): a path's weight has what is under it, so a list and what makes it heavy both show.
pub fn weights(j : Json, most? : Int = 12) -> (Int, Array[(String, Int)]) {
  let by : Map[String, Int] = Map([])
  let n = weigh(j, "", 0, by)
  let all = by.to_array()
  all.sort_by(fn(a, b) {
    let w = b.1.compare(a.1)
    if w != 0 {
      w
    } else {
      a.0.compare(b.0)
    }
  })
  (n, if all.length() > most { all[:most].to_owned() } else { all })
}
