// A station's files put into a message (ember apps/android chat/screens/StationFiles.kt, as the phone's web does it:
// web/src/mobile/StationFiles.tsx), the draft's side: what ＋'s Station 文件 (sfdesk's station_pick.mbt, the one picker
// of every frame) put into it comes in by files_into. Each goes into the draft named by its path (which station has
// it, and where: the message says so in a line of its own, `common.pathOn`; nothing goes up), or as a file where the
// chat says so (此对话默认发送文件, the core's prefs `dropFiles` by the chat's key, else `dropAs`); its card, tapped,
// opens its sheet (发送方式: 路径 or 文件, a folder of the chat's own station as a zip; the chat's say). A file goes up
// as the station stages it (`drive.stage`) on the chat's own station, else read from the station that has it
// (`drive.read`) and put up to the chat's (`station.upload.part`, as ＋'s files go). Not here yet: keeping them with
// the draft on the device.
///|
/// A file or folder of a station's in a draft, named by its path.
priv struct DraftRef {
  station : String
  station_name : String
  /// where it is on the station (absolute)
  path : String
  name : String
  dir : Bool
  /// where it is in that station's drive (a root and the path under it), to send it as a file
  root : String
  at : String
  size : Double
  /// "path": named by its path; "file": sent (a folder as a zip)
  mode : @signals.Signal[String]
  /// sent as a file: it going up, then up (its `done` the attachment)
  up : @signals.Signal[Pending?]
  /// its place among what was put in the draft (next_pending's count, as the draft's files: one row in that order)
  order : Int
}

///|
/// A station's file named by its path where it is (`path` absolute, `root` and `at` its place in the drive).
fn draft_ref(
  station : String,
  station_name : String,
  root : String,
  at : String,
  name : String,
  dir : Bool,
  size? : Double = 0.0,
) -> DraftRef {
  let order = next_pending.val
  next_pending.val += 1
  { station, station_name, path: dv_absolute(root, at), name, dir, root, at, size, mode: @signals.signal("path", same=fn(a, b) { a == b }), up: @signals.signal(None), order }
}

///|
/// The station files in each draft (by its key), while the app runs.
let draft_refs : @sf.LiveMap[String, Array[DraftRef]] = @sf.LiveMap::new()

///|
fn refs_of(key : String) -> Array[DraftRef] {
  draft_refs.get(key).unwrap_or([])
}

///|
/// Where a file named by its path is, as the message says it (composer.ts pathWords).
fn ref_words(r : DraftRef) -> String {
  fill(if r.dir { "common.folderOn" } else { "common.pathOn" }, [("station", r.station_name), ("path", r.path)])
}

///|
/// The words a message goes with: what was typed, then a line for each file of a station's named in it (not those
/// sent as files).
fn with_ref_words(words : String, key : String) -> String {
  let lines = [words]
  for r in refs_of(key) {
    if r.mode.get() == "path" {
      lines.push(ref_words(r))
    }
  }
  dv_words(lines, "\n")
}

///|
/// The station files sent as files that are up: their attachments.
fn ref_attachments(key : String) -> Array[Json] {
  refs_of(key).filter_map(fn(r) {
    match r.up.get() {
      Some(p) if r.mode.get() == "file" => p.done.get()
      _ => None
    }
  })
}

///|
/// A station file of the draft still going up as a file.
fn refs_uploading(key : String) -> Bool {
  refs_of(key).iter().any(fn(r) {
    match r.up.get() {
      Some(p) => r.mode.get() == "file" && p.done.get() is None && p.error.get() is None
      None => r.mode.get() == "file"
    }
  })
}

///|
/// Whether the chat `key` takes a station's files as files (StationFiles.kt dropsAsFiles: the core's prefs, the chat's
/// own say in `dropFiles`, else `dropAs`).
fn drops_as_files(src : Source, key : String) -> Bool {
  let prefs = (src.topic)("prefs", {}).value
  match field(field(prefs, "dropFiles"), key) {
    Some(True) => true
    Some(False) => false
    _ => text(prefs, "dropAs") == "file"
  }
}

