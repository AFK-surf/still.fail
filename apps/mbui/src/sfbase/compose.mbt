// What is being written to a chat as the core keeps it (ember web/src/draft.ts useDraft; the core's composer.ts, the
// `composer` topic, by the draft's key: `<station>:<chat>`, `new:<workspace>` the workspace's new chat): its words,
// the passages it quotes, the files going up to the station (the core sends them up and says how far), whether it can
// be sent, what went wrong. Each chat has its own while the page shows another; the core keeps each on the device as the
// chat's draft. This only shows it and says what is done to it: what is typed is the page's at once (and told to the
// core as it is typed), the rest as the page has done it until the core has it too.

///|
/// A draft as the page has it: its words (the field's, at once), and the rest as the core last said it, or as the page
/// did it while the core has not answered (`pending` calls under way, the core's `version` they were answered at,
/// the `rev` of the core's own words shown, the topic's version adopted).
pub(all) struct Writing {
  key : String
  field : @ui.Field
  text : @signals.Signal[String]
  mut quotes : Array[Json]
  mut files : Array[Json]
  mut focus : String
  mut starting : Bool
  mut error : String
  mut ready : Bool
  mut uploading : Bool
  pending : @signals.Signal[Int]
  mut acked : Double
  mut seen_rev : Double
  mut adopted : Int
  /// what `take` took, put back by `restore`
  mut taken : (String, Array[Json], Array[Json])?
}

///|
/// Each draft by its key, as the page has it.
pub let writings : Map[String, Writing] = {}

///|
/// The pictures of the files picked or pasted here, by their id: shown at once from their bytes (until the file leaves
/// the draft), and the station each went up to with its bytes (one sent to another station goes up again there).
pub let writing_pictures : Map[String, String] = {}

///|
let writing_went : Map[String, (String, String, Bytes)] = {}

///|
/// The videos added here, read whole, that the host has no picture of (no address for them: @hostapi.Picked.src), by
/// their id: their picture their first frame, drawn here from their bytes (writing_went) by writing_stills.
// kept across runs: put back by writings_reset (sfbase's reset)
let writing_unseen : Set[String] = Set::new()

///|
/// The stills of the videos waiting here the host has no picture of, made from their bytes (bytes_first_frame), each
/// its tile's picture and its message's once made: called as a composer is built.
pub fn writing_stills(c : @ui.Ctx) -> Unit {
  for id in writing_unseen.to_array() {
    guard writing_went.get(id) is Some((_, name, bytes)) else {
      writing_unseen.remove(id)
      continue
    }
    match bytes_first_frame(c, "draft/" + id, name, bytes) {
      "" => ()
      "!" => writing_unseen.remove(id)
      still => {
        writing_unseen.remove(id)
        writing_pictures[id] = still
        sent_pictures["upload\u{1}" + id] = still
      }
    }
  }
}

///|
/// The station each file added here goes up to, by its id.
// kept across runs: put back by writings_reset (sfbase's reset)
let writing_stations : Map[String, String] = {}

///|
/// Whether file `id` of a draft was put up from here (picked or pasted here: writing_add), which every message it goes
/// with says (Attachment.upload: file_key).
pub fn writing_put_here(id : String) -> Bool {
  writing_stations.contains(id)
}

///|
/// What each file picked or pasted here is (file_seed, held_seed), by its id: the same one added again while it is in
/// its draft is not added twice.
// kept across runs: put back by writings_reset (sfbase's reset)
let writing_seeds : Map[String, String] = {}

///|
/// Whether draft `w` has the file `seed` names already (writing_seeds).
fn writing_has(w : Writing, seed : String) -> Bool {
  w.files.iter().any(fn(f) { writing_seeds.get(text(Some(f), "id")) == Some(seed) })
}

///|
/// The files added here, counted (each its own id).
let writing_n : Ref[Int] = { val: 0 }

///|
pub fn writings_reset() -> Unit {
  quoted_into.clear()
  files_put.clear()
  writing_stations.clear()
  shared_into.clear()
  writings.clear()
  writing_pictures.clear()
  writing_went.clear()
  writing_unseen.clear()
  writing_seeds.clear()
  writing_n.val = 0
}

