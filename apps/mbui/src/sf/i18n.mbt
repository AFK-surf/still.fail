// The words people read, in their language (web/ui i18n.ts): the catalog's (client/i18n/catalog), as the app says them
// (set_words: its `fill`, told once as it starts). With none told, a key is said as it is.

///|
/// How a key's words are said, its `{name}`s put in from the pairs given, as the app said it.
// kept across runs: what the app says once as it starts (set_words), the same for every run of it
let words_of : Ref[(String, Array[(String, String)]) -> String] = Ref(fn(key, _) { key })

///|
/// How the words are said from now on (the web's addWords and setLang: the app's catalog in its language).
pub fn set_words(said : (String, Array[(String, String)]) -> String) -> Unit {
  // (the same told again, as each frame tells it: nothing new)
  if physical_equal(said, words_of.val) {
    return
  }
  words_of.val = said
  words_told_at.val += 1
  words_told.set(words_told_at.val)
}

///|
/// How many times other words were told (set_words): what a run checks the app tells them once.
pub fn words_told_count() -> Int {
  words_told_at.val
}

///|
/// How many times the words were told (set_words): read by t, so what reads words as it changes (a node's, bound to
/// them) says them again as they are told, whenever it was made.
let words_told : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
let words_told_at : Ref[Int] = Ref(0)

///|
/// The words for `key`, its `{name}`s put in from `args` (the web's `t`).
pub fn t(key : String, args? : Array[(String, String)] = []) -> String {
  words_told.get() |> ignore
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
