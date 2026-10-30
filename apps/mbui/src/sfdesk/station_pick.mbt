// A station's files picked to go into a message (ember web/src/mobile/StationFiles.tsx, as the phone's ＋ → Station
// 文件 and a narrow chat's 文件 tab): the places (each station's home, for a member who browses every folder, and its
// folders pinned, under its name, 离线 beside it while away), a folder entered by a tap, the way back as crumbs over
// them; files ticked (and the folder shown, as a whole), then 添加: each into the chat's message as the 文件 tab's
// 添加到消息 puts it (sfbase's files_into: the composer takes it, named by its path or as a file as the chat says).
// In the ＋'s sheet (the library's panel: station_files_pick); a chat's 文件 tab picks as it does (drive_tab.mbt).

///|
/// Where the picker is (None: the places): a station's folder (`root` its place there, `path` under it), with the
/// names it shows.
pub(all) struct PickAt {
  station : String
  station_name : String
  root : String
  root_name : String
  path : String
}

///|
/// The picker: where it is, what is ticked (by station and path), in the order ticked.
priv struct StationPick {
  at : @signals.Signal[PickAt?]
  ticked : Array[Dragged]
}

///|
// kept across runs: the picker's state (station_pick_reset puts it back)
let spick : StationPick = { at: @signals.signal(None), ticked: [] }

///|
fn station_pick_reset() -> Unit {
  spick.at.set(None)
  spick.ticked.clear()
}

///|
/// ＋'s Station 文件 for draft `key` (`<station>:<chat>`, `new:<workspace>`): the picker over the chat, from the
/// places; 添加 puts what is ticked into the draft.
pub fn station_files_pick(src : Source, key : String) -> Unit {
  station_pick_reset()
  let ws = draft_workspace(key)
  @sf.panel(
    @sf.t("web-pages.chat.files"),
    fn(c, _) { station_pick(c, src, ws) },
    from=Unanchored,
    // (its title as the app's words say it as it is drawn: put up before they are given, as a screen's fixture does)
    live=fn() { (@sf.t("web-pages.chat.files"), "", "") },
    tall=station_pick_tall,
    foot=fn(c, close) {
      if @sf.button(c, @sf.t("common.cancel"), key="station-pick/cancel", tone=Ghost) {
        close()
      }
      if station_pick_add(c, key) {
        close()
      }
    },
  )
}

///|
/// The picker at `at`, `ticked` ticked (a screen's fixture).
pub fn station_pick_set(at : PickAt, ticked : Array[Dragged]) -> Unit {
  spick.at.set(Some(at))
  spick.ticked.clear()
  spick.ticked.push_iter(ticked.iter())
}

///|
/// The workspace of draft `key` (`<station>:<chat>`, its station's; `new:<workspace>`).
fn draft_workspace(key : String) -> String {
  if key.has_prefix("new:") {
    key.view(start_offset=4).to_owned()
  } else {
    workspace_of(key)
  }
}

///|
/// 添加 (添加 n 个 once something is ticked): pressed, what is ticked goes into the message of chat `key`. Whether it was.
fn station_pick_add(c : @ui.Ctx, key : String) -> Bool {
  let n = spick.ticked.length()
  let label = if n == 0 {
    @sf.t("web-mobile.files.add")
  } else {
    @sf.t("web-mobile.files.addCount", args=[("n", n.to_string())])
  }
  if @sf.button(c, label, key="station-pick/add", tone=Primary, disabled=n == 0) {
    for d in spick.ticked {
      files_into(key, d)
    }
    spick.ticked.clear()
    true
  } else {
    false
  }
}

///|
/// The picker drawn into the box it is given: the way, then the places or a folder.
fn station_pick(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  c.box(style=narrow_page, fn() {
    station_pick_way(c)
    match spick.at.get() {
      None => station_pick_places(c, src, ws)
      Some(at) => station_pick_folder(c, src, at)
    }
  })
  |> ignore
}

