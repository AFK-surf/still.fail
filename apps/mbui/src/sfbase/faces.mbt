// The faces the app is set in, as this device chose them (docs/fonts.md; the Android app's ui/Fonts.kt rememberFonts
// and FaceFiles): the prefs' `faces` say each place's (ui, text, code); one still.fail keeps is had from the core, which
// keeps its files for this app (client/core-ts/src/font-files.ts: `fonts.file`, fetched first where it has none,
// `fonts.fetch`), each unzipped here and checked by its hash (and given back unzipped: `fonts.keep`), and given to the
// host once all are here (@ui.face_add_bytes: @hostapi.face_ui, face_text, face_code). One kept here before (an earlier
// run's) the prefs say where each of its files is (`path`), and the host reads them there (@ui.face_add) the frame the
// prefs come, the first page set in it: nothing asked of the core, carried or checked again. Until then, and where none
// is chosen, the app's own stands in (code's: JetBrains Mono). The fonts page shows each face in its preview
// (`fonts.preview`: its characters alone), given to a face of its own (4 on, by its place in the list).

///|
/// What of a chosen face is here: being asked for, being fetched, its files whole (each with the weight it is for),
/// or why not.
priv enum FaceHad {
  Asking
  Fetching
  Whole(Array[(FaceFile, Int)])
  NotHad(String)
}

///|
/// A face's file as it is had: where the core keeps it (the prefs say; the host reads it there), or its bytes, unzipped
/// and checked here this run.
priv enum FaceFile {
  At(String)
  Held(Bytes)
}

///|
let faces_had : @sf.LiveMap[String, FaceHad] = @sf.LiveMap::new()

///|
/// The face each place's host face holds now, by its id ("": the app's own); index 1 ui, 2 text, 3 code.
pub let faces_in : Array[String] = ["", "", "", ""]

///|
/// A face's preview, by its id: the host face it is given to (> 0), being asked for (0), not had (-1).
let previews : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
/// The host face the app's own code face is given to for the fonts page's 默认 (code's own may be another's then).
pub let own_code_face : Int = 15

///|
/// The host face the share card is set in (share_face.mbt), whatever this device chose for its places.
pub let share_face : Int = 14

///|
/// The first host face of the previews (each face's by its place in the list, share_face - 1 the last).
pub let preview_faces_from : Int = 4

///|
fn faces_reset() -> Unit {
  faces_had.clear()
  for i in 0..<faces_in.length() {
    faces_in[i] = ""
    faces_web[i] = ("", "")
  }
  previews.clear()
  share_face_asked.val = false
}

///|
/// The app's words' own face in the wide frame (keyboard and mouse's window, as the desktop app's pages: Inter, inter_face.mbt),
/// where none is chosen: its id in `faces_in`, its file unzipped once.
pub let desktop_face : String = "\u{1}inter"

///|
/// The places' faces as a visualization's page is set in them (viz_file.mbt viz_tokens), by host face (1 ui, 2 text,
/// 3 code): each one's family as CSS has it ("": the page's own), and the stylesheet a face still.fail keeps is had
/// from there ("": none, the family the machine's or the page's).
pub let faces_web : Array[(String, String)] = [("", ""), ("", ""), ("", ""), ("", "")]

///|
/// What a face of this machine's own is said as in the prefs' `fonts` (client/core-ts/src/fonts.ts LOCAL): `local:`
/// and its family's name.
let local_face : String = "local:"

