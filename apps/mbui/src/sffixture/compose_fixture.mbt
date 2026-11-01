// The fixture core's composers (as client/core-ts/src/composer.ts keeps them, for the made-up chats): by the draft's
// key, its words and their `rev` (the core's own words: read back, taken, put back, carried), the passages quoted, the
// files (fix_composers: up as soon as they are added), what went wrong, whether a new chat is being made for it, and a
// `version` each change counts. Read back the first time from the chat's seeded draft, as the core reads its kept one.

///|
/// The pictures of a mode's seeded draft drawn from them in its tiles, as a picture picked here is (the composer's
/// `writing_pictures`): newchat-attach's and chat-attach-pic's (the films of sending them: scripts/motion), and
/// chat-uploading's going up.
pub fn seeded_pictures(mode : String, files : Array[Json]) -> Unit {
  if mode != "newchat-attach" && mode != "chat-attach-pic" && mode != "chat-uploading" {
    return
  }
  for i, a in files {
    if number(Some(a), "width") > 0.0 {
      @sfbase.writing_pictures["seed-\{i}"] = fixture_file(text(Some(a), "name"))
    }
  }
}

///|
/// A fixture composer, by its key.
pub(all) struct FixWrite {
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
pub let fix_writes : Map[String, FixWrite] = {}

///|
pub fn fix_write(f : Fixture, key : String) -> FixWrite {
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
      // fix_draft_ref); one saying how much of it the station has (`sent`) still going up
      let seeded = items(seed, "files")
      let have = fix_composers.get(key).unwrap_or([])
      if !seeded.is_empty() && !have.iter().any(fn(x) { text(Some(x), "id").has_prefix("seed-") }) {
        fix_composers[key] = have +
          seeded.mapi(fn(i, a) {
            let f : Map[String, Json] = {
              "id": Json::string("seed-\{i}"),
              "name": Json::string(text(Some(a), "name")),
              "size": Json::number(number(Some(a), "size")),
            }
            match field(Some(a), "sent") {
              Some(sent) => f["sent"] = sent
              None => f["done"] = a
            }
            Json::object(f)
          })
        seeded_pictures(f.mode, seeded)
      }
      w
    }
  }
}

///|
/// The `composer` topic of key `key`: what is written, as the core says it.
pub fn fix_compose_view(f : Fixture, key : String) -> Json {
  let w = fix_write(f, key)
  let files = fix_composers.get(key).unwrap_or([])
  let uploading = files.iter().any(fn(x) { field(Some(x), "done") is None && text(Some(x), "error") == "" })
  let ready = (w.text.trim(chars=" \n\t").to_string() != "" ||
    files.iter().any(fn(x) { text(Some(x), "error") == "" }) ||
    w.quotes.length() > 0) &&
    !w.starting
  // a quote's picture in it, not among the files
  let quotes = w.quotes.map(fn(q) {
    match (q, files.iter().find_first(fn(x) { text(Some(x), "quote") == text(Some(q), "id") })) {
      (Object(m), Some(own)) => {
        let n = m.copy()
        n["own"] = own
        Json::object(n)
      }
      _ => q
    }
  })
  let v : Map[String, Json] = {
    "text": Json::string(w.text),
    "rev": Json::number(w.rev.to_double()),
    "quotes": Json::array(quotes),
    "files": Json::array(files.filter(fn(x) { text(Some(x), "quote") == "" })),
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
pub fn fix_compose_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  guard name.has_prefix("composer.") else { return None }
  let p = Some(params)
  let key = text(p, "key")
  let w = fix_write(f, key)
  let changed = fn() {
    w.version += 1
    f.changed()
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
      // an image of a message: its picture, up already, by the page's id for it
      match field(p, "attachment") {
        Some(a) =>
          fix_composers[key] = fix_composers.get(key).unwrap_or([]) +
            [
              {
                "id": Json::string(text(p, "fileId")),
                "name": Json::string(text(Some(a), "name")),
                "size": Json::number(number(Some(a), "size")),
                "done": a,
                "quote": Json::string(text(p, "id")),
              },
            ]
        None => ()
      }
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
      // its picture with it
      fix_composers[key] = fix_composers.get(key).unwrap_or([]).filter(fn(x) { text(Some(x), "quote") != text(p, "id") })
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
      // As the core does (composer.ts sentQuote and upOnce): each quote names its own file, and a file quoted more
      // than once goes with the message only once. The draft's quote ids do not go with the message.
      let sent = files.filter(fn(f) { field(Some(f), "link") is None && text(field(Some(f), "ref"), "mode") != "path" })
      let quotes = w.quotes.map(fn(q) {
        match q {
          Object(m) => {
            let out = m.copy()
            out.remove("id") |> ignore
            out["comment"] = Json::string(text(Some(q), "comment").trim(chars=" \n\t").to_string())
            match sent.iter().find_first(fn(f) { text(Some(f), "quote") == text(Some(q), "id") }) {
              Some(f) => {
                let name = match field(field(Some(f), "done"), "name") {
                  Some(String(name)) => name
                  _ => text(Some(f), "name")
                }
                out["file"] = Json::string(name)
              }
              None => ()
            }
            Json::object(out)
          }
          _ => q
        }
      })
      let paths : Set[String] = Set([])
      let attachments = sent.filter_map(fn(f) {
        match field(Some(f), "done") {
          Some(a) => {
            let path = text(Some(a), "path")
            if paths.contains(path) {
              None
            } else {
              paths.add(path)
              Some(a)
            }
          }
          None => None
        }
      })
      w.text = ""
      w.rev += 1
      w.quotes = []
      w.focus = ""
      w.error = ""
      fix_composers[key] = []
      w.version += 1
      f.changed()
      Some(
        Ok({
          "text": Json::string(taken),
          "attachments": Json::array(attachments),
          "quotes": Json::array(quotes),
          // those still going up, as they are now (none: the fixture's are up as they are added)
          "uploads": Json::array(
            files.filter_map(fn(x) {
              let o = Some(x)
              if field(o, "done") is None && text(o, "error") == "" && field(o, "link") is None && text(field(o, "ref"), "mode") != "path" {
                Some(Json::object({ "id": Json::string(text(o, "id")), "name": Json::string(text(o, "name")), "size": Json::number(number(o, "size")) }))
              } else {
                None
              }
            }),
          ),
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
