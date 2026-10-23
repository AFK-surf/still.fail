// The real core's answers to its pure calls, kept for the app's runs without a core: the Tester's tests (src/sf,
// src/sfapp, src/sfscreens), the screenshots' app (src/sffix), the design system's (src/sfkit), and the replays of tapes
// older than a call (src/sfreplay). `markdown` (a text's tree), `code.ink` (what each piece of a code is), `reader.book`,
// `reader.text` and `reader.search` (a text as the drive's reader shows it) answer the same for the same words, so the
// TypeScript core's answers are kept here (kept.mbt, made by client/core-ts/scripts/kept-answers.ts) and nothing in the
// app reads Markdown or code itself. An answer asked and not kept is said on the run's output (`kept-answers-ask {…}`):
// scripts/test.sh fails on it, and scripts/kept has the core work it out and keeps it.

///|
/// The kept answers as kept.mbt has them: `markdown` by the text; `code.ink` by the language and the code (a \u{1}
/// between); `reader.book` by "md" or "txt" and the text, each with its answer, its text as joined (where joining
/// changed it) and its searches by their words.
let table : Ref[Map[String, Json]?] = Ref(None)

///|
fn kept(call : String) -> Map[String, Json] {
  let t = match table.val {
    Some(t) => t
    None => {
      let t = match (@json.parse(kept_answers) catch { _ => Json::null() }) {
        Object(m) => m
        _ => {}
      }
      table.val = Some(t)
      t
    }
  }
  match t.get(call) {
    Some(Object(m)) => m
    _ => {}
  }
}

///|
fn param(params : Json, key : String) -> Json? {
  match params {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
fn word(params : Json, key : String) -> String {
  match param(params, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn flag(params : Json, key : String) -> Bool {
  param(params, key) is Some(True)
}

///|
/// An answer not kept: said on the output for scripts/kept, an error for the asker.
fn not_kept(ask : Map[String, Json]) -> Result[(Json, Bytes?), Json]? {
  println("kept-answers-ask " + Json::object(ask).stringify())
  Some(Err({ "code": "not_kept", "message": "the core's answer to \{ask.get("call").unwrap()} is not kept: apps/mbui/scripts/kept" }))
}

///|
/// The books asked of in this run, by the id each was answered with: its key in `reader.book`.
let books : Map[Int, String] = {}

///|
let next_book : Ref[Int] = Ref(1)

///|
fn book_key(markdown : Bool, text : String) -> String {
  (if markdown { "md" } else { "txt" }) + "\u{1}" + text
}

///|
/// Whether the core's answer to `name` with its `params` is kept (a call answered here, not asked of a core): Markdown
/// read and code coloured. Nothing is said on the output of one that is not.
pub fn has(name : String, params : Json) -> Bool {
  match name {
    "markdown" => kept("markdown").contains(word(params, "text"))
    "code.ink" => kept("code.ink").contains(word(params, "lang") + "\u{1}" + word(params, "code"))
    _ => false
  }
}

///|
/// The core's answer to `name` (with its `params`, and the bytes beside the call) as the real core gave it, its bytes
/// beside it; an error where it is not kept (said on the output); None for a call that is not one of these.
pub fn answer(name : String, params : Json, bytes : Bytes?) -> Result[(Json, Bytes?), Json]? {
  match name {
    "markdown" => {
      let text = word(params, "text")
      match kept("markdown").get(text) {
        Some(md) => Some(Ok(({ "md": md }, None)))
        None => not_kept({ "call": "markdown", "text": Json::string(text) })
      }
    }
    "code.ink" => {
      let code = word(params, "code")
      let lang = word(params, "lang")
      match kept("code.ink").get(lang + "\u{1}" + code) {
        Some(ink) => Some(Ok(({ "ink": ink }, None)))
        None => not_kept({ "call": "code.ink", "code": Json::string(code), "lang": Json::string(lang) })
      }
    }
    "reader.book" => {
      let text = match (param(params, "text"), bytes) {
        (Some(String(s)), _) => s
        (_, Some(b)) => @utf8.decode_lossy(b[:])
        _ => ""
      }
      let markdown = flag(params, "markdown")
      let key = book_key(markdown, text)
      match kept("reader.book").get(key) {
        Some(Object(entry)) => {
          let id = next_book.val
          next_book.val += 1
          books[id] = key
          let out : Map[String, Json] = {}
          match entry.get("answer") {
            Some(Object(a)) =>
              for k, v in a {
                if k != "md" || flag(params, "tree") {
                  out[k] = v
                }
              }
            _ => ()
          }
          out["id"] = Json::number(id.to_double())
          if flag(params, "withText") {
            out["text"] = Json::string(book_text(key))
          }
          Some(Ok((Json::object(out), None)))
        }
        _ => not_kept({ "call": "reader.book", "markdown": Json::boolean(markdown), "text": Json::string(text) })
      }
    }
    "reader.text" =>
      match book_of(params) {
        Some(key) => {
          let text = book_text(key)
          Some(Ok(({ "length": Json::number(text.length().to_double()) }, Some(@utf8.encode(text)))))
        }
        None => Some(Err({ "code": "invalid", "message": "no such book" }))
      }
    "reader.search" =>
      match book_of(params) {
        Some(key) => {
          let query = word(params, "query")
          match kept("reader.book").get(key) {
            Some(Object(entry)) =>
              match entry.get("search") {
                Some(Object(s)) if s.get(query) is Some(at) => Some(Ok(({ "at": at }, None)))
                _ => {
                  let (markdown, text) = match key.split("\u{1}").next() {
                    Some(m) => (m == "md", key.view(start_offset=m.length() + 1).to_string())
                    None => (false, key)
                  }
                  not_kept({
                    "call": "reader.search",
                    "markdown": Json::boolean(markdown),
                    "text": Json::string(text),
                    "query": Json::string(query),
                  })
                }
              }
            _ => Some(Err({ "code": "invalid", "message": "no such book" }))
          }
        }
        None => Some(Err({ "code": "invalid", "message": "no such book" }))
      }
    _ => None
  }
}

///|
fn book_of(params : Json) -> String? {
  match param(params, "id") {
    Some(Number(n, ..)) => books.get(n.to_int())
    _ => None
  }
}

///|
/// A kept book's text as joined: its own where joining changed it, else the text it was asked with.
fn book_text(key : String) -> String {
  match kept("reader.book").get(key) {
    Some(Object(entry)) if entry.get("text") is Some(String(t)) => t
    _ =>
      match key.split("\u{1}").next() {
        Some(m) => key.view(start_offset=m.length() + 1).to_string()
        None => key
      }
  }
}
