// The fixture core's composers (as client/core-ts/src/composer.ts keeps them, for the made-up chats): by the draft's
// key, its words and their `rev` (the core's own words: read back, taken, put back, carried), the passages quoted, the
// files (fix_composers: up as soon as they are added), what went wrong, whether a new chat is being made for it, and a
// `version` each change counts. Read back the first time from the chat's seeded draft, as the core reads its kept one.

///|
/// A fixture composer, by its key.
priv struct FixWrite {
  mut text : String
  mut rev : Int
  mut quotes : Array[Json]
  mut focus : String
  mut starting : Bool
  mut error : String
  mut version : Int
  /// what `composer.take` took (words, quotes, files), for `composer.restore`
  mut taken : (String, Array[Json], Array[Json])?
}

///|
let fix_writes : Map[String, FixWrite] = {}

///|
fn fix_write(f : Fixture, key : String) -> FixWrite {
  match fix_writes.get(key) {
    Some(w) => w
    None => {
      let seed = Some(seeded_draft(f.mode, key))
      let w : FixWrite = {
        text: text(seed, "text"),
        rev: if text(seed, "text") == "" { 0 } else { 1 },
        quotes: items(seed, "quotes"),
        focus: "",
        starting: false,
        error: "",
        version: 0,
        taken: None,
      }
      fix_writes[key] = w
      // its files up already, as the core keeps them in the draft (after what a screen put in first: a station's file,
      // fix_draft_ref)
      let seeded = items(seed, "files")
      let have = fix_composers.get(key).unwrap_or([])
      if !seeded.is_empty() && !have.iter().any(fn(x) { text(Some(x), "id").has_prefix("seed-") }) {
        fix_composers[key] = have +
          seeded.mapi(fn(i, a) {
            {
              "id": Json::string("seed-\{i}"),
              "name": Json::string(text(Some(a), "name")),
              "size": Json::number(number(Some(a), "size")),
              "done": a,
            }
          })
      }
      w
    }
  }
}

///|
/// The `composer` topic of key `key`: what is written, as the core says it.
fn fix_compose_view(f : Fixture, key : String) -> Json {
  let w = fix_write(f, key)
  let files = fix_composers.get(key).unwrap_or([])
  let uploading = files.iter().any(fn(x) { field(Some(x), "done") is None && text(Some(x), "error") == "" })
  let ready = (w.text.trim(chars=" \n\t").to_string() != "" ||
    files.iter().any(fn(x) { text(Some(x), "error") == "" }) ||
    w.quotes.length() > 0) &&
    !w.starting
  let v : Map[String, Json] = {
    "text": Json::string(w.text),
    "rev": Json::number(w.rev.to_double()),
    "quotes": Json::array(w.quotes),
    "files": Json::array(files),
    "uploading": Json::boolean(uploading),
    "ready": Json::boolean(ready),
    "starting": Json::boolean(w.starting),
    "version": Json::number(w.version.to_double()),
  }
  if w.focus != "" {
    v["focus"] = Json::string(w.focus)
  }
  if w.error != "" {
    v["error"] = Json::string(w.error)
  }
  Json::object(v)
}

///|
/// A `composer.*` call other than `add` and `remove` (chat_fixture.mbt's, which keep the files): done at once, its
/// answer the composer's new version; None for any other call.
fn fix_compose_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  guard name.has_prefix("composer.") else { return None }
  let p = Some(params)
  let key = text(p, "key")
  let w = fix_write(f, key)
  let changed = fn() {
    w.version += 1
    f.version += 1
    Some(Ok(Json::object({ "version": Json::number(w.version.to_double()) })))
  }
  match name {
    "composer.text" => {
      w.text = text(p, "text")
      changed()
    }
    "composer.quote" => {
      let q = match field(p, "quote") {
        Some(Object(m)) => m.copy()
        _ => {}
      }
      q["id"] = Json::string(text(p, "id"))
      if !q.contains("comment") {
        q["comment"] = Json::string("")
      }
      w.quotes.push(Json::object(q))
      if flag(p, "focus") {
        w.focus = text(p, "id")
      }
      changed()
    }
    "composer.comment" => {
      w.quotes = w.quotes.map(fn(q) {
        match q {
          Object(m) if text(Some(q), "id") == text(p, "id") => {
            let n = m.copy()
            n["comment"] = Json::string(text(p, "comment"))
            Json::object(n)
          }
          _ => q
        }
      })
      changed()
    }
    "composer.unquote" => {
      w.quotes = w.quotes.filter(fn(q) { text(Some(q), "id") != text(p, "id") })
      if w.focus == text(p, "id") {
        w.focus = ""
      }
      changed()
    }
    "composer.focused" => {
      w.focus = ""
      changed()
    }
    "composer.error" => {
      w.error = text(p, "error")
      changed()
    }
    "composer.starting" => {
      w.starting = flag(p, "starting")
      changed()
    }
    "composer.take" => {
      let files = fix_composers.get(key).unwrap_or([])
      w.taken = Some((w.text, w.quotes, files))
      let taken = w.text.trim(chars=" \n\t").to_string()
      let quotes = w.quotes
      w.text = ""
      w.rev += 1
      w.quotes = []
      w.focus = ""
      w.error = ""
      fix_composers[key] = []
      w.version += 1
      f.version += 1
      Some(
        Ok({
          "text": Json::string(taken),
          "attachments": Json::array(files.filter_map(fn(x) { field(Some(x), "done") })),
          "quotes": Json::array(quotes),
          "files": [],
          "version": Json::number(w.version.to_double()),
        }),
      )
    }
    "composer.restore" =>
      match w.taken {
        Some((words, quotes, files)) => {
          w.taken = None
          w.text = words
          w.rev += 1
          w.quotes = quotes
          fix_composers[key] = files
          w.error = text(p, "error")
          changed()
        }
        None => changed()
      }
    "composer.carry" => {
      let to = fix_write(f, text(p, "to"))
      to.text = w.text
      to.rev += 1
      to.quotes = w.quotes
      fix_composers[text(p, "to")] = fix_composers.get(key).unwrap_or([])
      w.text = ""
      w.rev += 1
      w.quotes = []
      fix_composers[key] = []
      to.version += 1
      changed()
    }
    "composer.mode" => changed()
    _ => None
  }
}