///|
/// The chat `key` set to take them as files or not (AppState.setDropsAsFiles: its own say dropped when it is the
/// settings' anyway).
fn set_drops_as_files(src : Source, key : String, on : Bool) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let own : Json = if on == (text(prefs, "dropAs") == "file") { Json::null() } else { Json::boolean(on) }
  let files : Map[String, Json] = Map([])
  files[key] = own
  (src.call)("prefs.set", Json::object({ "dropFiles": Json::object(files) }), fn(_) {  })
}

///|
/// A station file switched to go as a file (StationFiles.kt sendUp): staged on the chat's own station from its drive
/// (a folder zipped there: `drive.stage`), else read from the station that has it and put up to the chat's. Once up it
/// is kept, switched back or not.
fn ref_send_up(c : @ui.Ctx, src : Source, d : Draft, station : String, r : DraftRef) -> Unit {
  match r.up.get() {
    Some(p) if p.done.get() is Some(_) || p.error.get() is None => return
    _ => ()
  }
  if src.read_only {
    return
  }
  let id = next_pending.val
  next_pending.val += 1
  let name = if r.dir { r.name + ".zip" } else { r.name }
  let p : Pending = {
    id,
    name,
    size: r.size.to_int(),
    image: @signals.signal("", same=fn(a, b) { a == b }),
    width: 0,
    height: 0,
    pasted: None,
    local: None,
    done: @signals.signal(None),
    sent: @signals.signal(0),
    error: @signals.signal(None),
    core_id: @signals.signal("", same=fn(a, b) { a == b }),
    retry: @signals.signal(false, same=fn(a, b) { a == b }),
    retrying: @signals.signal(false),
    unseen: @signals.signal(None, same=fn(a, b) { a == b }),
    seed: "",
  }
  r.up.set(Some(p))
  let failed = fn(e : Json) {
    p.error.set(Some(
      match text(Some(e), "message") {
        "" => tr("android-chat.file.uploadFailed")
        m => m
      },
    ))
  }
  if r.station == station {
    // (sent once the frame's builds are over: by the file's place as it was chosen)
    c.tell("drive.stage/" + r.at, fn() { (src.call)(
      "drive.stage",
      Json::object({
        "station": Json::string(station),
        "root": Json::string(r.root),
        "path": Json::string(r.at),
        "zip": Json::boolean(r.dir),
      }),
      fn(res) {
        match res {
          Ok(a) => {
            p.done.set(Some(a))
            p.sent.set(p.size)
          }
          Err(e) => failed(e)
        }
      },
    )
    })
  } else {
    let all = Buffer()
    drive_fetch(src, r.station, r.root, r.at, fn(b) {
      all.write_bytes(b)
      true
    }, fn(err) {
      match err {
        None => {
          let bytes = all.to_bytes()
          let p2 = { ..p, size: bytes.length() }
          r.up.set(Some(p2))
          upload_part(src, d, station, p2, bytes, upload_id(d.key + "\u{1}" + d.id.get() + "\u{1}" + file_seed(station, p2.name, bytes), d.files.length()), 0)
        }
        Some(e) => failed(e)
      }
    })
  }
}

///|
/// Whether `id` is the file a station file of the draft goes up as.
fn ref_upload(key : String, id : Int) -> Bool {
  refs_of(key).iter().any(fn(r) {
    match r.up.get() {
      Some(p) => p.id == id
      None => false
    }
  })
}

///|
/// A station file's card tapped: its sheet (the draft's key, the file), closed (drawn sinking away until it has gone).
priv struct StationFilesUi {
  ref : @signals.Signal[(String, DraftRef)?]
  ref_closing : @signals.Signal[Bool]
}

