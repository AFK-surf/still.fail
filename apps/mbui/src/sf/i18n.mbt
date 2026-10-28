// The words people read, in their language (web/ui i18n.ts): the catalog's (client/i18n/catalog), as the app says them
// (set_words: its `fill`, told once as it starts). With none told, a key is said as it is.

///|
/// How a key's words are said, its `{name}`s put in from the pairs given, as the app said it.
// kept across runs: what the app says once as it starts (set_words), the same for every run of it
let words_of : Ref[(String, Array[(String, String)]) -> String] = Ref(fn(key, _) { key })

///|
/// How the words are said from now on (the web's addWords and setLang: the app's catalog in its language).
pub fn set_words(said : (String, Array[(String, String)]) -> String) -> Unit {
  words_of.val = said
}

///|
/// The words for `key`, its `{name}`s put in from `args` (the web's `t`).
pub fn t(key : String, args? : Array[(String, String)] = []) -> String {
  (words_of.val)(key, args)
}

///|
/// The words for `key` either side of its `{name}` (the web's tx, with something drawn in its place: a workspace's
/// mark and name, a person's face and name): what goes before it, and after. All of them before, where it has none.
pub fn t_around(key : String, name : String, args? : Array[(String, String)] = []) -> (String, String) {
  let mark = "\u{E000}"
  let whole = t(key, args=[..args, (name, mark)])
  match whole.find(mark) {
    Some(i) => (whole.view(end_offset=i).to_owned(), whole.view(start_offset=i + mark.length()).to_owned())
    None => (whole, "")
  }
}
