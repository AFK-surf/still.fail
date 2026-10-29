// The words of the settings: the catalog's (client/i18n/catalog), in Chinese strings_zh.mbt's and in English
// strings_en.mbt's, both written by scripts/strings for the keys words.txt says; `{name}` put in by `fill`.

///|
/// `key`'s words in English when that is the language (@sf.language: strings_en.mbt, scripts/strings), a count's of one
/// (`n` 1) its `.one`, as Android's I18n.kt chooses; None in Chinese, or for a key it has no words for.
fn english(key : String, args? : Array[(String, String)] = []) -> String? {
  if @sf.language() != "en" {
    return None
  }
  if args.iter().any(fn(a) { a.0 == "n" && a.1 == "1" }) && en.get(key + ".one") is Some(one) {
    return Some(one)
  }
  en.get(key)
}

///|
/// The words for `key`.
fn tr(key : String) -> String {
  match english(key) {
    Some(s) => s
    None => zh.get(key).unwrap_or(key)
  }
}

///|
/// The words for `key` with `{name}`s put in.
fn fill(key : String, args : Array[(String, String)]) -> String {
  let mut s = match english(key, args~) {
    Some(w) => w
    None => tr(key)
  }
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// The words for `key` with `{name}`s put in, as runs: its `{name}` (an item's name) in `named`'s run, set apart from
/// the words around it by how it looks rather than by quotes, the rest in `words`'s.
fn fill_named(
  key : String,
  args : Array[(String, String)],
  named : (String) -> @ui.Run,
  words : (String) -> @ui.Run,
) -> Array[@ui.Run] {
  let mut s = match english(key, args~) {
    Some(w) => w
    None => tr(key)
  }
  let mut name = ""
  for a in args {
    if a.0 == "name" {
      name = a.1
    } else {
      s = s.replace_all(old="{" + a.0 + "}", new=a.1)
    }
  }
  let runs : Array[@ui.Run] = []
  let parts = s.split("{name}").collect()
  for i, p in parts {
    if i > 0 {
      runs.push(named(name))
    }
    if p.length() > 0 {
      runs.push(words(p.to_string()))
    }
  }
  runs
}

///|
/// The words for `key` from these tables (`args` choosing a count's of one), None for a key they have none for: what
/// the app's own words fall back to (src/sfapp/strings.mbt), so a key of these pages said elsewhere (the desktop's
/// pages, src/sfdesk) is said once, here.
pub fn said(key : String, args : Array[(String, String)]) -> String? {
  match english(key, args~) {
    Some(s) => Some(s)
    None => zh.get(key)
  }
}