///|
/// The draft `key`, as the core says it now unless the page has done something it has not answered yet.
pub fn writing(src : Source, key : String) -> Writing {
  let w = match writings.get(key) {
    Some(w) => w
    None => {
      let w : Writing = {
        key,
        field: @ui.Field::new(),
        text: @signals.signal(""),
        quotes: [],
        files: [],
        focus: "",
        starting: false,
        error: "",
        ready: false,
        uploading: false,
        pending: @signals.signal(0),
        acked: 0.0,
        seen_rev: -1.0,
        adopted: -1,
        taken: None,
      }
      writings[key] = w
      w
    }
  }
  let t = (src.topic)("composer", { "key": Json::string(key) })
  writing_adopt(w, t.value, t.version)
  w
}

///|
/// The core's value shown, unless the page has done something it has not answered yet; its own words (a new `rev`:
/// read back, taken, put back, carried on) into the field.
fn writing_adopt(w : Writing, v : Json?, version : Int) -> Unit {
  guard v is Some(Object(_)) else { return }
  if w.pending.get() > 0 || number(v, "version") < w.acked || w.adopted == version {
    return
  }
  w.adopted = version
  w.quotes = items(v, "quotes")
  w.files = items(v, "files")
  // a picture picked here (a quote's too: a mark's screenshot), up: its message drawn from it as picked, by the name
  // the station keeps it under (sent.mbt)
  for f in writing_files(w) {
    let o = Some(f)
    match (writing_pictures.get(text(o, "id")), writing_stations.get(text(o, "id")), field(o, "done")) {
      (Some(picture), Some(station), Some(done)) if text(Some(done), "path") != "" =>
        sent_pictures[sent_key(station, text(Some(done), "path"))] = picture
      _ => ()
    }
  }
  w.focus = text(v, "focus")
  w.starting = flag(v, "starting")
  w.error = text(v, "error")
  w.ready = flag(v, "ready")
  w.uploading = flag(v, "uploading")
  let rev = number(v, "rev")
  if rev != w.seen_rev {
    w.seen_rev = rev
    w.text.set(text(v, "text"))
    w.field.set(w.text.get())
  }
}

///|
/// Has the core do `what` to the draft (`composer.<what>`), what the page shows of it meanwhile done by `show`; `done`
/// its answer.
fn writing_act(
  src : Source,
  w : Writing,
  what : String,
  params : Map[String, Json],
  show? : (Writing) -> Unit = fn(_) {  },
  done? : (Result[Json, Json]) -> Unit = fn(_) {  },
  bytes? : Bytes,
) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  show(w)
  w.pending.set(w.pending.get() + 1)
  params["key"] = Json::string(w.key)
  let answered = fn(r : Result[Json, Json]) {
    w.pending.set(w.pending.get() - 1)
    match r {
      Ok(a) =>
        match field(Some(a), "version") {
          Some(Number(n, ..)) => w.acked = if n > w.acked { n } else { w.acked }
          _ => ()
        }
      Err(_) => ()
    }
    done(r)
  }
  match bytes {
    Some(b) => (src.call_bytes)("composer." + what, Json::object(params), b, answered)
    None => (src.call)("composer." + what, Json::object(params), answered)
  }
}

///|
/// What is typed, told to the core as it is typed (`composer.text`).
pub fn writing_text(src : Source, w : Writing, words : String) -> Unit {
  if words == w.text.get() {
    return
  }
  w.text.set(words)
  writing_act(src, w, "text", { "text": Json::string(words) })
}

