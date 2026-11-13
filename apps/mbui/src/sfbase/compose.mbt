// What is being written to a chat as the core keeps it (still.fail web/src/draft.ts useDraft; the core's composer.ts, the
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
  text : @signals.Computed[String]
  quotes : @signals.Computed[Array[Json]]
  files : @signals.Computed[Array[Json]]
  focus : @signals.Computed[String]
  starting : @signals.Computed[Bool]
  error : @signals.Computed[String]
  ready : @signals.Computed[Bool]
  uploading : @signals.Computed[Bool]
  pending : @signals.Signal[Int]
  priv state : WritingState
  priv following : @signals.Computed[Unit]
  /// what `take` took, put back by `restore`
  mut taken : (String, Array[Json], Array[Json])?
}

///|
priv struct WritingState {
  field : @ui.Field
  text : @signals.Signal[String]
  quotes : @signals.Signal[Array[Json]]
  files : @signals.Signal[Array[Json]]
  focus : @signals.Signal[String]
  starting : @signals.Signal[Bool]
  error : @signals.Signal[String]
  ready : @signals.Signal[Bool]
  uploading : @signals.Signal[Bool]
  pending : @signals.Signal[Int]
  mut acked : Double
  mut seen_rev : Double
  mut adopted : Int
  mut generation : Int
  /// The committed words when a different core revision arrived during input-method composition.
  mut composing_base : String?
}

///|
priv struct WritingCached {
  source : Source
  key : String
  value : Writing
}

///|
let writing_cache : Ref[Array[WritingCached]] = Ref([])

///|
/// Each draft by its key, as the page has it.
pub let writings : Map[String, Writing] = Map([])

///|
/// The pictures of the files picked or pasted here, by their id: shown at once from their bytes (until the file leaves
/// the draft), and the station each went up to with its bytes (one sent to another station goes up again there).
pub let writing_pictures : Map[String, String] = Map([])

///|
let writing_went : Map[String, (String, String, Bytes)] = Map([])

///|
/// The videos added here, read whole, that the host has no picture of (no address for them: @hostapi.Picked.src), by
/// their id: their picture their first frame, drawn here from their bytes (writing_went) by writing_stills.
// kept across runs: put back by writings_reset (sfbase's reset)
let writing_unseen : Set[String] = Set([])

///|
/// The stills of the videos waiting here the host has no picture of, made from their bytes (bytes_first_frame), each
/// its tile's picture and its message's once made: called as a composer is built.
pub fn writing_stills(c : @ui.Ctx) -> Unit {
  for id in writing_unseen.to_array() {
    guard writing_went.get(id) is Some((station, name, bytes)) else {
      writing_unseen.remove(id)
      continue
    }
    match bytes_first_frame(c, "draft/" + id, name, bytes) {
      "" => ()
      "!" => writing_unseen.remove(id)
      still => {
        writing_unseen.remove(id)
        writing_pictures[id] = still
        sent_picture_kept("upload\u{1}" + id, still)
        for _, w in writings {
          for f in writing_files(w) {
            let o = Some(f)
            if text(o, "id") == id {
              let path = text(field(o, "done"), "path")
              if path != "" {
                sent_picture_kept(sent_key(station, path), still)
              }
            }
          }
        }
      }
    }
  }
}

///|
/// The station each file added here goes up to, by its id.
// kept across runs: put back by writings_reset (sfbase's reset)
let writing_stations : Map[String, String] = Map([])

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
let writing_seeds : Map[String, String] = Map([])

///|
/// Whether draft `w` has the file `seed` names already (writing_seeds).
fn writing_has(w : Writing, seed : String) -> Bool {
  w.state.files.get().iter().any(fn(f) { writing_seeds.get(text(Some(f), "id")) == Some(seed) })
}

///|
/// The files added here, counted (each its own id).
let writing_n : Ref[Int] = { val: 0 }

///|
pub fn writings_reset() -> Unit {
  quoted_into.clear()
  files_put.clear()
  drafts_given.set([])
  writing_stations.clear()
  shared_into.clear()
  for cached in writing_cache.val {
    cached.value.following.dispose()
  }
  // Array::clear keeps removed slots alive; drop its backing array when the app releases its drafts.
  writing_cache.val = []
  writings.clear()
  writing_pictures.clear()
  writing_went.clear()
  writing_unseen.clear()
  writing_seeds.clear()
  writing_n.val = 0
}

///|
/// Read one field and follow the shared core resource for as long as the computed has graph readers.
fn[T] writing_value(value : @signals.Signal[T], following : @signals.Computed[Unit], same : (T, T) -> Bool) -> @signals.Computed[T] {
  @signals.computed_following(fn(_) { value.get() }, following, same~)
}