///|
/// The way to the folder shown: all the places, then its station's place and the folders under it; each a way back.
fn station_pick_way(c : @ui.Ctx) -> Unit {
  let steps : Array[(String, PickAt?)] = [(@sf.t("web-mobile.files.places"), None)]
  match spick.at.get() {
    Some(at) => {
      steps.push((at.station_name + " · " + at.root_name, Some({ ..at, path: "" })))
      let mut so_far = ""
      for part in at.path.split("/") {
        if part != "" {
          so_far = dv_join(so_far, part.to_owned())
          steps.push((part.to_owned(), Some({ ..at, path: so_far })))
        }
      }
    }
    None => ()
  }
  @sf.way_line(c, "station-pick/way", steps.map(fn(s) { s.0 }), narrow_way(), fn(i) { spick.at.set(steps[i].1) })
}

///|
/// Each station's places: its home (for a member who browses every folder), then its folders pinned, on a card under
/// its name (离线 beside it while away).
fn station_pick_places(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let t = @sf.theme()
  let (list, error) = dv_stations(src, ws)
  let stations = match list {
    None => {
      @sf.waiting(c, fn() { places_pick_sample(c) }, error=error.unwrap_or(""))
      return
    }
    Some(l) => l.filter(fn(s) { s.drive })
  }
  if stations.length() == 0 {
    narrow_empty(c, @sf.t("web-main.rail.filesNone"), None)
    return
  }
  // (a station's name over its places; each place: the station, where, its name, whether its home)
  let rows : Array[(DvStation, String, String, Bool)] = []
  for s in stations {
    rows.push((s, "", "", false))
    if s.anywhere && s.home != "" {
      rows.push((s, s.home, @sf.t("web-pages.drive.home"), true))
    }
    for r in s.roots {
      rows.push((s, r.path, r.name, false))
    }
  }
  @sf.rows_list(c, "station-pick/places", rows.length(), narrow_row_est, fn(i) { place_line(c, rows, i) }) |> ignore
}

///|
/// Line `i` of the places (`rows`: each a station, a place's path, its name, whether it is the home): a station's name
/// over its places, or a place on its card.
fn place_line(c : @ui.Ctx, rows : Array[(DvStation, String, String, Bool)], i : Int) -> Unit {
  let t = @sf.theme()
  let (s, path, name, home) = rows[i]
  if path == "" && name == "" {
    c.box(style=narrow_count_box, fn() {
      let words = if s.online { s.name } else { s.name + " · " + @sf.t("web-pages.stations.offline") }
      c.text(words, style=narrow_count_words) |> ignore
    })
    |> ignore
  } else {
    let first = i > 0 && rows[i - 1].1 == ""
    let last = i == rows.length() - 1 || rows[i + 1].1 == ""
    let id = c.id("station-pick/place/" + s.station + "|" + path)
    if c.clicked(id) {
      spick.at.set(Some({ station: s.station, station_name: s.name, root: path, root_name: name, path: "" }))
    }
    @sf.group_row(c, first, last, id~, fn() {
      let b = c.box(style=narrow_entry, fn() {
        @sf.icon(c, if home { "server" } else { "folder" }, size=narrow_kind_icon, color=t.p.muted) |> ignore
        c.box(style=narrow_entry_words, fn() {
          c.text(name, style=narrow_entry_name) |> ignore
          c.text(path, style=narrow_entry_meta) |> ignore
        })
        |> ignore
        @sf.icon(c, "chevron-right", size=narrow_chevron_icon, color=t.p.subtle) |> ignore
      })
      c.semantics(b, Button, id~, label=name)
    })
  }
}

///|
/// The places to come while the stations are read (the library's Waiting, in its bones): a made-up station's name
/// and its places, as place_line draws them.
fn places_pick_sample(c : @ui.Ctx) -> Unit {
  let s = @sfbase.dv_station({ "station": "sample", "name": Json::string(@sf.sample_words(4)), "online": true })
  let rows = [(s, "", "", false), (s, @sf.sample_words(12), @sf.sample_words(3), true)] +
    [(18, 5), (14, 7), (20, 4)].map(fn(n) { (s, @sf.sample_words(n.0), @sf.sample_words(n.1), false) })
  @sf.rows_room(c, fn() {
    for i in 0..<rows.length() {
      place_line(c, rows, i)
    }
  })
}