///|
/// The places' faces as the prefs say them, given to the host as each is here (call each frame, before the pages):
/// with none chosen for the app's words, the desktop app's in the wide frame (`wide`).
pub fn faces(src : Source, wide : Bool) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  guard prefs is Some(_) else { return }
  let shown = field(prefs, "faces")
  let chosen = field(prefs, "fonts")
  let wanted : Array[String] = []
  for slot, place in ["ui", "text", "code"] {
    let host_face = slot + 1
    let face = field(shown, place)
    let files = items(face, "files")
    // text not chosen: as ui (what people wrote in the app's words' face); a face of the device's own (local:<family>):
    // the host's, by its name
    let picked = text(chosen, place)
    let id = if picked.has_prefix(local_face) {
      picked
    } else if picked == "" || files.is_empty() {
      ""
    } else {
      text(face, "id")
    }
    if id != "" {
      wanted.push(id)
    }
    // the page loads a face still.fail keeps itself (its stylesheet), here or not yet; with none chosen, the app's
    // words in the wide frame are Inter, as the page's stylesheet has it from its CDN
    faces_web[host_face] = if id.has_prefix(local_face) {
      (face_css_family(id.unsafe_substring(start=local_face.length(), end=id.length())), "")
    } else if id != "" {
      (face_css_family(text(face, "family")), text(face, "css"))
    } else if host_face == @hostapi.face_ui && wide {
      ("\"Inter Variable\"", "")
    } else {
      ("", "")
    }
    // the app's words with none chosen, in the wide frame: the desktop app's face (what people wrote follows them)
    let now = if id == "" {
      if host_face == @hostapi.face_ui && wide { desktop_face } else { "" }
    } else if id.has_prefix(local_face) {
      id
    } else {
      match face_had(src, id, files) {
        Some(_) => id
        // until it is here: the app's own
        None => ""
      }
    }
    if faces_in[host_face] == now {
      continue
    }
    @ui.face_clear(host_face)
    if now == desktop_face {
      match inter_face() {
        Some(b) => ignore(@ui.face_add_bytes(host_face, b))
        None => ()
      }
    } else if now == "" {
      if host_face == @hostapi.face_code {
        ignore(@ui.face_add_bytes(host_face, @sf.code_face()))
      }
    } else if now.has_prefix(local_face) {
      // the machine's family; none of that name here (another machine's choice): the app's own
      if !@ui.face_add_family(host_face, now.unsafe_substring(start=local_face.length(), end=now.length())) &&
        host_face == @hostapi.face_code {
        ignore(@ui.face_add_bytes(host_face, @sf.code_face()))
      }
    } else {
      match faces_had.get(now) {
        Some(Whole(had)) => {
          let mut read = true
          for f in had {
            match f.0 {
              At(path) => if !@ui.face_add(host_face, path, weight=f.1) { read = false }
              Held(b) => ignore(@ui.face_add_bytes(host_face, b, weight=f.1))
            }
          }
          // a file the host could not read where it is (one kept as fetched, not unzipped yet): had through the core
          // instead, the app's own standing in until then
          if !read {
            @ui.face_clear(host_face)
            faces_had[now] = Asking
            face_files(src, now, files, 0, [], false)
            faces_in[host_face] = ""
            continue
          }
        }
        _ => ()
      }
    }
    faces_in[host_face] = now
  }
  // a face no longer chosen: let go (what failed stays said until it is chosen again)
  for id in faces_had.keys().collect() {
    if !wanted.contains(id) && faces_had.get(id) is Some(Whole(_)) {
      faces_had.remove(id)
    }
  }
}

///|
/// A family's name as CSS has it, quoted ("" none).
fn face_css_family(family : String) -> String {
  let name = family.replace_all(old="\"", new="").replace_all(old="\\", new="").replace_all(old="<", new="").replace_all(old=">", new="")
  if name == "" {
    ""
  } else {
    "\"" + name + "\""
  }
}

///|
/// Face `id`'s files when all are here; None while they come (asked for the first time it is wanted, unless the prefs
/// say where each is kept).
fn face_had(src : Source, id : String, files : Array[Json]) -> Array[(FaceFile, Int)]? {
  match faces_had.get(id) {
    Some(Whole(b)) => Some(b)
    Some(_) => None
    None if files.iter().all(fn(f) { text(Some(f), "path") != "" }) => {
      let at = files.map(fn(f) { (At(text(Some(f), "path")), number(Some(f), "weight").to_int()) })
      faces_had[id] = Whole(at)
      Some(at)
    }
    None => {
      faces_had[id] = Asking
      face_files(src, id, files, 0, [], false)
      // (all here at once where the core had them so)
      match faces_had.get(id) {
        Some(Whole(b)) => Some(b)
        _ => None
      }
    }
  }
}