///|
let sfs : StationFilesUi = { ref: @signals.signal(None), ref_closing: @signals.signal(false, same=fn(a, b) { a == b }) }

///|
/// A station file in the draft (StationFiles.kt RefCard), in the files' row (draft_files_row): its name and where it is (named by its path:
/// outlined, as it stays where it is), or how it goes up (the bubble's grey: a spinner, how far, why it failed, its
/// size); × takes it out; tapped, its sheet (ref_sheet).
fn ref_card(c : @ui.Ctx, key : String, r : DraftRef) -> Unit {
  let t = @sf.theme()
  let remove = c.id("composer/unref/" + r.station + "|" + r.path)
  let card = c.id("composer/ref/" + r.station + "|" + r.path)
  if c.clicked(remove) {
    draft_refs.set(key, refs_of(key).filter(fn(x) { !(x.station == r.station && x.path == r.path) }))
  } else if c.clicked(card) {
    sfs.ref.set(Some((key, r)))
    sfs.ref_closing.set(false)
  }
  let named = r.mode.get() == "path"
  let up = if named { None } else { r.up.get() }
  let busy = !named &&
    (match up {
      Some(p) => p.done.get() is None && p.error.get() is None
      None => true
    })
  let failed = match up {
    Some(p) => p.error.get()
    None => None
  }
  let name = if !named && r.dir { r.name + ".zip" } else { r.name }
  let note = if named {
    r.station_name + " · " + tr("web-main.file.modePath")
  } else {
    match up {
      Some(p) =>
        match (p.error.get(), p.done.get()) {
          (Some(e), _) => e
          (_, Some(done)) => @sf.file_size(number(Some(done), "size"))
          _ => uploading_text(p)
        }
      None => tr("common.uploading")
    }
  }
  // (its remove button over its corner as a picture's, their tops in line; as wide as it is, never squeezed)
  with_remove(c, remove, file_card_w, tr("web-main.file.remove", args=[("name", name)]), fn() {
    let tile = c.box(
      dir=Row,
      w=Px(file_card_w),
      padx=10.0,
      pady=8.0,
      gap=10.0,
      // (named by its path: no ground, outlined; going as the file: as every waiting card's, @sf.composer_card)
      style=if named { files_card() } else { files_card().then(@sf.composer_card()) },
      border=if named { 1.0 } else { 0.0 },
      border_color=@sf.alpha(t.p.text, 0.22),
      align=ACenter,
      id=card,
      fn() {
        if busy {
          @sf.spinner(c, size=16.0) |> ignore
        } else {
          @sf.icon(c, if r.dir && named { "folder" } else { "read" }, size=16.0, color=t.p.muted) |> ignore
        }
        c.box(w=Fill(1.0), fn() {
          c.text(name, size=t.t.ui, color=t.p.text, wrap=false, line=20.0) |> ignore
          c.text(note, size=t.t.caption, color=if failed is Some(_) && !named { t.p.red } else { t.p.muted }, wrap=false, line=16.0)
          |> ignore
        })
        |> ignore
      },
    )
    // where it is, for it to fly from when sent as a file (flight.mbt)
    @motion.measure(c, tile, "composer/tile/ref/\{r.order}")
  })
}