///|
/// A draft is shared by its source and key, independent of which page or node reads it.
fn writing_cached(src : Source, key : String) -> Writing {
  match writing_cache.val.search_by(fn(w) { physical_equal(w.source, src) && w.key == key }) {
    Some(i) => writing_cache.val[i].value
    None => {
      let state : WritingState = {
        field: @ui.Field::new(),
        text: @signals.signal("", same=fn(a, b) { a == b }),
        quotes: @signals.signal([], same=fn(a, b) { a == b }),
        files: @signals.signal([], same=fn(a, b) { a == b }),
        focus: @signals.signal("", same=fn(a, b) { a == b }),
        starting: @signals.signal(false),
        error: @signals.signal("", same=fn(a, b) { a == b }),
        ready: @signals.signal(false),
        uploading: @signals.signal(false),
        pending: @signals.signal(0),
        acked: 0.0,
        seen_rev: -1.0,
        adopted: -1,
        generation: -1,
        composing_base: None,
      }
      let topic = src.topic("composer", { "key": Json::string(key) })
      let following = @signals.computed(fn(_) {
        // (what the core reads of its field's words: its marks, its `@` words, refs.mbt)
        refs_follow(src, key, state.field)
        @signals.effect(fn() {
          let t = topic.get()
          state.pending.get() |> ignore
          let composing = state.field.composing()
          @signals.untracked(fn() {
            let (generation, fresh) = (src.generation)("composer", { "key": Json::string(key) })
            writing_adopt(state, t.value, t.version, generation, fresh, composing)
          })
        }) |> ignore
      })
      let w : Writing = {
        key,
        field: state.field,
        text: writing_value(state.text, following, fn(a, b) { a == b }),
        quotes: writing_value(state.quotes, following, fn(a, b) { a == b }),
        files: writing_value(state.files, following, fn(a, b) { a == b }),
        focus: writing_value(state.focus, following, fn(a, b) { a == b }),
        starting: writing_value(state.starting, following, fn(a, b) { a == b }),
        error: writing_value(state.error, following, fn(a, b) { a == b }),
        ready: writing_value(state.ready, following, fn(a, b) { a == b }),
        uploading: writing_value(state.uploading, following, fn(a, b) { a == b }),
        pending: state.pending,
        state,
        following,
        taken: None,
      }
      writing_cache.val.push({ source: src, key, value: w })
      writings[key] = w
      w
    }
  }
}

///|
/// The shared draft, followed by what reads its fields. An untracked call only reads the current topic once.
pub fn writing(src : Source, key : String) -> Writing {
  let w = writing_cached(src, key)
  if @signals.active_sub() is Some(_) {
    w.following.get()
  } else {
    let t = src.topic("composer", { "key": Json::string(key) }).get()
    @signals.untracked(fn() {
      let (generation, fresh) = (src.generation)("composer", { "key": Json::string(key) })
      writing_adopt(w.state, t.value, t.version, generation, fresh, w.field.composing())
    })
  }
  w
}

