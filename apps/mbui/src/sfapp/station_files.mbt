// A station's files put into a message (ember apps/android chat/screens/StationFiles.kt, as the phone's web does it:
// web/src/mobile/StationFiles.tsx): ＋'s Station 文件 opens the places (each station's home, for a member who browses
// every folder, and its folders lent), a folder entered by a tap, the way back as crumbs; files ticked (and the folder
// shown, as a whole), then 添加. Each goes into the draft named by its path (which station has it, and where: the
// message says so in a line of its own, `common.pathOn`; nothing goes up), or as a file where the chat says so
// (此对话默认发送文件, the core's prefs `dropFiles` by the chat's key, else `dropAs`); its card, tapped, opens its sheet
// (发送方式: 路径 or 文件, a folder of the chat's own station as a zip; the chat's say). A file goes up as the station
// stages it (`drive.stage`) on the chat's own station, else read from the station that has it (`drive.read`) and put
// up to the chat's (`station.upload.part`, as ＋'s files go). Not here yet: keeping them with the draft on the device.

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
  mut mode : String
  /// sent as a file: it going up, then up (its `done` the attachment)
  mut up : Pending?
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
  { station, station_name, path: dv_absolute(root, at), name, dir, root, at, size, mode: "path", up: None }
}

///|
/// The station files in each draft (by its key), while the app runs.
let draft_refs : Map[String, Array[DraftRef]] = Map([])

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
    if r.mode == "path" {
      lines.push(ref_words(r))
    }
  }
  dv_words(lines, "\n")
}

///|
/// The station files sent as files that are up: their attachments.
fn ref_attachments(key : String) -> Array[Json] {
  refs_of(key).filter_map(fn(r) {
    match r.up {
      Some(p) if r.mode == "file" => p.done
      _ => None
    }
  })
}

///|
/// A station file of the draft still going up as a file.
fn refs_uploading(key : String) -> Bool {
  refs_of(key).iter().any(fn(r) {
    match r.up {
      Some(p) => r.mode == "file" && p.done is None && p.error is None
      None => r.mode == "file"
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
  match r.up {
    Some(p) if p.done is Some(_) || p.error is None => return
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
    image: "",
    width: 0,
    height: 0,
    pasted: None,
    done: None,
    sent: 0,
    error: None,
  }
  r.up = Some(p)
  let failed = fn(e : Json) {
    p.error = Some(
      match text(Some(e), "message") {
        "" => tr("android-chat.file.uploadFailed")
        m => m
      },
    )
  }
  if r.station == station {
    (src.call)(
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
            p.done = Some(a)
            p.sent = p.size
          }
          Err(e) => failed(e)
        }
      },
    )
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
          r.up = Some(p2)
          upload_part(src, d, station, p2, bytes, upload_id(src), 0)
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
    match r.up {
      Some(p) => p.id == id
      None => false
    }
  })
}

///|
/// A place of a station's drive being browsed: the station, a root, a path under it.
priv struct SfPlace {
  station : String
  station_name : String
  root : String
  root_name : String
  path : String
}

///|
/// The sheet: open (for which draft, the chat's station), where it is, what is ticked (by station and path).
priv struct StationFilesUi {
  mut open : Bool
  mut at : Double
  mut closed_at : Double
  mut draft : String
  mut place : SfPlace?
  ticked : Map[String, DraftRef]
  /// a station file's card tapped: its sheet (the draft's key, the file), open since, closed since
  mut ref : (String, DraftRef)?
  mut ref_at : Double
  mut ref_closed : Double
}

///|
let sfs : StationFilesUi = {
  open: false,
  at: 0.0,
  closed_at: -1.0e9,
  draft: "",
  place: None,
  ticked: Map([]),
  ref: None,
  ref_at: 0.0,
  ref_closed: -1.0e9,
}

///|
/// ＋'s Station 文件 tapped: the places, for the draft `key`.
fn station_files_open(c : @ui.Ctx, key : String) -> Unit {
  sfs.open = true
  sfs.at = c.now()
  sfs.draft = key
  sfs.place = None
  sfs.ticked.clear()
}

///|
/// The sheet (or a station file's card's) drawn closing this long after it was closed.
let sfs_close_ms : Double = 300.0

///|
fn station_files_close(c : @ui.Ctx) -> Unit {

  sfs.open = false
  sfs.closed_at = c.now()
}

