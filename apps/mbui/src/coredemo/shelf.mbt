// The shelf over the core's media module (ember docs/media-service.md): the
// `media.shelf` and `media.book` topics, `media.chapter` for a chapter's
// blocks, `media.image` for covers and pictures, `media.place.set` as pages
// turn. The station is $MBUI_MEDIA_STATION ("<workspace>/<station>"), else
// the first station of the first workspace.

///|
/// Chapters asked for, by "book/index": None while on their way.
let chapters : Map[String, Result[Array[@ui.Block], String]?] = {}

///|
/// Pictures asked for, by their image key.
let pictures : Map[String, Bool] = {}

///|
fn media_station() -> String? {
  let chosen = env("MBUI_MEDIA_STATION")
  if chosen.length() > 0 {
    return Some(chosen)
  }
  let ws = @core.subscribe("workspaces")
  guard ws.value is Some(Array(accounts)) && accounts.length() > 0 else {
    return None
  }
  let first = match accounts[0] {
    Object(a) =>
      match a.get("workspaces") {
        Some(Array(list)) if list.length() > 0 => str(Some(list[0]), "id")
        _ => ""
      }
    _ => ""
  }
  if first.length() == 0 {
    return None
  }
  let stations = @core.subscribe("stations", params={ "scope": Json::string(first) })
  match stations.value {
    Some(Array(list)) if list.length() > 0 => Some(str(Some(list[0]), "station"))
    _ => None
  }
}

///|
fn num(v : Json?, key : String) -> Double? {
  match v {
    Some(Object(m)) =>
      match m.get(key) {
        Some(Number(d, ..)) => Some(d)
        _ => None
      }
    _ => None
  }
}

///|
/// The image key of picture `ref` of `book`, its bytes asked for the first
/// time it is wanted.
fn picture(station : String, book : String, ref_ : String) -> String {
  let key = "mem:\{book}/\{ref_}"
  if !pictures.contains(key) {
    pictures[key] = true
    let params : Map[String, Json] = {
      "station": Json::string(station),
      "book": Json::string(book),
      "ref": Json::string(ref_),
    }
    @core.call_bytes("media.image", params=Json::object(params), on_done=fn(r) {
      match r {
        Ok((_, Some(bytes))) => {
          @ui.add_image(key, bytes)
        }
        _ => ()
      }
    })
  }
  key
}

///|
/// A block as the media service sends it, for the reader.
fn block_of(station : String, book : String, b : Json) -> @ui.Block? {
  match str(Some(b), "t") {
    "p" =>
      match b {
        Object(m) =>
          match m.get("runs") {
            // styled runs: their text (bold, italic and links not shown yet)
            Some(Array(runs)) => {
              let sb = StringBuilder()
              for run in runs {
                sb.write_string(str(Some(run), "text"))
              }
              Some(Para(sb.to_string()))
            }
            _ => Some(Para(str(Some(b), "text")))
          }
        _ => None
      }
    "h" => Some(Heading(str(Some(b), "text")))
    "img" => {
      let src = picture(station, book, str(Some(b), "ref"))
      let w = num(Some(b), "w").unwrap_or(800.0)
      let h = num(Some(b), "h").unwrap_or(600.0)
      Some(Picture(src, w, h))
    }
    "hr" => Some(Rule)
    _ => None
  }
}

