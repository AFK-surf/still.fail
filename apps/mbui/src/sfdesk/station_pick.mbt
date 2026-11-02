// A station's files picked to go into a message (ember web/src/mobile/StationFiles.tsx, as the phone's ＋ → Station
// 文件 and a narrow chat's 文件 tab): each station's home and the person's favorites, under its name (离线 while away),
// a folder entered by a tap, the way back as crumbs over
// them; files ticked (and the folder shown, as a whole), then 添加: each into the chat's message as the 文件 tab's
// 添加到消息 puts it (sfbase's files_into: the composer takes it, named by its path or as a file as the chat says).
// In the ＋'s sheet (the library's panel: station_files_pick), its rows the panel's; a chat's 文件 tab picks as it
// does (drive_tab.mbt).

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
  mut at : PickAt?
  ticked : Array[Dragged]
}

///|
// kept across runs: the picker's state (station_pick_reset puts it back)
let spick : StationPick = { at: None, ticked: [] }

///|
fn station_pick_reset() -> Unit {
  spick.at = None
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
  spick.at = Some(at)
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
/// The picker, a panel's body: the way, then the places or a folder, their rows the panel's (on its ground, their
/// words on its words' line, scrolling in its list: panel_list), not a page's cards on a page's ground of its own; the
/// sheet its share wherever it is (`fills`), not taller and shorter from folder to folder.
fn station_pick(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  station_pick_way(c)
  match spick.at {
    None => station_pick_places(c, src, ws)
    Some(at) => station_pick_folder(c, src, at)
  }
}

///|
/// The way to the folder shown: all the places, then its station's place and the folders under it; each a way back.
/// Its words on the panel's words' line.
fn station_pick_way(c : @ui.Ctx) -> Unit {
  let steps : Array[(String, PickAt?)] = [(@sf.t("web-mobile.files.places"), None)]
  match spick.at {
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
  let look = { ..narrow_way(), line: @sf.panel_words_out_by(pick_crumb_in).then(pick_crumbs_row) }
  @sf.way_line(c, "station-pick/way", steps.map(fn(s) { s.0 }), look, fn(i) { spick.at = steps[i].1 })
}

///|
/// Each station's home and the same favorites offered on the files page, under its name (离线 while away).
fn station_pick_places(c : @ui.Ctx, src : Source, ws : String) -> Unit {
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
  // Each place keeps its root and relative path: old integrations may only open a configured root.
  let rows : Array[(DvStation, String, String, String, Bool)] = []
  let kept = favorites_in(src, ws, stations)
  for s in stations {
    rows.push((s, "", "", "", false))
    if s.anywhere && s.home != "" {
      rows.push((s, s.home, "", @sf.t("web-pages.drive.home"), true))
    }
    for f in kept {
      if f.station == s.station && !(s.anywhere && s.home != "" && favorite_same_path(f.root, f.path, s.home, "")) {
        let old = s.roots.iter().find_first(fn(r) { favorite_same_path(f.root, f.path, r.path, "") })
        let (root, path) = match old {
          Some(r) => (r.path, "")
          None => (f.root, f.path)
        }
        rows.push((s, root, path, f.name, false))
      }
    }
  }
  @sf.panel_list(c, "station-pick/places", rows.length(), pick_row_est, fills=true, fn(i) {
    place_line(c, rows, i)
  })
  |> ignore
}

///|
/// Line `i` of the places (`rows`: each a station, a place's path, its name, whether it is the home): a station's name
/// over its places, or a place.
fn place_line(c : @ui.Ctx, rows : Array[(DvStation, String, String, String, Bool)], i : Int) -> Unit {
  let t = @sf.theme()
  let (s, root, path, name, home) = rows[i]
  if root == "" && name == "" {
    c.box(style=@sf.panel_words_in().then(if i == 0 { pick_head_first } else { pick_head }), fn() {
      let words = if s.online { s.name } else { s.name + " · " + @sf.t("web-pages.stations.offline") }
      c.text(words, style=pick_head_words) |> ignore
    })
    |> ignore
  } else if @sf.link_row(c, "station-pick/place/" + s.station + "|" + root + "|" + path, name, note=dv_absolute(root, path), lead=fn() {
      @sf.icon(c, if home { "server" } else { "folder" }, size=pick_mark, color=t.p.muted) |> ignore
    }) {
    let root_name = if path == "" { name } else { dv_root_label(s.roots, root) }
    spick.at = Some({ station: s.station, station_name: s.name, root, root_name, path })
  }
}

///|
/// The places to come while the stations are read (the library's Waiting, in its bones): a made-up station's name
/// and its places, as place_line draws them.
fn places_pick_sample(c : @ui.Ctx) -> Unit {
  let s = @sfbase.dv_station({ "station": "sample", "name": Json::string(@sf.sample_words(4)), "online": true })
  let rows = [(s, "", "", "", false), (s, @sf.sample_words(12), "", @sf.sample_words(3), true)] +
    [(18, 5), (14, 7), (20, 4)].map(fn(n) { (s, @sf.sample_words(n.0), "", @sf.sample_words(n.1), false) })
  for i in 0..<rows.length() {
    place_line(c, rows, i)
  }
}

///|
/// A folder: itself to tick as a whole, then what is in it (a folder entered, a file ticked).
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
  // its mark
  let mark = fn(icon : String) { fn() { @sf.icon(c, icon, size=pick_mark, color=t.p.muted) |> ignore } }
  // a row ticked (✓ at its end while it is): its name and what is under it; pressed, ticked or not
  let tick_row = fn(key : String, icon : String, name : String, sub : String, d : Dragged) {
    if @sf.choice_row(c, "station-pick/row/" + key, ticked(d), name, note=sub, lead=mark(icon)) {
      toggle(d)
    }
  }
  match topic.value {
    None =>
      match topic.error {
        Some(e) => narrow_retry(c, dv_error(e), narrow_failed_words, fn() {  })
        None =>
          // (read the first time: made-up entries' rows, in their bones)
          @sf.waiting(c, fn() {
            let names = [5, 9, 7, 12, 6]
            for i, n in names {
              @sf.choice_row(c, "station-pick/sample/" + i.to_string(), false, @sf.sample_words(n), note=@sf.sample_words(
                  if i == 0 { 14 } else { 6 },
                ), lead=mark(if i < 2 { "folder" } else { "file" }))
              |> ignore
            }
          })
      }
    Some(_) =>
      @sf.panel_list(c, "station-pick/folder/" + at.station + "|" + at.root + "|" + at.path, shown.length() + 1, pick_row_est, fills=true, fn(
        i,
      ) {
        if i == 0 {
          tick_row("whole", "folder", @sf.t("web-mobile.files.wholeFolder"), whole.abs, whole)
        } else {
          let e = shown[i - 1]
          let path = dv_join(at.path, e.name)
          let icon = dv_kind_icon(if e.dir { "folder" } else { e.kind })
          if e.dir {
            // (a folder: entered)
            if @sf.link_row(c, "station-pick/row/e/" + e.name, e.name, note=e.time_text, lead=mark(icon)) {
              spick.at = Some({ ..at, path })
            }
          } else {
            let d : Dragged = {
              station: at.station,
              station_name: at.station_name,
              root: at.root,
              path,
              abs: dv_absolute(at.root, path),
              name: e.name,
              size: e.size,
              dir: false,
            }
            let sub = dv_words([if e.size_text == "" { @sf.file_size(e.size) } else { e.size_text }, e.time_text], " · ")
            tick_row("e/" + e.name, icon, e.name, sub, d)
          }
        }
      })
      |> ignore
  }
}

///|
/// A row's height before it is laid out (a title and a note under it).
let pick_row_est : Double = 60.0

///|
/// A place's or an entry's mark.
let pick_mark : Double = 20.0

///|
/// How far a crumb's words stand in from its ground (narrow_crumb: 4): its words on the panel's words' line.
let pick_crumb_in : Double = 4.0

///|
/// The way's line in the panel: its own room over and under it, its sides the panel's.
// kept across runs: a value (no field of it changes)
let pick_crumbs_row : @ui.Style = @ui.css("row pt=S0_5 pb=S1 align=ACenter")

///|
/// A station's name over its places (as a day over a machine's sessions: run_more.mbt machine_day), 14 over it but
/// the first.
// kept across runs: a value (no field of it changes)
let pick_head : @ui.Style = @ui.css("w=Full pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let pick_head_first : @ui.Style = @ui.css("w=Full pt=S1 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let pick_head_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Muted, wrap=false)

///|
/// The ＋'s sheet as tall as most of the window (StationFiles.kt: 86%).
let station_pick_tall : Double = 0.86
