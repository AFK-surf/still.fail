// The app's words in English, for mbui's still.fail: every key of a package's tables of words (its `let …: Map[String,
// String] = {…}`, in Chinese: strings.mbt and the others) with what client/i18n/catalog/en says for it, written as
// that package's strings_en.mbt, which its `tr` reads when the language is English (@sf.language). A count's words
// (`{"one": …, "other": …}`) are the key's (other) and the key's `.one`, as Android's I18n.kt chooses them by `n`.
//
//   scripts/strings <repository>          writes src/sfapp/strings_en.mbt and src/sfapp/settings/strings_en.mbt
//
// A key the English catalog lacks fails it, named: its words go in the catalog (both languages), not here.

///|
/// The packages with tables of words, from the repository.
let packages : Array[String] = ["apps/mbui/src/sfapp", "apps/mbui/src/sfapp/settings"]

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("strings: " + why)
  @sys.exit(1)
}

///|
/// The keys of the tables of words in `dir`'s files (not its tests, not the English it writes), in the order they come.
fn table_keys(dir : String) -> Array[String] {
  let names = @sys.list_dir(dir).filter(fn(n) {
    n.has_suffix(".mbt") && !n.has_suffix("_test.mbt") && !n.has_suffix("_wbtest.mbt") && n != "strings_en.mbt"
  })
  names.sort()
  let keys : Array[String] = []
  let seen : Map[String, Bool] = {}
  for name in names {
    let text = @sys.read_text(@sys.join(dir, name)).unwrap_or("")
    let mut table = false
    for raw in text.split("\n") {
      let line = raw.to_string()
      if !table {
        table = (line.has_prefix("let ") || line.has_prefix("pub let ")) &&
          line.contains(": Map[String, String] = {")
        continue
      }
      if line.has_prefix("}") {
        table = false
        continue
      }
      let t = line.trim(chars=" ").to_string()
      if !t.has_prefix("\"") {
        continue
      }
      // the key: up to its closing quote (keys have no escapes)
      let cs = t.to_array()
      let mut i = 1
      while i < cs.length() && cs[i] != '"' {
        i += 1
      }
      let key = String::from_array(cs[1:i].to_array())
      // (a key is a catalog's: part.name…; the others are not words)
      if key.contains(".") && !seen.contains(key) {
        seen[key] = true
        keys.push(key)
      }
    }
  }
  keys
}

///|
/// `s` as a MoonBit string's literal.
fn quoted(s : String) -> String {
  let b = StringBuilder::new()
  b.write_char('"')
  for c in s {
    match c {
      '\\' => b.write_string("\\\\")
      '"' => b.write_string("\\\"")
      '\n' => b.write_string("\\n")
      '\t' => b.write_string("\\t")
      '\r' => b.write_string("\\r")
      _ => b.write_char(c)
    }
  }
  b.write_char('"')
  b.to_string()
}

///|
fn text_of(j : Json?) -> String? {
  match j {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    @sys.eprintln("scripts/strings <repository>")
    @sys.exit(2)
    return
  }
  let repo = argv[1]
  let catalog = @sys.join(repo, "client/i18n/catalog/en")
  let parts = @sys.list_dir(catalog).filter(fn(n) { n.has_suffix(".json") })
  parts.sort()
  if parts.is_empty() {
    fail("no catalog in \{catalog}")
    return
  }
  let en : Map[String, Json] = {}
  for part in parts {
    let text = @sys.read_text(@sys.join(catalog, part)).unwrap_or("")
    match (try Some(@json.parse(text)) catch { _ => None }) {
      Some(Object(m)) => for k, v in m { en[k] = v }
      _ => fail("\{part} is not a JSON object")
    }
  }
  let missing : Array[String] = []
  for pkg in packages {
    let dir = @sys.join(repo, pkg)
    let words : Array[(String, String)] = []
    let put : Map[String, Bool] = {}
    let add = fn(k : String, v : String) {
      if !put.contains(k) {
        put[k] = true
        words.push((k, v))
      }
    }
    for key in table_keys(dir) {
      match en.get(key) {
        Some(String(s)) => add(key, s)
        Some(Object(o)) =>
          match (text_of(o.get("other")), text_of(o.get("one"))) {
            (Some(other), one) => {
              add(key, other)
              if one is Some(s) {
                add(key + ".one", s)
              }
            }
            _ => missing.push(pkg + ": " + key)
          }
        _ => {
          // a count's one or other by its own key (drive's trashed.one)
          let (base, form) = if key.has_suffix(".one") {
            (key.view(end_offset=key.length() - 4).to_string(), "one")
          } else if key.has_suffix(".other") {
            (key.view(end_offset=key.length() - 6).to_string(), "other")
          } else {
            ("", "")
          }
          let said = match en.get(base) {
            Some(Object(o)) => text_of(o.get(form))
            _ => None
          }
          match said {
            Some(s) => add(key, s)
            None => missing.push(pkg + ": " + key)
          }
        }
      }
    }
    let out = StringBuilder::new()
    out.write_string(
      "// Generated by scripts/strings from client/i18n/catalog/en (tools/strings: the words of this package's tables, in\n",
    )
    out.write_string("// English): do not edit.\n\n///|\n")
    out.write_string(
      "/// This package's words in English (`.one`: a count's when it is one), as `tr` says them when @sf.language() is \"en\".\n",
    )
    out.write_string("let en : Map[String, String] = {\n")
    for w in words {
      out.write_string("  " + quoted(w.0) + ": " + quoted(w.1) + ",\n")
    }
    out.write_string("}\n")
    if !@sys.write_text(@sys.join(dir, "strings_en.mbt"), out.to_string()) {
      fail("\{pkg}/strings_en.mbt not written")
    }
  }
  if !missing.is_empty() {
    fail("the English catalog (client/i18n/catalog/en) has no words for:\n  " + missing.join("\n  "))
  }
}