///|
/// A file picked or pasted (`pasted`: long words kept as a file, what the core says of them) going up to `station`
/// (`composer.add`, its bytes beside the call): shown at once, a picture from its bytes, else the host's picture of it
/// (`still`: where the host has it, @hostapi.Picked.src; a video's still); or the picture of the quote `quote` (a
/// mark's screenshot), shown in its card.
pub fn writing_add(
  src : Source,
  w : Writing,
  station : String,
  name : String,
  bytes : Bytes,
  pasted? : Json,
  quote? : String = "",
  still? : String = "",
) -> Unit {
  // (the same file picked or pasted again: one tile, one upload; a quote's picture is its quote's own)
  let seed = file_seed(station, name, bytes)
  let picked = pasted is None && quote == ""
  if picked && writing_has(w, seed) {
    return
  }
  writing_n.val += 1
  let id = "f" + upload_id(w.key + "\u{1}" + seed, writing_n.val)
  if picked {
    writing_seeds[id] = seed
  }
  if pasted is None {
    match @pixels.image_size(bytes) {
      Some(_) => {
        let key = "mem:writing/" + id
        @ui.add_image(key, bytes)
        writing_pictures[id] = key
        // its message drawn from it, as picked, sent before it is up (it names its upload: sent.mbt)
        sent_pictures["upload\u{1}" + id] = key
      }
      None =>
        match host_picture(name, still) {
          "" if preview_kind(name).0 == Some(KVideo) => writing_unseen.add(id)
          "" => ()
          picture => {
            writing_pictures[id] = picture
            sent_pictures["upload\u{1}" + id] = picture
          }
        }
    }
  }
  writing_went[id] = (station, name, bytes)
  writing_stations[id] = station
  let blob : Map[String, Json] = {
    "hostBytes": [0, Json::number(bytes.length().to_double())],
    "type": Json::string(file_type(name)),
  }
  let one : Map[String, Json] = {
    "id": Json::string(id),
    "name": Json::string(name),
    "size": Json::number(bytes.length().to_double()),
    "blob": Json::object(blob),
  }
  match pasted {
    Some(p) => one["pasted"] = p
    None => ()
  }
  if quote != "" {
    one["quote"] = Json::string(quote)
  }
  let shown : Map[String, Json] = {
    "id": Json::string(id),
    "name": Json::string(name),
    "size": Json::number(bytes.length().to_double()),
  }
  match pasted {
    Some(p) => shown["pasted"] = p
    None => ()
  }
  shown_waiting(w, shown)
  writing_act(
    src,
    w,
    "add",
    { "station": Json::string(station), "files": Json::array([Json::object(one)]) },
    show=fn(w) {
      if quote == "" {
        w.files = w.files + [Json::object(shown)]
      } else {
        w.quotes = w.quotes.map(fn(q) {
          match q {
            Object(m) if text(Some(q), "id") == quote => {
              let n = m.copy()
              n["own"] = Json::object(shown)
              Json::object(n)
            }
            _ => q
          }
        })
      }
    },
    bytes~,
  )
}

///|
/// A file the host holds, too big to be read whole (a video: @hostapi.Picked.held), into the draft: the core sends it
/// up to `station`, reading it from the host a part at a time as it goes (`composer.add` with `blob: {hostFile, size,
/// type}`: still.fail's Android app's PickedFiles.kt); its tile the host's picture of it (a video's still).
pub fn writing_add_held(src : Source, w : Writing, station : String, f : @hostapi.Picked) -> Unit {
  // (the same file picked again, where the host has it: one tile, one upload)
  let seed = held_seed(station, f)
  if writing_has(w, seed) {
    return
  }
  writing_n.val += 1
  let id = "f" + upload_id(w.key + "\u{1}held\u{1}" + station + "\u{1}" + f.name + "\u{1}\{f.size}", writing_n.val)
  writing_seeds[id] = seed
  match host_picture(f.name, f.src) {
    "" => ()
    picture => {
      writing_pictures[id] = picture
      sent_pictures["upload\u{1}" + id] = picture
    }
  }
  writing_stations[id] = station
  let one : Map[String, Json] = {
    "id": Json::string(id),
    "name": Json::string(f.name),
    "size": Json::number(f.size),
    "blob": Json::object({
      "hostFile": Json::number(f.held.to_double()),
      "size": Json::number(f.size),
      "type": Json::string(file_type(f.name)),
    }),
  }
  let shown : Map[String, Json] = {
    "id": Json::string(id),
    "name": Json::string(f.name),
    "size": Json::number(f.size),
  }
  shown_waiting(w, shown)
  writing_act(
    src,
    w,
    "add",
    { "station": Json::string(station), "files": Json::array([Json::object(one)]) },
    show=fn(w) { w.files = w.files + [Json::object(shown)] },
  )
}

///|
/// A file as the page shows it until the core has it: a new chat's waits for its message, nothing going up yet
/// (composer.ts `waits`).
fn shown_waiting(w : Writing, shown : Map[String, Json]) -> Unit {
  if w.key.has_prefix("new:") {
    shown["waits"] = Json::boolean(true)
  }
}

