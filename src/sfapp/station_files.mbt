// A station's files put into a message (ember apps/android chat/screens/StationFiles.kt, as the phone's web does it:
// web/src/mobile/StationFiles.tsx): ＋'s Station 文件 opens the places (each station's home, for a member who browses
// every folder, and its folders lent), a folder entered by a tap, the way back as crumbs; files ticked (and the folder
// shown, as a whole), then 添加. Each goes into the draft named by its path (which station has it, and where: the
// message says so in a line of its own, `common.pathOn`; nothing goes up). Not here yet: sending one as a file
// (`drive.stage`, the card's sheet and the chat's 此对话默认发送文件), and keeping them with the draft on the device.

///|
/// A file or folder of a station's in a draft, named by its path.
priv struct DraftRef {
  station : String
  station_name : String
  /// where it is on the station (absolute)
  path : String
  name : String
  dir : Bool
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
/// The words a message goes with: what was typed, then a line for each file of a station's named in it.
fn with_ref_words(words : String, key : String) -> String {
  let lines = [words]
  for r in refs_of(key) {
    lines.push(ref_words(r))
  }
  dv_words(lines, "\n")
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
}

///|
let sfs : StationFilesUi = {
  open: false,
  at: 0.0,
  closed_at: -1.0e9,
  draft: "",
  place: None,
  ticked: Map([]),
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
fn station_files_close(c : @ui.Ctx) -> Unit {
  sfs.open = false
  sfs.closed_at = c.now()
}

///|
/// The sheet over the chat (StationFiles.kt openStationFiles): 86% of the screen, the way, the places or a folder,
/// 取消 and 添加.
fn station_files_sheet(c : @ui.Ctx, src : Source, w : String, key : String) -> Unit {
  let closing = !sfs.open
  if closing && (c.now() - sfs.closed_at >= 300.0 || c.stable() || sfs.draft != key) {
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
          for _, r in sfs.ticked {
            if !have.iter().any(fn(x) { x.station == r.station && x.path == r.path }) {
              have.push(r)
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
  let whole : DraftRef = {
    station: p.station,
    station_name: p.station_name,
    path: dv_absolute(p.root, p.path),
    name: if p.path == "" { p.root_name } else { dv_name(p.path) },
    dir: true,
  }
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
      let r : DraftRef = {
        station: p.station,
        station_name: p.station_name,
        path: dv_absolute(p.root, dv_join(p.path, e.name)),
        name: e.name,
        dir: e.dir,
      }
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
/// outlined, as it stays where it is), × takes it out.
fn ref_cards(c : @ui.Ctx, key : String) -> Unit {
  let refs = refs_of(key)
  if refs.length() == 0 {
    return
  }
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=2.0, pr=2.0, pt=2.0, gap=11.0, align=AEnd, clip=true, fn() {
    for r in refs {
      let remove = c.id("composer/unref/" + r.station + "|" + r.path)
      if c.clicked(remove) {
        draft_refs[key] = refs_of(key).filter(fn(x) { !(x.station == r.station && x.path == r.path) })
      }
      c.box(
        dir=Row,
        w=Px(236.0),
        padx=10.0,
        pady=8.0,
        gap=10.0,
        radius=16.0,
        border=1.0,
        border_color=@sf.alpha(t.p.text, 0.22),
        align=ACenter,
        fn() {
          @sf.icon(c, if r.dir { "folder" } else { "read" }, size=16.0, color=t.p.muted) |> ignore
          c.box(w=Fill(1.0), fn() {
            c.text(r.name, size=15.0, color=t.p.text, wrap=false, line=20.0) |> ignore
            c.text(r.station_name + " · " + tr("web-main.file.modePath"), size=11.0, color=t.p.muted, wrap=false, line=16.0)
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
