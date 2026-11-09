// The workspace lock's forms, as station/src/cloud/lock.ts and client/core-ts/src/lock-form.ts
// have them: JSON with object keys sorted and no space (what is hashed), byte for byte as theirs (rules/test checks the
// two agree), and what an entry's hash is of.

///|
/// A value no lock entry holds (a number not a safe integer).
#derive(Debug)
pub(all) suberror Invalid {
  Invalid(String)
}

///|
/// The largest integer a double holds exactly (JS's Number.MAX_SAFE_INTEGER).
let max_safe : Double = 9007199254740991.0

///|
/// JSON with object keys sorted (by UTF-16 code unit, as JS sorts them) and no space: only integers, strings,
/// booleans, null, arrays and objects. Strings are written as JSON.stringify writes them.
pub fn canonical(v : Json) -> String raise Invalid {
  let b = StringBuilder()
  write(b, v)
  b.to_string()
}

///|
fn write(b : StringBuilder, v : Json) -> Unit raise Invalid {
  match v {
    Null => b.write_string("null")
    True => b.write_string("true")
    False => b.write_string("false")
    Number(n, ..) => {
      if !(n == n.floor() && n.abs() <= max_safe) {
        raise Invalid("lock entries hold integers only")
      }
      b.write_string(n.to_int64().to_string())
    }
    String(s) => quote(b, s)
    Array(xs) => {
      b.write_char('[')
      for i, x in xs {
        if i > 0 {
          b.write_char(',')
        }
        write(b, x)
      }
      b.write_char(']')
    }
    Object(m) => {
      let keys = m.keys().collect()
      keys.sort_by(code_units)
      b.write_char('{')
      for i, k in keys {
        if i > 0 {
          b.write_char(',')
        }
        quote(b, k)
        b.write_char(':')
        write(b, m.get(k).unwrap())
      }
      b.write_char('}')
    }
  }
}

///|
/// JS's default sort order of strings: by UTF-16 code unit.
fn code_units(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
let hex_digits : String = "0123456789abcdef"

///|
/// A string as JSON.stringify writes it: `"` and `\` escaped, control characters as \b \f \n \r \t or \u00xx, a lone
/// surrogate as \udxxx, everything else as it is.
fn quote(b : StringBuilder, s : String) -> Unit {
  b.write_char('"')
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.code_unit_at(i).to_int()
    if c == 0x22 {
      b.write_string("\\\"")
    } else if c == 0x5c {
      b.write_string("\\\\")
    } else if c == 0x08 {
      b.write_string("\\b")
    } else if c == 0x0c {
      b.write_string("\\f")
    } else if c == 0x0a {
      b.write_string("\\n")
    } else if c == 0x0d {
      b.write_string("\\r")
    } else if c == 0x09 {
      b.write_string("\\t")
    } else if c < 0x20 {
      unicode_escape(b, c)
    } else if c >= 0xd800 && c <= 0xdbff {
      // a high surrogate: with its low one, as it is; alone, escaped
      if i + 1 < n && s.code_unit_at(i + 1).to_int() >= 0xdc00 && s.code_unit_at(i + 1).to_int() <= 0xdfff {
        b.write_char(Int::unsafe_to_char(0x10000 + ((c - 0xd800) << 10) + (s.code_unit_at(i + 1).to_int() - 0xdc00)))
        i = i + 1
      } else {
        unicode_escape(b, c)
      }
    } else if c >= 0xdc00 && c <= 0xdfff {
      unicode_escape(b, c)
    } else {
      b.write_char(Int::unsafe_to_char(c))
    }
    i = i + 1
  }
  b.write_char('"')
}

///|
fn unicode_escape(b : StringBuilder, c : Int) -> Unit {
  b.write_string("\\u")
  for shift in [12, 8, 4, 0] {
    b.write_char(hex_digits.code_unit_at((c >> shift) & 0xf).to_int().unsafe_to_char())
  }
}

///|
/// What an entry's hash is of: everything but its signature, tagged.
pub fn entry_text(e : Json) -> String raise Invalid {
  guard e is Object(m) else { raise Invalid("an entry is an object") }
  // (a field the entry leaves out is left out here too, as JS leaves out an undefined one)
  let hashed : Map[String, Json] = Map([])
  for k in ["v", "ws", "seq", "prev", "at", "kind", "body"] {
    if m.get(k) is Some(x) {
      hashed[k] = x
    }
  }
  "stillfail-lock/1\n" + canonical(Json::object(hashed))
}