///|
/// The core's value shown, unless the page has done something it has not answered yet; its own words (a new `rev`:
/// read back, taken, put back, carried on) into the field.
fn writing_adopt(w : WritingState, v : Json?, version : Int, generation : Int, fresh : Bool, composing : Bool) -> Unit {
  if w.generation != generation {
    // A restarting client keeps the old value visible until the new core answers. Do not count that old revision as
    // the new core's: its first value can have the same revision but different contents.
    if !fresh && v is Some(_) {
      return
    }
    // A new core has its own composer version and revision sequence.
    w.generation = generation
    w.acked = 0.0
    w.adopted = -1
    w.seen_rev = -1.0
    w.composing_base = None
  }
  if v is None && version == 0 {
    // A fresh subscription has its own message count even within the same core lifetime.
    w.adopted = -1
  }
  guard v is Some(Object(_)) else { return }
  if w.pending.get() > 0 || number(v, "version") < w.acked ||
    (w.adopted == version && (composing || w.composing_base is None)) {
    return
  }
  w.adopted = version
  @signals.start_batch()
  w.quotes.set(items(v, "quotes"))
  w.files.set(items(v, "files"))
  // a picture picked here (a quote's too: a mark's screenshot), up: its message drawn from it as picked, by the name
  // the station keeps it under (sent.mbt)
  let files = w.files.get() + w.quotes.get().filter_map(fn(q) { field(Some(q), "own") })
  for f in files {
    let o = Some(f)
    match (writing_pictures.get(text(o, "id")), writing_stations.get(text(o, "id")), field(o, "done")) {
      (Some(picture), Some(station), Some(done)) if text(Some(done), "path") != "" =>
        sent_picture_kept(sent_key(station, text(Some(done), "path")), picture)
      _ => ()
    }
  }
  w.focus.set(text(v, "focus"))
  w.starting.set(flag(v, "starting"))
  w.error.set(text(v, "error"))
  w.ready.set(flag(v, "ready"))
  w.uploading.set(flag(v, "uploading"))
  let rev = number(v, "rev")
  if rev != w.seen_rev || (!composing && w.composing_base is Some(_)) {
    let words = text(v, "text")
    if composing && w.field.text() != words {
      // Leave marked text alone. When it ends, a cancel adopts the latest core words; a committed edit keeps its own.
      if w.composing_base is None {
        w.composing_base = Some(w.field.text())
      }
    } else {
      let edited = match w.composing_base {
        Some(base) => !composing && w.field.text() != base
        None => false
      }
      w.composing_base = None
      w.seen_rev = rev
      if !edited {
        w.text.set(words)
        if w.field.text() != words {
          w.field.set(words)
        }
      }
    }
  }
  @signals.end_batch()
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
  @signals.start_batch()
  w.pending.set(w.pending.get() + 1)
  show(w)
  @signals.end_batch()
  params["key"] = Json::string(w.key)
  let answered = fn(r : Result[Json, Json]) {
    @signals.start_batch()
    match r {
      Ok(a) =>
        match field(Some(a), "version") {
          Some(Number(n, ..)) => w.state.acked = if n > w.state.acked { n } else { w.state.acked }
          _ => ()
        }
      Err(_) => w.state.adopted = -1
    }
    w.pending.set(w.pending.get() - 1)
    done(r)
    @signals.end_batch()
  }
  match bytes {
    Some(b) => (src.call_bytes)("composer." + what, Json::object(params), b, answered)
    None => (src.call)("composer." + what, Json::object(params), answered)
  }
}

///|
/// The core's calls whose answers change only signals (@core.said, as the app starts; a made-up core's the same): the
/// words of a draft told (`composer.text`: what writing_act does with its answer, `pending` and the version it is at,
/// read by what follows the draft's topic), where a ref is asked at the caret (`ref.at`: refs_ask_at's, what it found
/// set with the signals the menu reads). Taken as they come, what read those is built again, nothing else: not a page
/// whose field had a word typed in it built whole for each.
pub fn calls_said() -> Array[String] {
  ["composer.text", "ref.at"]
}

///|
/// Whether call `name`'s answer changes only signals (calls_said).
pub fn call_said(name : String) -> Bool {
  calls_said().contains(name)
}