///|
/// A file the system picked (or shared into the app) into the draft: held by the host (writing_add_held), or its bytes
/// (writing_add).
pub fn writing_add_picked(src : Source, w : Writing, station : String, f : @hostapi.Picked) -> Unit {
  if f.held != 0 {
    writing_add_held(src, w, station, f)
  } else {
    writing_add(src, w, station, f.name, f.bytes, still=f.src)
  }
}

///|
/// The host's picture of a file picked (@hostapi.Picked.src: an image's, a video's still), what its tile and its
/// message show while it is this device's: "" for a file of any other kind, which shows as a file's card.
pub fn host_picture(name : String, src : String) -> String {
  match preview_kind(name) {
    (Some(KImage | KVideo), _, _) => src
    _ => ""
  }
}

///|
/// Files shared into the app from another (Android's share sheet), waiting for their chat's composer to take them, by
/// its draft's key.
// kept across runs: put back by writings_reset (sfbase's reset)
pub let shared_into : Map[String, Array[@hostapi.Picked]] = {}

///|
/// The station files' picker (＋ → Station 文件) put up for draft `key` (`src` what it reads the stations by): sfdesk's
/// station_files_pick; what is ticked there comes into the draft as files_into does.
// kept across runs: what the app says once as it starts
pub let station_files_asked : Ref[(Source, String) -> Unit] = Ref(fn(_, _) {  })

///|
/// A folder of a station picked (src, its workspace, the station's address, what goes on with its path): sfdesk's
/// pick_folder, the files' page's picker.
// kept across runs: what the app says once as it starts
pub let folder_asked : Ref[(Source, String, String, (String) -> Unit) -> Unit] = Ref(fn(_, _, _, _) {  })

///|
/// Chat `r`'s services and jobs put up (an agent's card's jobs pressed, sfpages): the screen's (sfapp's: the desktop's
/// popover, the phone's panel).
// kept across runs: what the app says once as it starts
pub let chat_jobs_asked : Ref[(@ui.Ctx, Source, ChatRef) -> Unit] = Ref(fn(_, _, _) {  })

///|
/// Files and folders dragged in from where they are (a station's files: `ref` with its station, its name and path, a
/// folder or not; `drive` where it is in that station's drive), named by their path unless this chat takes files
/// dragged in as files (the core's `composer.add`, nothing of them going up yet).
pub fn writing_drop(src : Source, d : Writing, station : String, dropped : Array[Json], as_files : Bool) -> Unit {
  let files = dropped.map(fn(x) {
    writing_n.val += 1
    let v = Some(x)
    let r = match field(v, "ref") {
      Some(Object(m)) => m.copy()
      _ => {}
    }
    r["mode"] = Json::string(if as_files && !flag(Some(Json::object(r)), "dir") { "file" } else { "path" })
    let one : Map[String, Json] = {
      "id": Json::string("f" + upload_id(d.key + "\u{1}" + text(v, "name"), writing_n.val)),
      "name": Json::string(text(v, "name")),
      "size": Json::number(number(v, "size")),
      "ref": Json::object(r),
    }
    match field(v, "drive") {
      Some(Object(_) as dr) => one["drive"] = dr
      _ => ()
    }
    Json::object(one)
  })
  writing_act(src, d, "add", { "station": Json::string(station), "files": Json::array(files) }, show=fn(d) {
    d.files = d.files + files
  })
}

///|
/// A file dragged in, named by its path or sent as a file (`composer.mode`).
pub fn writing_mode(src : Source, w : Writing, id : String, mode : String) -> Unit {
  writing_act(src, w, "mode", { "id": Json::string(id), "mode": Json::string(mode) })
}

///|
/// A file out of the draft (`composer.remove`), its picture let go.
pub fn writing_remove(src : Source, w : Writing, id : String) -> Unit {
  writing_pictures.remove(id)
  writing_went.remove(id)
  writing_seeds.remove(id)
  writing_act(src, w, "remove", { "id": Json::string(id) }, show=fn(w) {
    w.files = w.files.filter(fn(f) { text(Some(f), "id") != id })
  })
}

///|
/// A file that failed to go up, sent up again (`composer.retry`).
pub fn writing_retry(src : Source, w : Writing, id : String) -> Unit {
  writing_act(src, w, "retry", { "id": Json::string(id) })
}