///|
/// The sheet over the chat (StationFiles.kt openStationFiles): 86% of the screen, the way, the places or a folder,
/// 取消 and 添加.
fn station_files_sheet(c : @ui.Ctx, src : Source, w : String, key : String) -> Unit {
  let closing = !sfs.open
  if closing && (c.now() - sfs.closed_at >= sfs_close_ms || c.stable() || sfs.draft != key) {
    return
  }
  if closing {
    c.request_frame()
  }
  if sfs.draft != key {
    return
  }
  let t = @sf.theme()
  dv_sheet_frame(
    c,
    tr("web-pages.chat.files"),
    c.height * 0.86,
    closing~,
    at=if closing { sfs.closed_at } else { sfs.at },
    close=Some(fn() { station_files_close(c) }),
    fn() {
      sf_crumbs(c)
      c.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
        match sfs.place {
          None => sf_places(c, src, w)
          Some(p) => sf_folder(c, src, p)
        }
      })
      |> ignore
      let n = sfs.ticked.length()
      c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=16.0, gap=8.0, justify=JEnd, fn() {
        if dv_button(c, "sf/cancel", tr("common.cancel"), primary=false) {
          station_files_close(c)
        }
        if dv_button(
            c,
            "sf/add",
            if n == 0 {
              tr("web-mobile.files.add")
            } else {
              fill("web-mobile.files.addCount", [("n", "\{n}")])
            },
            primary=true,
            enabled=n > 0,
          ) {
          let have = refs_of(key)
          // as files where the chat says so (a folder only named); the composer puts those up (ref_send_up)
          let as_files = drops_as_files(src, key)
          for _, r in sfs.ticked {
            if !have.iter().any(fn(x) { x.station == r.station && x.path == r.path }) {
              have.push({ ..r, mode: if as_files && !r.dir { "file" } else { "path" }, up: None })
            }
          }
          draft_refs[key] = have
          station_files_close(c)
        }
      })
      |> ignore
      ignore(t)
    },
  )
}