///|
/// What is typed, told to the core as it is typed (`composer.text`).
pub fn writing_text(src : Source, w : Writing, words : String) -> Unit {
  if words == w.text.get() {
    return
  }
  @signals.start_batch()
  w.state.text.set(words)
  writing_act(src, w, "text", { "text": Json::string(words) })
  @signals.end_batch()
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
        sent_picture_kept("upload\u{1}" + id, key)
      }
      None =>
        match host_picture(name, still) {
          "" if preview_kind(name).0 == Some(KVideo) => writing_unseen.add(id)
          "" => ()
          picture => {
            writing_pictures[id] = picture
            sent_picture_kept("upload\u{1}" + id, picture)
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
        w.state.files.set(w.state.files.get() + [Json::object(shown)])
      } else {
        w.state.quotes.set(w.state.quotes.get().map(fn(q) {
          match q {
            Object(m) if text(Some(q), "id") == quote => {
              let n = m.copy()
              n["own"] = Json::object(shown)
              Json::object(n)
            }
            _ => q
          }
        }))
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
      sent_picture_kept("upload\u{1}" + id, picture)
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
    show=fn(w) { w.state.files.set(w.state.files.get() + [Json::object(shown)]) },
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
pub let shared_into : Map[String, Array[@hostapi.Picked]] = Map([])

///|
/// The station files' picker (＋ → Station 文件) put up for draft `key` (`src` what it reads the stations by): sfdesk's
/// station_files_pick; what is ticked there comes into the draft as files_into does.
// kept across runs: what the app says once as it starts
pub let station_files_asked : Ref[(Source, String) -> Unit] = Ref(fn(_, _) {  })

///|
/// A folder to choose on a station (sfdesk drive_dialogs.mbt's picker, folder_pick_asked): its panel's `title` and what it
/// says under it (`note`, "" nothing), the `stations` it can be chosen on and the one it starts on (`station`), the
/// folder it starts in there (`at`, "" the station's home); its button's words given the name of the folder shown
/// (`action`), whether that folder is taken already (`taken`, given the station and its path: the button disabled,
/// `taken_words` its words then); what a folder chosen does (`pick`, given its station, its path, its name, and what
/// closes the picker).
pub(all) struct FolderPick {
  title : String
  note : String
  stations : Array[@sf.StationChoice]
  station : String
  at : String
  action : (String) -> String
  taken : (String, String) -> Bool
  taken_words : String
  pick : (String, String, String, () -> Unit) -> Unit
}

///|
/// The folder picker put up (`src` what it asks the stations by), a step further in from the panel that asked for it
/// as that one closes for it: sfdesk's folder_pick (浏览文件夹 of a preset's folders, sfpages presets.mbt).
// kept across runs: what the app says once as it starts
pub let folder_pick_asked : Ref[(Source, FolderPick) -> Unit] = Ref(fn(_, _) {  })

///|
/// Chat `r`'s services and jobs put up (an agent's card's jobs pressed, sfpages): the screen's (sfapp's: the desktop's
/// popover, the phone's panel).
// kept across runs: what the app says once as it starts
pub let chat_jobs_asked : Ref[(@ui.Ctx, Source, ChatRef) -> Unit] = Ref(fn(_, _, _) {  })

///|
/// A key that is the page's (Space's composer.focus) at moment `at`: the page brought over first where the tape (中屏)
/// has it behind the sidebar (sfdesk's tape_page_for_key), as the old page's own key did; nothing elsewhere.
// kept across runs: what the app says once as it starts
pub let page_for_key : Ref[(Double) -> Unit] = Ref(fn(_) {  })

///|
/// The same from what is made once (an agent's card as nodes), the window's width given (what its screen is of).
// kept across runs: what the app says once as it starts
pub let chat_jobs_open : Ref[(Source, ChatRef, Double) -> Unit] = Ref(fn(_, _, _) {  })

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
    d.state.files.set(d.state.files.get() + files)
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
  writing_unseen.remove(id)
  writing_seeds.remove(id)
  writing_act(src, w, "remove", { "id": Json::string(id) }, show=fn(w) {
    w.state.files.set(w.state.files.get().filter(fn(f) { text(Some(f), "id") != id }))
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
  writing_act(src, w, "quote", p, show=fn(w) { if ask { w.state.focus.set(id) } })
  match picture {
    Some((station, name, bytes)) => writing_add(src, w, station, name, bytes, quote=id)
    None => ()
  }
}

///|
/// Its files and its quotes' own pictures (the core's composer keeps both among its files; its message has both among
/// its own).
pub fn writing_files(w : Writing) -> Array[Json] {
  w.files.get() + w.quotes.get().filter_map(fn(q) { field(Some(q), "own") })
}

///|
/// What is said about a quote (`composer.comment`), the page's at once as the words are.
pub fn writing_comment(src : Source, w : Writing, id : String, words : String) -> Unit {
  writing_act(src, w, "comment", { "id": Json::string(id), "comment": Json::string(words) }, show=fn(w) {
    w.state.quotes.set(w.state.quotes.get().map(fn(q) {
      match q {
        Object(m) if text(Some(q), "id") == id => {
          let said = m.copy()
          said["comment"] = Json::string(words)
          Json::object(said)
        }
        _ => q
      }
    }))
  })
}

///|
/// A quote let go (`composer.unquote`), its picture with it.
pub fn writing_unquote(src : Source, w : Writing, id : String) -> Unit {
  match w.state.quotes.get().iter().find_first(fn(q) { text(Some(q), "id") == id }) {
    Some(q) => {
      let own = text(field(Some(q), "own"), "id")
      writing_pictures.remove(own)
      writing_went.remove(own)
    }
    None => ()
  }
  writing_act(src, w, "unquote", { "id": Json::string(id) }, show=fn(w) {
    w.state.quotes.set(w.state.quotes.get().filter(fn(q) { text(Some(q), "id") != id }))
    if w.state.focus.get() == id {
      w.state.focus.set("")
    }
  })
}

///|
/// A quote's comment line has the focus it asked for (`composer.focused`).
pub fn writing_focused(src : Source, w : Writing) -> Unit {
  writing_act(src, w, "focused", {}, show=fn(w) { w.state.focus.set("") })
}

///|
/// What went wrong said in the draft, or no longer (`composer.error`).
pub fn writing_error(src : Source, w : Writing, error : String) -> Unit {
  writing_act(src, w, "error", { "error": if error == "" { Json::null() } else { Json::string(error) } }, show=fn(w) {
    w.state.error.set(error)
  })
}

///|
/// A new chat being made for the message, or no longer (`composer.starting`).
pub fn writing_starting(src : Source, w : Writing, on : Bool) -> Unit {
  writing_act(src, w, "starting", { "starting": Json::boolean(on) }, show=fn(w) { w.state.starting.set(on) })
}

///|
/// What is written taken away to be sent (`composer.take`): the draft empty at once; `done` gets what the core took,
/// as it goes (its words with the links and the paths named after them, the files that are up, the quotes, those still
/// going up), sent as it says: its files as they were when it took them, not as this page last drew them. `station`:
/// the one it goes to, where a new chat's files go up now.
pub fn writing_take(src : Source, w : Writing, station? : String = "", done : (Json?) -> Unit) -> Unit {
  w.taken = Some((w.state.text.get(), w.state.quotes.get(), w.state.files.get()))
  let params : Map[String, Json] = Map([])
  if station != "" {
    params["station"] = Json::string(station)
  }
  writing_act(
    src,
    w,
    "take",
    params,
    show=fn(w) {
      w.state.text.set("")
      w.field.set("")
      w.state.quotes.set([])
      w.state.files.set([])
      w.state.focus.set("")
      w.state.error.set("")
      w.state.ready.set(false)
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
  if unless_written && (w.state.text.get().trim(chars=" \n\t").to_owned() != "" || w.state.files.get().length() > 0 || w.state.quotes.get().length() > 0) {
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
          w.state.text.set(words)
          w.field.set(words)
          w.state.quotes.set(quotes)
          w.state.files.set(files)
        }
        None => ()
      }
      w.state.error.set(error)
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
  } else if ends(".ogv") {
    "video/ogg"
  } else if ends(".3gp") {
    "video/3gpp"
  } else if ends(".3g2") {
    "video/3gpp2"
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
  draft_given(draft)
}

///|
/// Files (a 文件 row) put into a chat's message from elsewhere (the files' tab: 添加到消息, a row let go on the chat), by
/// the chat's key; taken by its composer as it is next drawn (files_taken).
pub fn files_into(chat : String, d : Dragged) -> Unit {
  files_put.push((chat, d))
  draft_given(chat)
}

///|
/// What was put into the chat `chat`'s message since it was last asked, taken; the last of what is put into that draft
/// to be taken (its composer takes the rest before), so nothing waits for it any more (drafts_given).
pub fn files_taken(chat : String) -> Array[Dragged] {
  drafts_given_read(chat)
  let out = files_put.filter(fn(x) { x.0 == chat }).map(fn(x) { x.1 })
  files_put.retain(fn(x) { x.0 != chat })
  drafts_given.remove(chat)
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
      Some(i) => station.exact_view(start=i + 1).to_owned()
      None => station
    }
  }
  paths.map(fn(p) {
    let abs = if p.path.length() > 1 && p.path.has_suffix("/") {
      p.path.exact_view(end=p.path.length() - 1).to_owned()
    } else {
      p.path
    }
    // (its folder the root it is asked from: the station's own reach any folder of it, drive.ts `anywhere`)
    let (root, name) = match abs.rev_find("/") {
      Some(0) => ("/", abs.exact_view(start=1).to_owned())
      Some(i) => (abs.exact_view(end=i).to_owned(), abs.exact_view(start=i + 1).to_owned())
      None => ("", abs)
    }
    { station, station_name, root, path: name, abs, name, size: p.size, dir: p.dir }
  })
}

///|
// kept across runs: put back by writings_reset (sfbase's reset)
let files_put : Array[(String, Dragged)] = []

///|
/// The drafts (by key) something was put into from elsewhere (files_into, quote_file_into, shared_into, marked_into,
/// followed_into) not yet taken: what takes a draft's (its composer as it is built) built again as its key comes in.
// kept across runs: emptied by writings_reset (sfbase's reset)
let drafts_given : @signals.Keyed[String] = @signals.keyed()

///|
/// Something put into the draft `key` from elsewhere: what takes it told.
pub fn draft_given(key : String) -> Unit {
  drafts_given.add(key)
}

///|
/// Whether something put into the draft `key` from elsewhere waits, read (its composer taking it).
pub fn drafts_given_read(key : String) -> Unit {
  drafts_given.has(key) |> ignore
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
pub let quoted_into : Map[String, Array[(String, String, String, Json)]] = Map([])
