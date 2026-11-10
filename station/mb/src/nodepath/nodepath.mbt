// Paths made as Node's path.join makes them (posix's, or win32's when the separator is `\`), for what the station's
// programs give back to the TypeScript station to compare with its own.

///|
fn is_sep(c : Int, win : Bool) -> Bool {
  c == '/' || (win && c == '\\')
}

///|
/// Node's path.join: the parts joined, then normalized.
pub fn join(sep : String, parts : Array[String]) -> String {
  let joined = parts.filter(p => p != "").join(sep)
  normalize(sep, if joined == "" { "." } else { joined })
}

///|
/// Node's path.normalize: `.` and `..` taken out by name, repeated separators made one, the trailing one kept.
fn normalize(sep : String, path : String) -> String {
  let win = sep == "\\"
  let n = path.length()
  let mut root = ""
  let mut at = 0
  if win && n >= 2 && path.unsafe_charcode_at(1) == ':' {
    root = path.exact_view(end=2).to_owned()
    at = 2
    if n > 2 && is_sep(path.unsafe_charcode_at(2), true) {
      root = root + "\\"
      at = 3
    }
  } else if win && n >= 2 && is_sep(path.unsafe_charcode_at(0), true) && is_sep(path.unsafe_charcode_at(1), true) {
    root = "\\\\"
    at = 2
  } else if n > 0 && is_sep(path.unsafe_charcode_at(0), win) {
    root = sep
    at = 1
  }
  let absolute = root != "" && (root.length() != 2 || !win || root == "\\\\")
  let parts : Array[String] = []
  let mut start = at
  for i = at; i <= n; i = i + 1 {
    if i < n && !is_sep(path.unsafe_charcode_at(i), win) {
      continue
    }
    let part = path.view(start_offset=start, end_offset=i).to_owned()
    start = i + 1
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        ignore(parts.pop())
      } else if !absolute {
        parts.push(part)
      }
      continue
    }
    parts.push(part)
  }
  let body = parts.join(sep)
  let trailing = n > at && is_sep(path.unsafe_charcode_at(n - 1), win) && body != ""
  let out = root + body + (if trailing { sep } else { "" })
  if out == "" {
    "."
  } else {
    out
  }
}

