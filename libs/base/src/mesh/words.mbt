// The words the mesh's errors are said in: the device base's own (client/core-ts/src/lang.zh.json, lang.en.json: the
// keys `core-logic.mesh.*`, of no program, the peer "the server"), the same keys and texts as its TypeScript mesh says.
// They are not written here: scripts/mb-base-words.ts writes them out of the two files as words_made.mbt beside this
// file (`made_zh`, `made_en`), which is committed, and scripts/check.sh holds it to what the two files make.

///|
/// The language the words are said in.
let language : Ref[String] = { val: "zh" }

///|
/// `lang`: "en" or "zh". Chinese until told otherwise, as the device base in TypeScript.
pub fn set_language(lang : String) -> Unit {
  language.val = lang
}

///|
/// The words of `core-logic.mesh.<key>`, each `{name}` in them what `args` says it is.
pub fn say(key : String, args? : Map[String, String]) -> String {
  let words = if language.val == "en" { made_en } else { made_zh }
  let mut text = words.get("core-logic.mesh." + key).unwrap_or(key)
  if args is Some(args) {
    for name, value in args {
      text = text.replace_all(old="{" + name + "}", new=value)
    }
  }
  text
}