///|
/// A folder: itself to tick as a whole, then what is in it (a folder entered, a file ticked), on a card.
fn station_pick_folder(c : @ui.Ctx, src : Source, at : PickAt) -> Unit {
  let t = @sf.theme()
  let topic = @sfbase.hold(src, @sfbase.drive_scope, "drive", {
    "station": Json::string(at.station),
    "root": Json::string(at.root),
    "path": Json::string(at.path),
  })
  let entries = @sfbase.dv_entries(src, at.station, at.root, at.path).unwrap_or([])
  let shown = @sfbase.dv_shown(src, at.station, at.root, at.path, entries).unwrap_or([])
  let whole : Dragged = {
    station: at.station,
    station_name: at.station_name,
    root: at.root,
    path: at.path,
    abs: dv_absolute(at.root, at.path),
    name: if at.path == "" { at.root_name } else { dv_name(at.path) },
    size: 0.0,
    dir: true,
  }
  let ticked = fn(d : Dragged) { spick.ticked.iter().any(fn(x) { x.station == d.station && x.abs == d.abs }) }
  let toggle = fn(d : Dragged) {
    if ticked(d) {
      spick.ticked.retain(fn(x) { !(x.station == d.station && x.abs == d.abs) })
    } else {
      spick.ticked.push(d)
    }
  }
  // a row: its mark, its name and what is under it, ✓ when ticked; pressed, `press`
  let row = fn(key : String, first : Bool, last : Bool, icon : String, name : String, sub : String, on : Bool, press : () -> Unit) {
    let id = c.id("station-pick/row/" + key)
    if c.clicked(id) {
      press()
    }
    @sf.group_row(c, first, last, id~, fn() {
      let b = c.box(style=narrow_entry, fn() {
        @sf.icon(c, icon, size=narrow_kind_icon, color=t.p.muted) |> ignore
        c.box(style=narrow_entry_words, fn() {
          c.text(name, style=narrow_entry_name) |> ignore
          if sub != "" {
            c.text(sub, style=narrow_entry_meta) |> ignore
          }
        })
        |> ignore
        if on {
          @sf.icon(c, "check", size=narrow_chevron_icon, color=t.p.accent) |> ignore
        }
      })
      c.semantics(b, Button, id~, label=name, selected=on)
    })
  }
  match topic.value {
    None =>
      match topic.error {
        Some(e) => narrow_retry(c, dv_error(e), narrow_failed_words, fn() {  })
        None =>
          // (read the first time: made-up entries' rows, in their bones)
          @sf.waiting(c, fn() {
            @sf.rows_room(c, fn() {
              let names = [5, 9, 7, 12, 6]
              for i, n in names {
                row("sample/" + i.to_string(), i == 0, i == names.length() - 1, if i < 2 { "folder" } else { "file" }, @sf.sample_words(n), @sf.sample_words(if i == 0 { 14 } else { 6 }), false, fn() {  })
              }
            })
          })
      }
    Some(_) => {
      let n = shown.length() + 1
      @sf.rows_list(c, "station-pick/folder/" + at.station + "|" + at.root + "|" + at.path, n, narrow_row_est, fn(i) {
        if i == 0 {
          row("whole", true, shown.length() == 0, "folder", @sf.t("web-mobile.files.wholeFolder"), whole.abs, ticked(whole), fn() {
            toggle(whole)
          })
        } else {
          let e = shown[i - 1]
          let path = dv_join(at.path, e.name)
          let d : Dragged = {
            station: at.station,
            station_name: at.station_name,
            root: at.root,
            path,
            abs: dv_absolute(at.root, path),
            name: e.name,
            size: e.size,
            dir: e.dir,
          }
          let sub = if e.dir {
            e.time_text
          } else {
            dv_words([if e.size_text == "" { @sf.file_size(e.size) } else { e.size_text }, e.time_text], " · ")
          }
          row("e/" + e.name, false, i == n - 1, dv_kind_icon(if e.dir { "folder" } else { e.kind }), e.name, sub, !e.dir && ticked(d), fn() {
            if e.dir {
              spick.at.set(Some({ ..at, path }))
            } else {
              toggle(d)
            }
          })
        }
      })
      |> ignore
    }
  }
}

///|
/// The ＋'s sheet as tall as most of the window (StationFiles.kt: 86%).
let station_pick_tall : Double = 0.86
