// A link's card's pictures (a page's icon and picture, a pull request's author's face) and a file's peek's, as their
// topics (`linkPreview`, `filePeek`) name them: each by a token alone, its bytes asked of the core beside a call's
// answer (`link.preview.picture`, `file.peek.picture`: core-ts peek-pictures.ts, out of what the topic's read brought,
// no request made), each once and kept as an image as a chat's pictures are (`Source::images`, chat_images.mbt): its
// key once here, "" while it comes, "!" when there is none. Until 2026-11-11 they came inline in the topics' values
// (a page's 222 KB, a picture file's 342 KB), parsed on the frame thread and their base64 decoded there.
//
// A card whose value names pictures shows once they are here or have failed (`link_pictures_here`, a file's
// `file_peek_picture` not ""), never first without them and then with: until then it shows what it shows while its topic is
// read. They are asked as soon as the value is read (as the pointer comes onto the link, before its card opens), so
// the card mostly opens whole.

///|
/// Each answer come for such a picture, followed: what reads one reads it, so a node bound to it is drawn again as it
/// comes (the images' keys are no signal).
// kept across runs: only counted on
let peek_pictures_came : @signals.Signal[Int] = @signals.signal(0)

///|
/// Picture `id` asked of the core with `call` and `params`: its image's key once here, "" while it comes, "!" when
/// there is none (the core's error, or no bytes).
fn peek_picture_of(src : Source, station : String, id : String, call : String, params : Map[String, Json]) -> String {
  peek_pictures_came.get() |> ignore
  // (an answer given at once, from within the asking, is read below, not told)
  let asking = Ref(true)
  let key = src.images.get(station, id, "mem:peek/\{@ui.stable_hash(id)}/\{id.length()}", fn(_, done) {
    (src.read_bytes)(call, Json::object(params), fn(r) {
      done(r.map(fn(a) { (a.0, Some(a.1)) }))
      if !asking.val {
        peek_pictures_came.set(peek_pictures_came.untracked() + 1)
      }
    })
  })
  asking.val = false
  if key == "" {
    src.images.keys.get(id).unwrap_or("")
  } else {
    key
  }
}

///|
/// Picture `which` (`icon`, `image`, `avatar`: its author's) of the card of link `url` on station `station` whose
/// value is `v`: its image's key once here, "" while it comes, "!" when it has none.
pub fn link_picture(src : Source, station : String, url : String, v : Json?, which : String) -> String {
  let token = if which == "avatar" { text(field(v, "author"), "avatar") } else { text(v, which) }
  if token == "" || station == "" {
    return "!"
  }
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "url": Json::string(url),
    "which": Json::string(which),
  }
  peek_picture_of(
    src,
    station,
    "link\u{1}" + station + "\u{1}" + url + "\u{1}" + which + "\u{1}" + token,
    "link.preview.picture",
    params,
  )
}

///|
/// Whether every picture value `v` of link `url`'s card names is here or has failed (each asked now, the first time):
/// what the card shows waits for them.
pub fn link_pictures_here(src : Source, station : String, url : String, v : Json?) -> Bool {
  let mut here = true
  for which in ["icon", "image", "avatar"] {
    if link_picture(src, station, url, v, which) == "" {
      here = false
    }
  }
  here
}

///|
/// The picture of the peek `v` of file `path` (`line` as the `filePeek` topic was asked with it) the session `key` of
/// station `station` names: its image's key once here, "" while it comes, "!" when it has none.
pub fn file_peek_picture(src : Source, station : String, key : String, path : String, line : Int?, v : Json?) -> String {
  let token = text(field(v, "image"), "picture")
  if token == "" || station == "" {
    return "!"
  }
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "key": Json::string(key),
    "path": Json::string(path),
  }
  match line {
    Some(n) => params["line"] = Json::number(n.to_double())
    None => ()
  }
  peek_picture_of(
    src,
    station,
    "peek\u{1}" + station + "\u{1}" + key + "\u{1}" + path + "\u{1}" + line.map(fn(n) { n.to_string() }).unwrap_or("") +
    "\u{1}" + token,
    "file.peek.picture",
    params,
  )
}

///|
/// A picture's key as it is drawn: none ("") where it has none or it has not come.
pub fn picture_drawn(key : String) -> String {
  if key == "!" {
    ""
  } else {
    key
  }
}