///|
/// A passage quoted (its `author`, `text`, its message's `ts` and `role`), its comment line asking for the focus while
/// nothing is said of it (a mark's quote comes with what its note said: written, it asks for nothing); with
/// its picture: an image of a message (`file`: it goes again with the message as the station has it, by `quoted-<id>`),
/// or a mark's screenshot (`picture`: the station it goes up to, its name and bytes).
pub fn writing_quote(src : Source, w : Writing, quote : Json, file? : Json, picture? : (String, String, Bytes)) -> Unit {
  writing_n.val += 1
  let id = "q" + writing_n.val.to_string()
  let ask = text(Some(quote), "comment") == ""
  let p : Map[String, Json] = { "id": Json::string(id), "quote": quote, "focus": Json::boolean(ask) }
  match file {
    Some(f) => {
      p["attachment"] = f
      p["fileId"] = Json::string("quoted-" + id)
    }
    None => ()
  }
  writing_act(src, w, "quote", p, show=fn(w) { if ask { w.focus = id } })
  match picture {
    Some((station, name, bytes)) => writing_add(src, w, station, name, bytes, quote=id)
    None => ()
  }
}

///|
/// Its files and its quotes' own pictures (the core's composer keeps both among its files; its message has both among
/// its own).
pub fn writing_files(w : Writing) -> Array[Json] {
  w.files + w.quotes.filter_map(fn(q) { field(Some(q), "own") })
}

///|
/// What is said about a quote (`composer.comment`), the page's at once as the words are.
pub fn writing_comment(src : Source, w : Writing, id : String, words : String) -> Unit {
  writing_act(src, w, "comment", { "id": Json::string(id), "comment": Json::string(words) }, show=fn(w) {
    w.quotes = w.quotes.map(fn(q) {
      match q {
        Object(m) if text(Some(q), "id") == id => {
          let said = m.copy()
          said["comment"] = Json::string(words)
          Json::object(said)
        }
        _ => q
      }
    })
  })
}

///|
/// A quote let go (`composer.unquote`), its picture with it.
pub fn writing_unquote(src : Source, w : Writing, id : String) -> Unit {
  match w.quotes.iter().find_first(fn(q) { text(Some(q), "id") == id }) {
    Some(q) => {
      let own = text(field(Some(q), "own"), "id")
      writing_pictures.remove(own)
      writing_went.remove(own)
    }
    None => ()
  }
  writing_act(src, w, "unquote", { "id": Json::string(id) }, show=fn(w) {
    w.quotes = w.quotes.filter(fn(q) { text(Some(q), "id") != id })
    if w.focus == id {
      w.focus = ""
    }
  })
}

///|
/// A quote's comment line has the focus it asked for (`composer.focused`).
pub fn writing_focused(src : Source, w : Writing) -> Unit {
  writing_act(src, w, "focused", {}, show=fn(w) { w.focus = "" })
}

///|
/// What went wrong said in the draft, or no longer (`composer.error`).
pub fn writing_error(src : Source, w : Writing, error : String) -> Unit {
  writing_act(src, w, "error", { "error": if error == "" { Json::null() } else { Json::string(error) } }, show=fn(w) {
    w.error = error
  })
}

///|
/// A new chat being made for the message, or no longer (`composer.starting`).
pub fn writing_starting(src : Source, w : Writing, on : Bool) -> Unit {
  writing_act(src, w, "starting", { "starting": Json::boolean(on) }, show=fn(w) { w.starting = on })
}

///|
/// What is written taken away to be sent (`composer.take`): the draft empty at once; `done` gets what the core took,
/// as it goes (its words with the links and the paths named after them, the files that are up, the quotes, those still
/// going up), sent as it says: its files as they were when it took them, not as this page last drew them. `station`:
/// the one it goes to, where a new chat's files go up now.
pub fn writing_take(src : Source, w : Writing, station? : String = "", done : (Json?) -> Unit) -> Unit {
  w.taken = Some((w.text.get(), w.quotes, w.files))
  let params : Map[String, Json] = {}
  if station != "" {
    params["station"] = Json::string(station)
  }
  writing_act(
    src,
    w,
    "take",
    params,
    show=fn(w) {
      w.text.set("")
      w.field.set("")
      w.quotes = []
      w.files = []
      w.focus = ""
      w.error = ""
      w.ready = false
    },
    done=fn(r) {
      match r {
        Ok(v) => done(Some(v))
        Err(_) => done(None)
      }
    },
  )
}