///|
/// A station file's card tapped (StationFiles.kt openRefSheet): its name, where it is, how it goes (发送方式: 路径, or
/// 文件 / zip: a folder only of the chat's own station), and whether this chat takes such files as files.
fn ref_sheet(c : @ui.Ctx, src : Source, key : String, station : String) -> Unit {
  let (k, r) = match sfs.ref.get() {
    Some(x) => x
    None => return
  }
  if k != key {
    return
  }
  let closing = sfs.ref_closing.get()
  let t = @sf.theme()
  let zips = r.dir && r.station == station
  let folder = match r.path.rev_find("/") {
    Some(i) if i > 0 => r.path.view(end_offset=i).to_owned()
    _ => r.path
  }
  dv_sheet_frame(
    c,
    r.name,
    // (before what it holds is first laid out: built again at once, as tall as it is)
    c.height * 0.5,
    fit=true,
    closing~,
    reader=true,
    close=fn() { sfs.ref_closing.set(true) },
    gone=fn() {
      sfs.ref.set(None)
      sfs.ref_closing.set(false)
    },
    fn() {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=14.0, fn() {
        c.text(r.station_name + " · " + folder, size=t.t.meta, color=t.p.muted, w=Fill(1.0)) |> ignore
      })
      |> ignore
      if !r.dir || zips {
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=14.0, gap=8.0, fn() {
          c.text(tr("web-main.file.sendAs"), size=t.t.meta, color=t.p.muted) |> ignore
          let now = if r.mode.get() == "path" { 0 } else { 1 }
          // the two halves of the sheet's width (Seg fill = true), inside the track's 2 each side
          let picked = @sf.segmented(
            c,
            "ref/mode",
            [
              tr("web-main.file.modePath"),
              tr(if r.dir { "web-main.file.modeZip" } else { "web-main.file.modeFile" }),
            ],
            now,
            item_w=(c.width - 44.0) / 2.0,
          )
          if picked != now {
            r.mode.set(if picked == 0 { "path" } else { "file" })
            // (the composer puts it up: ref_send_up; a pick asks for its frame)

          }
        })
        |> ignore
      }
      let chat = drops_as_files(src, key)
      let id = c.id("ref/chat-files")
      if c.clicked(id) {
        set_drops_as_files(src, key, !chat)
      }
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=14.0, fn() {
        c.box(dir=Row, w=Fill(1.0), padx=14.0, pady=10.0, gap=12.0, radius=14.0, bg=t.p.chip, align=ACenter, id~, fn() {
          c.text(tr("web-main.file.chatAsFiles"), size=t.t.ui, weight=600, color=t.p.text, w=Fill(1.0)) |> ignore
          // the settings' switch (PageParts.kt Switch)
          @settings.switch(c, "ref/chat-files", chat)
        })
        |> ignore
      })
      |> ignore
    },
  )
}

///|
/// A station's files from its 文件 tab (src/sfdesk/drive_tab.mbt: 添加到消息, or dragged onto the chat) into draft `key`, as
/// the web's droppedFrom: each named by its path, or as a file where the chat says so (a folder only named); what is
/// already in it not twice.
fn refs_put(src : Source, key : String, items : Array[Dragged]) -> Unit {
  if items.is_empty() {
    return
  }
  let have = refs_of(key)
  let as_files = drops_as_files(src, key)
  for i in items {
    if have.iter().any(fn(x) { x.station == i.station && x.path == i.abs }) {
      continue
    }
    let name = if i.station_name != "" { i.station_name } else { station_name_by(src, i.station) }
    let r = draft_ref(i.station, name, i.root, i.path, i.name, i.dir, size=i.size)
    have.push({ ..r, mode: @signals.signal(if as_files && !i.dir { "file" } else { "path" }, same=fn(a, b) { a == b }), up: @signals.signal(r.up.get()) })
  }
  draft_refs.set(key, have)
}

///|
/// A station's name by its address (`<workspace>/<station>`), as the workspace's stations say it ("" not known).
fn station_name_by(src : Source, station : String) -> String {
  let (list, _) = dv_stations(src, workspace_of(station))
  match list.unwrap_or([]).iter().find_first(fn(s) { s.station == station }) {
    Some(s) => s.name
    None => ""
  }
}

///|
/// Whether any of the workspace's stations lends its files (ChatSide.tsx useStationDrive): then a chat has its 文件 tab.
fn drive_in(src : Source, ws : String) -> Bool {
  let (list, _) = dv_stations(src, ws)
  list.unwrap_or([]).iter().any(fn(s) { s.drive })
}