///|
/// The way to the folder shown: all the places, then its station's place and the folders under it; each a way back.
fn sf_crumbs(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let steps : Array[(String, SfPlace?)] = [(tr("web-mobile.files.places"), None)]
  match sfs.place {
    Some(p) => {
      steps.push((p.station_name + " · " + p.root_name, Some({ ..p, path: "" })))
      let mut so_far = ""
      for part in p.path.split("/") {
        if part != "" {
          so_far = dv_join(so_far, part.to_owned())
          steps.push((part.to_owned(), Some({ ..p, path: so_far })))
        }
      }
    }
    None => ()
  }
  c.box(dir=Row, w=Fill(1.0), min_h=28.0, pl=17.0, pr=20.0, pb=8.0, align=ACenter, clip=true, fn() {
    for i, step in steps {
      let (name, to) = step
      if i > 0 {
        @sf.icon(c, "chevron-right", size=12.0, color=t.p.subtle) |> ignore
      }
      let last = i == steps.length() - 1
      let id = c.id("sf-way/\{i}")
      if !last && c.clicked(id) {
        sfs.place = to
      }
      c.box(padx=3.0, pady=3.0, radius=6.0, id=if last { 0 } else { id }, fn() {
        c.text(name, size=14.0, weight=if last { 600 } else { 400 }, color=if last { t.p.text } else { t.p.muted }, wrap=false)
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// Each station's places (StationFiles.kt Places): its home (for a member who browses every folder), then its folders
/// lent, under its name (离线 beside it while away).
fn sf_places(c : @ui.Ctx, src : Source, w : String) -> Unit {
  let t = @sf.theme()
  let (list, error) = dv_stations(src, w)
  match list {
    None => {
      waiting(c, 5, None, error)
      return
    }
    _ => ()
  }
  let stations = list.unwrap_or([]).filter(fn(s) { s.drive })
  if stations.length() == 0 {
    c.box(padx=20.0, pady=12.0, fn() {
      c.text(tr("web-main.rail.filesNone"), size=13.0, color=t.p.muted, w=Fill(1.0)) |> ignore
    })
    |> ignore
    return
  }
  let rows : Array[(DvStation, String, String, Bool)?] = []
  for s in stations {
    rows.push(Some((s, "", "", false)))
    if s.anywhere && s.home != "" {
      rows.push(Some((s, s.home, tr("web-pages.drive.home"), true)))
    }
    for r in s.roots {
      rows.push(Some((s, r.path, r.name, false)))
    }
  }
  rows.push(None)
  c.list("sf-places", rows.length(), 48.0, fn(i) {
    match rows[i] {
      None => c.box(h=Px(8.0), fn() {  }) |> ignore
      Some((s, "", _, _)) =>
        dv_section(c, s.name, trailing=if s.online { "" } else { tr("web-pages.stations.offline") })
      Some((s, path, name, home)) =>
        if dv_pick_row(c, "sf-place/" + s.station + "|" + path, name, sub=path, icon=if home { "server" } else { "folder" }) {
          sfs.place = Some({ station: s.station, station_name: s.name, root: path, root_name: name, path: "" })
        }
    }
  })
  |> ignore
}

///|
/// A folder (StationFiles.kt FolderRows): itself to tick as a whole, then what is in it (a folder entered, a file
/// ticked).
fn sf_folder(c : @ui.Ctx, src : Source, p : SfPlace) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("drive", {
    "station": Json::string(p.station),
    "root": Json::string(p.root),
    "path": Json::string(p.path),
  })
  let (sort, hidden) = dv_views(src)
  let shown = dv_arranged(items(topic.value, "entries").map(dv_entry), sort, hidden)
  let whole = draft_ref(p.station, p.station_name, p.root, p.path, if p.path == "" { p.root_name } else { dv_name(p.path) }, true)
  let tick_key = fn(r : DraftRef) { r.station + "\n" + r.path }
  let toggle = fn(r : DraftRef) {
    if sfs.ticked.contains(tick_key(r)) {
      sfs.ticked.remove(tick_key(r))
    } else {
      sfs.ticked[tick_key(r)] = r
    }
  }
  let n = if topic.value is Some(_) { shown.length() + 2 } else { 3 }
  c.list("sf-folder/" + p.station + "|" + p.root + "|" + p.path, n, 48.0, fn(i) {
    if i == 0 {
      if dv_pick_row(c, "sf-whole", tr("web-mobile.files.wholeFolder"), sub=whole.path, icon="folder", checked=sfs.ticked.contains(tick_key(whole))) {
        toggle(whole)
      }
      c.box(w=Fill(1.0), padx=20.0, pady=4.0, fn() {
        c.box(w=Fill(1.0), h=Px(1.0), bg=t.p.line, fn() {  }) |> ignore
      })
      |> ignore
    } else if i == n - 1 {
      c.box(h=Px(8.0), fn() {  }) |> ignore
    } else if topic.value is None {
      match topic.error {
        Some(e) =>
          c.box(padx=20.0, pady=12.0, fn() {
            c.text(dv_error(e), size=13.0, color=t.p.red, w=Fill(1.0)) |> ignore
          })
          |> ignore
        None => waiting(c, 5, None, None)
      }
    } else if shown.length() == 0 {
      c.box(padx=20.0, pady=12.0, fn() {
        c.text(tr("web-pages.drive.emptyFolder"), size=13.0, color=t.p.muted, w=Fill(1.0)) |> ignore
      })
      |> ignore
    } else {
      let e = shown[i - 1]
      let r = draft_ref(p.station, p.station_name, p.root, dv_join(p.path, e.name), e.name, e.dir, size=e.size)
      if e.dir {
        if dv_pick_row(c, "sf-e/" + e.name, e.name, sub=e.time_text, icon=dv_kind_icon(e.kind)) {
          sfs.place = Some({ ..p, path: dv_join(p.path, e.name) })
        }
      } else if dv_pick_row(
          c,
          "sf-e/" + e.name,
          e.name,
          sub=dv_words([if e.size_text == "" { file_size(e.size) } else { e.size_text }, e.time_text], " · "),
          icon=dv_kind_icon(e.kind),
          checked=sfs.ticked.contains(tick_key(r)),
        ) {
        toggle(r)
      }
    }
  })
  |> ignore
}

///|
/// The station files in the draft (StationFiles.kt RefCard): each its name and where it is (named by its path:
/// outlined, as it stays where it is), or how it goes up (the bubble's grey: a spinner, how far, why it failed, its
/// size); × takes it out; tapped, its sheet (ref_sheet).
fn ref_cards(c : @ui.Ctx, key : String) -> Unit {
  let refs = refs_of(key)
  if refs.length() == 0 {
    return
  }
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=2.0, pr=2.0, pt=2.0, gap=11.0, align=AEnd, clip=true, fn() {
    for r in refs {
      let remove = c.id("composer/unref/" + r.station + "|" + r.path)
      let card = c.id("composer/ref/" + r.station + "|" + r.path)
      if c.clicked(remove) {
        draft_refs[key] = refs_of(key).filter(fn(x) { !(x.station == r.station && x.path == r.path) })
      } else if c.clicked(card) {
        sfs.ref = Some((key, r))
        sfs.ref_at = c.now()
      }
      let named = r.mode == "path"
      let up = if named { None } else { r.up }
      let busy = !named &&
        (match up {
          Some(p) => p.done is None && p.error is None
          None => true
        })
      let failed = match up {
        Some(p) => p.error
        None => None
      }
      let name = if !named && r.dir { r.name + ".zip" } else { r.name }
      let note = if named {
        r.station_name + " · " + tr("web-main.file.modePath")
      } else {
        match up {
          Some(p) =>
            match (p.error, p.done) {
              (Some(e), _) => e
              (_, Some(done)) => file_size(number(Some(done), "size"))
              _ => uploading_text(p)
            }
          None => tr("common.uploading")
        }
      }
      c.box(
        dir=Row,
        w=Px(236.0),
        padx=10.0,
        pady=8.0,
        gap=10.0,
        radius=16.0,
        border=if named { 1.0 } else { 0.0 },
        border_color=@sf.alpha(t.p.text, 0.22),
        bg=if named { 0L } else { ink().neutral },
        align=ACenter,
        id=card,
        fn() {
          if busy {
            @sf.spinner(c, size=16.0) |> ignore
          } else {
            @sf.icon(c, if r.dir && named { "folder" } else { "read" }, size=16.0, color=t.p.muted) |> ignore
          }
          c.box(w=Fill(1.0), fn() {
            c.text(name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
            c.text(note, size=11.0, color=if failed is Some(_) && !named { t.p.red } else { t.p.muted }, wrap=false, line=16.0)
            |> ignore
          })
          |> ignore
          card_close(c, remove)
        },
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// A station file's card tapped (StationFiles.kt openRefSheet): its name, where it is, how it goes (发送方式: 路径, or
/// 文件 / zip: a folder only of the chat's own station), and whether this chat takes such files as files.
fn ref_sheet(c : @ui.Ctx, src : Source, key : String, station : String) -> Unit {
  let (k, r) = match sfs.ref {
    Some(x) => x
    None => return
  }
  if k != key {
    return
  }
  let closing = sfs.ref_closed > sfs.ref_at
  if closing && c.now() - sfs.ref_closed >= sfs_close_ms {
    sfs.ref = None
    return
  }
  let t = @sf.theme()
  let zips = r.dir && r.station == station
  let folder = match r.path.rev_find("/") {
    Some(i) if i > 0 => r.path.view(end_offset=i).to_owned()
    _ => r.path
  }
  let rows = if !r.dir || zips { 2 } else { 1 }
  dv_sheet_frame(
    c,
    r.name,
    dv_fit(rows) + 30.0,
    closing~,
    at=if closing { sfs.ref_closed } else { sfs.ref_at },
    close=Some(fn() { sfs.ref_closed = c.now() }),
    fn() {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=14.0, fn() {
        c.text(r.station_name + " · " + folder, size=13.0, color=t.p.muted, w=Fill(1.0)) |> ignore
      })
      |> ignore
      if !r.dir || zips {
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=14.0, gap=8.0, fn() {
          c.text(tr("web-main.file.sendAs"), size=13.0, color=t.p.muted) |> ignore
          let now = if r.mode == "path" { 0 } else { 1 }
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
            r.mode = if picked == 0 { "path" } else { "file" }
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
          c.text(tr("web-main.file.chatAsFiles"), size=14.0, weight=600, color=t.p.text, w=Fill(1.0)) |> ignore
          // the settings' switch (PageParts.kt Switch): mbui's switch's look in still.fail's colours
          @kit.switch_look_of(w=44.0, h=26.0, inset=3.0, on_color=t.p.green, off_color=t.p.line, knob=0xFFFFFFFFL, shadow=false)(
            c,
            {
              on: chat,
              t: if chat { 1.0 } else { 0.0 },
              hovered: false,
              pressed: false,
              focus_shown: false,
              disabled: false,
              rect: (0.0, 0.0, 44.0, 26.0),
            },
          )
        })
        |> ignore
      })
      |> ignore
    },
  )
}