///|
/// Face `id`'s files from the `at`th on, each from the core: unzipped and checked where it is as fetched; where the
/// core has one not, the face fetched first (once).
fn face_files(src : Source, id : String, files : Array[Json], at : Int, got : Array[(FaceFile, Int)], fetched : Bool) -> Unit {
  if at >= files.length() {
    faces_had[id] = Whole(got)
    return
  }
  let f = Some(files[at])
  let sha = text(f, "sha256")
  let weight = number(f, "weight").to_int()
  (src.read_bytes)("fonts.file", Json::object({ "sha256": sha.to_json() }), fn(r) {
    match r {
      Ok((v, bytes)) => {
        let whole = if flag(Some(v), "zipped") { @zip.gunzip(bytes) } else { Some(bytes) }
        match whole {
          Some(b) if @zip.sha256(b) == sha => {
            // kept unzipped from now on
            if flag(Some(v), "zipped") {
              (src.call_bytes)("fonts.keep", Json::object({ "sha256": sha.to_json() }), b, fn(_) {  })
            }
            got.push((Held(b), weight))
            face_files(src, id, files, at + 1, got, fetched)
          }
          _ => faces_had[id] = NotHad(@sf.t("android-settings.fonts.damaged"))
        }
      }
      Err(e) if text(Some(e), "code") == "not_found" && !fetched => {
        faces_had[id] = Fetching
        (src.call)("fonts.fetch", Json::object({ "id": id.to_json() }), fn(r) {
          match r {
            Ok(_) => face_files(src, id, files, 0, [], true)
            Err(e) => faces_had[id] = NotHad(text(Some(e), "message"))
          }
        })
      }
      Err(e) => faces_had[id] = NotHad(text(Some(e), "message"))
    }
  })
}

///|
/// Whether face `id` is what a place is set in now (all its files here).
pub fn face_here(id : String) -> Bool {
  id != "" && faces_in.contains(id)
}

///|
/// Why face `id` could not be had here (unzipped wrong; the core's fetch failing is the `fonts` topic's to say), "" none.
fn face_failed(id : String) -> String {
  match faces_had.get(id) {
    Some(NotHad(why)) => why
    _ => ""
  }
}

///|
/// The host face face `id` is shown in itself in on the fonts page (its preview's), at `index` in the list; 0 until it
/// is here (asked for the first time).
fn face_preview(src : Source, id : String, index : Int, variable : Bool) -> Int {
  let host_face = preview_faces_from + index
  if host_face >= share_face {
    return 0
  }
  match previews.get(id) {
    Some(f) => if f > 0 { f } else { 0 }
    None => {
      previews[id] = 0
      (src.read_bytes)("fonts.preview", Json::object({ "id": id.to_json() }), fn(r) {
        match r {
          Ok((_, bytes)) =>
            previews[id] = if @ui.face_add_bytes(host_face, bytes, weight=if variable { 0 } else { 400 }) {
              host_face
            } else {
              -1
            }
          // not shown in itself: its name in the app's face
          Err(_) => previews[id] = -1
        }
      })
      0
    }
  }
}

///|
/// Whether the share card's face was given to its host (once a run: a host that takes none is not asked again).
let share_face_asked : Ref[Bool] = Ref(false)

///|
/// The share card's face given to its host face (share_face) once, each weight's file unzipped (the card's words set in
/// it from then on; until it is, or where the host takes none, in the app's): `share_face`, to name as words' face.
pub fn share_face_given() -> Int {
  if !share_face_asked.val && !@ui.face_given(share_face) {
    // (asked again while a file is not here yet: a browser's come after the app started, share_face_js.mbt)
    let files = share_files()
    share_face_asked.val = files.iter().all(fn(f) { f.0.length() > 0 })
    if share_face_asked.val {
      for file in files {
        match @zip.gunzip(file.0) {
          Some(b) => ignore(@ui.face_add_bytes(share_face, b, weight=file.1))
          None => ()
        }
      }
    }
  }
  share_face
}

///|
/// The host face the fonts page's 默认 for code is in: the app's own code face, given to one of its own once.
fn own_code_preview() -> Int {
  if !@ui.face_given(own_code_face) {
    ignore(@ui.face_add_bytes(own_code_face, @sf.code_face()))
  }
  own_code_face
}
