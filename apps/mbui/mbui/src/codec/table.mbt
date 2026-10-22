// Data written as text: the rows of a CSV (or a TSV), and JSON written out to be read.

///|
/// The rows of a CSV (or TSV: `sep` a tab), quoted fields and their doubled quotes as RFC 4180 has them, lines ending
/// in \n, \r\n or \r; no more than `limit` rows.
pub fn parse_csv(s : String, sep : Char, limit : Int) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let field = StringBuilder()
  let mut empty = true
  let mut quoted = false
  let chars : Array[Char] = []
  for ch in s {
    chars.push(ch)
  }
  let mut i = 0
  while i < chars.length() && rows.length() < limit {
    let ch = chars[i]
    if quoted {
      if ch == '"' && i + 1 < chars.length() && chars[i + 1] == '"' {
        field.write_char('"')
        i += 1
      } else if ch == '"' {
        quoted = false
      } else {
        field.write_char(ch)
      }
    } else if ch == '"' && empty {
      quoted = true
      empty = false
    } else if ch == sep {
      row.push(field.to_string())
      field.reset()
      empty = true
    } else if ch == '\n' || ch == '\r' {
      if ch == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 1
      }
      row.push(field.to_string())
      rows.push(row)
      row = []
      field.reset()
      empty = true
    } else {
      field.write_char(ch)
      empty = false
    }
    i += 1
  }
  if (!empty || row.length() > 0) && rows.length() < limit {
    row.push(field.to_string())
    rows.push(row)
  }
  rows
}

///|
/// JSON written out to be read: an object's members and an array's items a line each, two spaces in a level, `": "`
/// after a key; an empty one as `{}` or `[]`.
pub fn pretty_json(v : Json) -> String {
  pretty_at(v, 0)
}

///|
fn pretty_at(v : Json, depth : Int) -> String {
  let pad = fn(d : Int) -> String {
    let sb = StringBuilder()
    for _ in 0..<d {
      sb.write_string("  ")
    }
    sb.to_string()
  }
  match v {
    Object(m) => {
      if m.size() == 0 {
        return "{}"
      }
      let parts = []
      for k, x in m {
        parts.push(pad(depth + 1) + Json::string(k).stringify() + ": " + pretty_at(x, depth + 1))
      }
      "{\n" + parts.join(",\n") + "\n" + pad(depth) + "}"
    }
    Array(a) => {
      if a.length() == 0 {
        return "[]"
      }
      "[\n" +
      a.map(fn(x) { pad(depth + 1) + pretty_at(x, depth + 1) }).join(",\n") +
      "\n" +
      pad(depth) +
      "]"
    }
    _ => v.stringify()
  }
}