///|
fn core_books() -> Result[Array[@shelf.BookInfo], String]? {
  guard media_station() is Some(station) else { return None }
  import_books()
  let s = @core.subscribe("media.shelf", params={ "station": Json::string(station) })
  match (s.value, s.error) {
    (Some(Object(m)), _) =>
      match m.get("books") {
        Some(Array(list)) =>
          Some(
            Ok(
              list.map(fn(b) {
                let id = str(Some(b), "id")
                let cover_ref = str(Some(b), "coverRef")
                let place = match b {
                  Object(bm) =>
                    match bm.get("place") {
                      Some(p) =>
                        Some(
                          (
                            num(Some(p), "chapter").unwrap_or(0.0).to_int(),
                            num(Some(p), "offset").unwrap_or(0.0).to_int(),
                          ),
                        )
                      None => None
                    }
                  _ => None
                }
                {
                  id,
                  title: str(Some(b), "title"),
                  author: str(Some(b), "author"),
                  chapters: num(Some(b), "chapters").unwrap_or(1.0).to_int(),
                  cover: if cover_ref.length() > 0 {
                    Some(picture(station, id, cover_ref))
                  } else {
                    None
                  },
                  place,
                  read: num(Some(b), "read"),
                }
              }),
            ),
          )
        _ => Some(Ok([]))
      }
    // the station installs the media service on the first request: the
    // shelf comes once it is up (the module's events read it again)
    (_, Some(e)) if str(Some(e), "code") == "module_starting" => None
    (_, Some(e)) => Some(Err(str(Some(e), "message")))
    _ => None
  }
}

///|
fn core_toc(book : String) -> Array[String]? {
  guard media_station() is Some(station) else { return None }
  let s = @core.subscribe("media.book", params={
    "station": Json::string(station),
    "book": Json::string(book),
  })
  match s.value {
    Some(Object(m)) =>
      match m.get("toc") {
        Some(Array(list)) => Some(list.map(fn(t) { str(Some(t), "title") }))
        _ => None
      }
    _ => None
  }
}

///|
fn core_chapter(book : String, index : Int) -> Result[Array[@ui.Block], String]? {
  guard media_station() is Some(station) else { return None }
  let key = "\{book}/\{index}"
  match chapters.get(key) {
    Some(got) => got
    None => {
      chapters[key] = None
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "book": Json::string(book),
        "index": Json::number(index.to_double()),
      }
      @core.call("media.chapter", params=Json::object(params), on_done=fn(r) {
        chapters[key] = Some(
          match r {
            Ok(Object(m)) =>
              match m.get("blocks") {
                Some(Array(bs)) => {
                  let out = []
                  for b in bs {
                    match block_of(station, book, b) {
                      Some(x) => out.push(x)
                      None => ()
                    }
                  }
                  Ok(out)
                }
                _ => Ok([])
              }
            Ok(_) => Ok([])
            Err(e) => Err(str(Some(e), "message"))
          },
        )
      })
      None
    }
  }
}

///|
fn core_save_place(book : String, chapter : Int, offset : Int, at : Double) -> Unit {
  guard media_station() is Some(station) else { return }
  let place : Map[String, Json] = {
    "chapter": Json::number(chapter.to_double()),
    "offset": Json::number(offset.to_double()),
    "at": Json::number(at.floor()),
  }
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "book": Json::string(book),
    "place": Json::object(place),
  }
  @core.call("media.place.set", params=Json::object(params))
}

///|
/// MBUI_MEDIA_IMPORT="<drive root>|<path>": puts the books there on the
/// shelf once (media.import), printing IMPORT … with the answer.
let import_done : Ref[Bool] = { val: false }

///|
fn import_books() -> Unit {
  let spec = env("MBUI_MEDIA_IMPORT")
  if import_done.val || spec.length() == 0 {
    return
  }
  guard media_station() is Some(station) else { return }
  import_done.val = true
  let (root, path) = match spec.find("|") {
    Some(i) => (spec.view(end_offset=i).to_owned(), spec.view(start_offset=i + 1).to_owned())
    None => (spec, "")
  }
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  }
  @host.log("IMPORT station \{station}")
  @core.call("media.import", params=Json::object(params), on_done=fn(r) {
    match r {
      Ok(v) => @host.log("IMPORT ok " + v.stringify())
      Err(e) => @host.log("IMPORT failed " + e.stringify())
    }
  })
}

///|
let core_source : @shelf.Source = {
  books: core_books,
  toc: core_toc,
  chapter: core_chapter,
  save_place: core_save_place,
  now: fn() { @ui.wall_ms() },
}
