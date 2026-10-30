// The real core's answers to its pure calls, kept for the app's runs without a core: the Tester's tests (src/sf,
// src/sfapp with its screens), the screenshots' app (src/sffix), the design system's (src/sfkit), and the replays of tapes
// older than a call (src/sfreplay). `markdown` (a text's tree), `code.ink` (what each piece of a code is), `reader.book`,
// `reader.text` and `reader.search` (a text as the drive's reader shows it), `commands.find` (what ⌘K lists of what is
// offered), `chat.tabs` (a chat's side panel's tabs, for a run's made-up core: chat-tabs.ts), `chat.find.go` (where a chat's find goes: chat-find.ts), `chat.relayView` (what a chat's relay picker shows:
// relay-pick.ts) answer the same for the same words, so the
// TypeScript core's answers are kept here (kept.mbt, made by client/core-ts/scripts/kept-answers.ts) and nothing in the
// app reads Markdown or code itself. An answer asked and not kept is said on the run's output (`kept-answers-ask {…}`):
// scripts/test.sh fails on it, and scripts/kept has the core work it out and keeps it.

///|
/// The kept answers as kept.mbt has them (an answer a line), by call: `markdown` by the text; `code.ink` by the language and the code (a \u{1}
/// between); `reader.book` by "md" or "txt" and the text, each with its answer, its text as joined (where joining
/// changed it) and its searches by their words.
let table : Ref[Map[String, Json]?] = Ref(None)

///|
fn kept(call : String) -> Map[String, Json] {
  let t = match table.val {
    Some(t) => t
    None => {
      // an answer a line: [call, key, answer]
      let t : Map[String, Json] = {}
      for line in kept_answers.split("\n") {
        match (@json.parse(line.to_string()) catch { _ => Json::null() }) {
          Array([String(call), String(key), answer]) =>
            match t.get(call) {
              Some(Object(m)) => m[key] = answer
              _ => {
                let m : Map[String, Json] = {}
                m[key] = answer
                t[call] = Json::object(m)
              }
            }
          _ => ()
        }
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
/// read and code coloured; a text's book and what is asked of it (`reader.*`: always answered here, its text beside the
/// call where params cannot say it; one not kept is said on the output and kept by scripts/kept); what is written, read
/// (`ref.*`, `paste.info`: always answered here); one asked as said whose answer is kept (a history step's call, a
/// chat's tabs). Nothing is said on the output of one that is not.
pub fn has(name : String, params : Json) -> Bool {
  match name {
    "markdown" => kept("markdown").contains(word(params, "text"))
    "code.ink" => kept("code.ink").contains(word(params, "lang") + "\u{1}" + word(params, "code"))
    "reader.book" | "reader.text" | "reader.search" => true
    // what is written, read (refLinks.ts, pasted.ts): a pure function of the words, answered here whatever a run's
    // tape has of it (a field's edits ask it as they come, in an order of their own)
    "ref.at" | "ref.before" | "ref.marks" | "ref.pasted" | "paste.info" => true
    // a name typed for a file or folder (drive.ts nameProblem): a pure function of it
    "drive.check" => true
    // answered here once kept, by what is asked as said (answer): never the run's core's to give then, so never
    // waited for in its tape either (⌘K's `commands.find` is the tape's: src/sfreplay source.mbt asks it of the run)
    "railView" | "chat.tabs" | "history.tool" | "chat.find.go" | "chat.relayView" =>
      kept(name).contains(params.stringify())
    _ => false
  }
}

///|
/// The core's answer to `name` (with its `params`, and the bytes beside the call) as the real core gave it, its bytes
/// beside it; an error where it is not kept (said on the output); None for a call that is not one of these.
pub fn answer(name : String, params : Json, bytes : Bytes?) -> Result[(Json, Bytes?), Json]? {
  match name {
    // the rail as drawn from the prefs kept (`rail`, `rails`: rail.ts railView), by them as JSON
    "railView" => {
      let key = params.stringify()
      match kept("railView").get(key) {
        Some(v) => Some(Ok((v, None)))
        None => not_kept({ "call": "railView", "prefs": params })
      }
    }
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
    // what ⌘K lists of what the app offers (the made-up core says in which language: `lang`), by what is asked as said
    "commands.find" => {
      let key = params.stringify()
      match kept("commands.find").get(key) {
        Some(found) => Some(Ok((found, None)))
        None => not_kept({ "call": "commands.find", "key": Json::string(key) })
      }
    }
    // a chat's side panel's tabs (chat-tabs.ts) for a made-up core that keeps them: those shown for what is kept
    // (`kept`, its `agents`, `noChat`, `session`), or what is kept after a `change` (`next`), as asked
    "chat.tabs" => {
      let key = params.stringify()
      match kept("chat.tabs").get(key) {
        Some(v) => Some(Ok((v, None)))
        None => not_kept({ "call": "chat.tabs", "key": Json::string(key) })
      }
    }
    "browse" => browse_answer(params)
    // what a history step's call and result are (tool-step.ts), by what is asked as said
    "history.tool" => {
      let key = params.stringify()
      match kept("history.tool").get(key) {
        Some(v) => Some(Ok((v, None)))
        None => not_kept({ "call": "history.tool", "key": Json::string(key) })
      }
    }
    // where a chat's find goes (chat-find.ts): from what was found and where the reader is, which way, what shows
    // what is written, read (refLinks.ts refAt, markBefore, marksIn, pastedRefs; pasted.ts; a name typed for a file or
    // folder, drive.ts nameProblem): by the call and its words
    "ref.at" | "ref.before" | "ref.marks" | "ref.pasted" | "paste.info" | "drive.check" => {
      let ask : Map[String, Json] = { "call": Json::string(name), "text": Json::string(word(params, "text")) }
      match param(params, "caret") {
        Some(Number(_, ..) as n) => ask["caret"] = n
        _ => ()
      }
      match word(params, "here") {
        "" => ()
        h => ask["here"] = Json::string(h)
      }
      let key = Json::object(ask).stringify()
      match kept("words").get(key) {
        Some(v) => Some(Ok((v, None)))
        None => not_kept({ "call": "words", "key": Json::string(key) })
      }
    }
    "chat.find.go" => {
      let key = params.stringify()
      match kept("chat.find.go").get(key) {
        Some(v) => Some(Ok((v, None)))
        None => not_kept({ "call": "chat.find.go", "key": Json::string(key) })
      }
    }
    // what a chat's relay picker shows (relay-pick.ts): from the connects read, what was typed, the bot picked
    "chat.relayView" => {
      let key = params.stringify()
      match kept("chat.relayView").get(key) {
        Some(v) => Some(Ok((v, None)))
        None => not_kept({ "call": "chat.relayView", "key": Json::string(key) })
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
