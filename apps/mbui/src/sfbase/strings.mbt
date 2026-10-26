// The app's words: the catalog's (client/i18n/catalog), in Chinese strings_zh.mbt's and in English strings_en.mbt's
// (@sf.language: the core's `lang`, else the phone's), both written by scripts/strings for the keys words.txt says. A
// word the app says is a key added to words.txt and the script run, its words in the catalog, never copied here.
// `{name}` is put in by `fill`.

///|
/// `key`'s words in English when that is the language (@sf.language: strings_en.mbt, scripts/strings), a count's of one
/// (`n` 1) its `.one`, as Android's I18n.kt chooses; None in Chinese, or for a key it has no words for.
pub fn english(key : String, args? : Array[(String, String)] = []) -> String? {
  if @sf.language() != "en" {
    return None
  }
  if args.iter().any(fn(a) { a.0 == "n" && a.1 == "1" }) && en.get(key + ".one") is Some(one) {
    return Some(one)
  }
  en.get(key)
}

///|
/// The words for `key` with `{name}`s put in from `args`.
pub fn tr(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = match english(key, args~) {
    Some(s) => s
    None =>
      match zh.get(key) {
        Some(s) => s
        // (the settings' own words: the desktop's settings pages say them too)
        None => @settings.said(key, args).unwrap_or(key)
      }
  }
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// The words for `key` with `{name}`s put in (tr's, as @sf.set_words is told).
pub fn fill(key : String, args : Array[(String, String)]) -> String {
  tr(key, args~)
}