///|
/// What `take` took put back (a chat that could not be made, a message never sent), saying why; with `unless_written`,
/// only while nothing new is written there (`composer.restore`).
pub fn writing_restore(src : Source, w : Writing, error : String, unless_written? : Bool = false) -> Unit {
  if unless_written && (w.text.get().trim(chars=" \n\t").to_string() != "" || w.files.length() > 0 || w.quotes.length() > 0) {
    return
  }
  let kept = w.taken
  w.taken = None
  writing_act(
    src,
    w,
    "restore",
    {
      "error": if error == "" { Json::null() } else { Json::string(error) },
      "unlessWritten": Json::boolean(unless_written),
    },
    show=fn(w) {
      match kept {
        Some((words, quotes, files)) => {
          w.text.set(words)
          w.field.set(words)
          w.quotes = quotes
          w.files = files
        }
        None => ()
      }
      w.error = error
    },
  )
}

///|
/// What is written in `from` goes on into `to` (a new chat becoming the chat it made, or its station changed): `from`
/// left empty (`composer.carry`).
pub fn writing_carry(src : Source, from : String, to : String) -> Unit {
  let w = writing(src, from)
  writing_act(src, w, "carry", { "to": Json::string(to) })
}

///|
/// The station a file added here went up to and its bytes, while it is in a draft (sent to another station, it goes up
/// again there).
pub fn writing_went_to(id : String) -> (String, String, Bytes)? {
  writing_went.get(id)
}

///|
/// What a file is by its name's ending, for the core (a picture's size is read from its head as it goes up): "" when
/// not known.
pub fn file_type(name : String) -> String {
  let lower = name.to_lower()
  let ends = fn(e : String) { lower.has_suffix(e) }
  if ends(".png") {
    "image/png"
  } else if ends(".jpg") || ends(".jpeg") {
    "image/jpeg"
  } else if ends(".gif") {
    "image/gif"
  } else if ends(".webp") {
    "image/webp"
  } else if ends(".heic") {
    "image/heic"
  } else if ends(".mp4") || ends(".m4v") {
    "video/mp4"
  } else if ends(".mov") {
    "video/quicktime"
  } else if ends(".webm") {
    "video/webm"
  } else if ends(".3gp") {
    "video/3gpp"
  } else if ends(".pdf") {
    "application/pdf"
  } else if ends(".txt") {
    "text/plain"
  } else {
    ""
  }
}

///|
/// A file as the core gives it (Attachment), kept by `owner`'s workspace.
pub fn attachment_json(a : Attachment, owner : String) -> Json {
  let o : Map[String, Json] = {
    "name": Json::string(a.name),
    "path": Json::string(a.path),
    "size": Json::number(a.size),
  }
  if a.width > 0.0 && a.height > 0.0 {
    o["width"] = Json::number(a.width)
    o["height"] = Json::number(a.height)
  }
  if a.thumbhash != "" {
    o["thumbhash"] = Json::string(a.thumbhash)
  }
  if a.duration > 0.0 {
    o["duration"] = Json::number(a.duration)
  }
  if a.frames > 0 {
    o["frames"] = Json::number(a.frames.to_double())
  }
  if owner != "" {
    o["owner"] = Json::string(owner)
  }
  Json::object(o)
}

///|
/// A message's file quoted into a chat's draft (a picture's menu, 引用): by the draft's key, whose (`author`), the
/// message's `ts`, its role, the file as the core gives it; taken by whichever composer the draft's is, as it is next
/// drawn (its quote with the file in its card, the file going again with the message as the station has it).
pub fn quote_file_into(draft : String, author : String, ts : String, role : String, file : Json) -> Unit {
  let list = quoted_into.get(draft).unwrap_or([])
  list.push((author, ts, role, file))
  quoted_into[draft] = list
  draft_given()
}

///|
/// Files (a 文件 row) put into a chat's message from elsewhere (the files' tab: 添加到消息, a row let go on the chat), by
/// the chat's key; taken by its composer as it is next drawn (files_taken).
pub fn files_into(chat : String, d : Dragged) -> Unit {
  files_put.push((chat, d))
  draft_given()
}

///|
/// What was put into the chat `chat`'s message since it was last asked, taken.
pub fn files_taken(chat : String) -> Array[Dragged] {
  drafts_given_read()
  let out = files_put.filter(fn(x) { x.0 == chat }).map(fn(x) { x.1 })
  files_put.retain(fn(x) { x.0 != chat })
  out
}

///|
/// Whether files from this machine's Finder let go on a chat are taken by where they are (finder_dragged): where this
/// machine is a station. Elsewhere a field takes them as their paths, words.
pub fn finder_by_station() -> Bool {
  this_machine() != ""
}

///|
/// Files from this machine's Finder let go on a chat (@ui.Ctx::paths_into), as a 文件 row of this machine's station
/// carries them: each by its station and path, for the chat's message to name so or send as a file as it takes what is
/// dragged in (prefs `dropFiles`, `dropAs`), the station reading it from where it is. None where this machine is no
/// station (finder_by_station).
pub fn finder_dragged(src : Source, paths : Array[@ui.DroppedPath]) -> Array[Dragged] {
  let station = this_machine()
  if station == "" {
    return []
  }
  let station_name = match dv_stations(src, workspace_of(station)).0 {
    Some(list) =>
      match list.iter().find_first(fn(s) { s.station == station }) {
        Some(s) => s.name
        None => ""
      }
    None => ""
  }
  let station_name = if station_name != "" {
    station_name
  } else {
    match station.rev_find("/") {
      Some(i) => station.view(start_offset=i + 1).to_owned()
      None => station
    }
  }
  paths.map(fn(p) {
    let abs = if p.path.length() > 1 && p.path.has_suffix("/") {
      p.path.view(end_offset=p.path.length() - 1).to_owned()
    } else {
      p.path
    }
    // (its folder the root it is asked from: the station's own reach any folder of it, drive.ts `anywhere`)
    let (root, name) = match abs.rev_find("/") {
      Some(0) => ("/", abs.view(start_offset=1).to_owned())
      Some(i) => (abs.view(end_offset=i).to_owned(), abs.view(start_offset=i + 1).to_owned())
      None => ("", abs)
    }
    { station, station_name, root, path: name, abs, name, size: p.size, dir: p.dir }
  })
}

///|
// kept across runs: put back by writings_reset (sfbase's reset)
let files_put : Array[(String, Dragged)] = []

///|
/// Told as anything is put into a draft from elsewhere (files_into, quote_file_into, shared_into, marked_into,
/// followed_into): what takes it (a composer as it is built) built again for it.
// kept across runs: only counts on
let drafts_given : @signals.Signal[Int] = @signals.signal(0)

///|
/// Something put into a draft from elsewhere: what takes it told.
pub fn draft_given() -> Unit {
  drafts_given.set(@signals.untracked(fn() { drafts_given.get() }) + 1)
}

///|
/// What is put into drafts from elsewhere, read (a composer taking what was put into its draft).
pub fn drafts_given_read() -> Unit {
  drafts_given.get() |> ignore
}

///|
/// What a row dragged now carries, as the frame that drags it says (sfdesk's drag.mbt), for a composer it goes over.
// kept across runs: what the app says once as it starts
pub let drag_carried : Ref[() -> Dragged?] = Ref(fn() { None })

///|
/// The chat before (-1) or after (1) the one open, gone to by a composer's ↑ or ↓ (empty, focused), as the shell
/// says as the app starts (its list's order); none while the shell has the arrows itself (its switcher open).
// kept across runs: what the app says once as it starts
pub let neighbour_go : Ref[(Source, Workspace, Int) -> Unit] = Ref(fn(_, _, _) {  })

///|
/// Whether the shell has the arrows now (neighbour_go).
// kept across runs: what the app says once as it starts
pub let neighbour_held : Ref[() -> Bool] = Ref(fn() { false })

///|
/// The files quoted, by draft key, not yet taken by a composer.
// kept across runs: put back by writings_reset (sfbase's reset)
pub let quoted_into : Map[String, Array[(String, String, String, Json)]] = {}
