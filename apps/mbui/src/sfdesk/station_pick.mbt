// A station's files picked to go into a message (still.fail web/src/mobile/StationFiles.tsx, as the phone's ＋ → Station
// 文件 and a narrow chat's 文件 tab): each station's home and the person's favorites, under its name (离线 while away),
// a folder entered by a tap, the way back as crumbs over
// them; files ticked (and the folder shown, as a whole), then 添加: each into the chat's message as the 文件 tab's
// 添加到消息 puts it (sfbase's files_into: the composer takes it, named by its path or as a file as the chat says).
// In the ＋'s sheet (the library's panel: station_files_pick), its rows the panel's, nodes of the window's tree made once
// as it opens (@sf.panel_nodes); a chat's 文件 tab picks as it does (drive_tab.mbt).

///|
/// Where the picker is (None: the places): a station's folder (`root` its place there, `path` under it), with the
/// names it shows.
#derive(Eq)
pub(all) struct PickAt {
  station : String
  station_name : String
  root : String
  root_name : String
  path : String
}

///|
/// The picker: where it is, what is ticked (by station and path), in the order ticked. Signals: what its body and its
/// foot are made of is bound to them.
priv struct StationPick {
  at : @signals.Signal[PickAt?]
  ticked : @signals.Signal[Array[Dragged]]
}

///|
// kept across runs: the picker's state (station_pick_reset puts it back)
let spick : StationPick = { at: @signals.signal(None), ticked: @signals.signal([]) }

///|
fn station_pick_reset() -> Unit {
  spick.at.set(None)
  spick.ticked.set([])
}

///|
/// ＋'s Station 文件 for draft `key` (`<station>:<chat>`, `new:<workspace>`): the picker over the chat, from the
/// places; 添加 puts what is ticked into the draft. What it holds and its buttons are nodes of the window's tree, made
/// once as it opens (@sf.panel_nodes).
pub fn station_files_pick(src : Source, key : String) -> Unit {
  station_pick_reset()
  let ws = draft_workspace(key)
  @sf.panel_nodes(
    @sf.t("web-pages.chat.files"),
    fn(v, _) { station_pick(v, src, ws) },
    from=Unanchored,
    // (its title as the app's words say it as it is drawn: put up before they are given, as a screen's fixture does)
    live=fn() { (@sf.t("web-pages.chat.files"), "", "") },
    tall=station_pick_tall,
    foot=fn(v, close) {
      @sf.button_node(v, fn() { @sf.t("common.cancel") }, fn() { close() }, tone=Ghost) |> ignore
      station_pick_add(v, key, then=close)
    },
  )
}

///|
/// The picker at `at`, `ticked` ticked (a screen's fixture).
pub fn station_pick_set(at : PickAt, ticked : Array[Dragged]) -> Unit {
  spick.at.set(Some(at))
  spick.ticked.set(ticked.copy())
}

///|
/// The workspace of draft `key` (`<station>:<chat>`, its station's; `new:<workspace>`).
fn draft_workspace(key : String) -> String {
  if key.has_prefix("new:") {
    key.exact_view(start=4).to_owned()
  } else {
    workspace_of(key)
  }
}

///|
/// 添加 (添加 n 个 once something is ticked), in node `v` (the panel's foot's): pressed, what is ticked goes into the
/// message of chat `key`, then `then` (what closes it).
fn station_pick_add(v : @view.View, key : String, then~ : () -> Unit) -> Unit {
  let n = fn() { spick.ticked.get().length() }
  @sf.button_node(
    v,
    fn() {
      if n() == 0 {
        @sf.t("web-mobile.files.add")
      } else {
        @sf.t("web-mobile.files.addCount", args=[("n", n().to_string())])
      }
    },
    fn() {
      for d in spick.ticked.get() {
        files_into(key, d)
      }
      spick.ticked.set([])
      then()
    },
    tone=Primary,
    disabled=fn() { n() == 0 },
  )
  |> ignore
}

///|
/// The picker, a panel's body in node `v`: the way, then the places or a folder, their rows the panel's (on its ground,
/// their words on its words' line, scrolling in its list: panel_list_node), not a page's cards on a page's ground of its
/// own; the sheet its share wherever it is (`fills`), not taller and shorter from folder to folder.
fn station_pick(v : @view.View, src : Source, ws : String) -> Unit {
  station_pick_way(v)
  v.box(fn(main) {
    main.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    main.pick(fn() { spick.at.get() }, fn(b, at) {
      b.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      match at {
        None => station_pick_places(b, src, ws)
        Some(at) => station_pick_folder(b, src, at)
      }
    })
  })
  |> ignore
}

///|
/// The way to the folder shown: all the places, then its station's place and the folders under it; each a way back.
fn pick_steps() -> Array[(String, PickAt?)] {
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
  steps
}

///|
/// The way to the folder shown in node `v` (pick_steps), its words on the panel's words' line.
fn station_pick_way(v : @view.View) -> Unit {
  let line = @sf.panel_words_out_by_node(v, pick_crumb_in).then(pick_crumbs_row)
  @sf.way_line_node(v, fn() { pick_steps().map(fn(s) { s.0 }) }, fn() { { ..narrow_way(), line: line } }, fn(i) {
    let steps = @signals.untracked(pick_steps)
    if i < steps.length() {
      spick.at.set(steps[i].1)
    }
  })
  |> ignore
}

///|
/// What the places show: the stations read the first time (or failing to be), none lending a folder, or their places.
#derive(Eq)
priv enum PlacesShow {
  PlacesReading
  PlacesNone
  PlacesListed
}

///|
/// The stations lending folders in workspace `ws` (None while they are read the first time), and why they could not be
/// read.
fn pick_stations(src : Source, ws : String) -> (Array[DvStation]?, String?) {
  let (list, error) = dv_stations(src, ws)
  (list.map(fn(l) { l.filter(fn(s) { s.drive }) }), error)
}

///|
/// Each station's home and the same favorites offered on the files page, under its name (离线 while away).
fn place_lines(src : Source, ws : String, stations : Array[DvStation]) -> Array[(DvStation, String, String, String, Bool)] {
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
  rows
}

///|
/// A line of the places (a station, a place's root and path under it, its name, whether it is the home; a station's
/// name over its places where its root and name are ""): its key in their list, a station's name by its station, a
/// place by its station, root and path.
fn pick_place_key(l : (DvStation, String, String, String, Bool)) -> String {
  let (s, root, path, name, _) = l
  if root == "" && name == "" {
    "h|" + s.station
  } else {
    "p|" + s.station + "|" + root + "|" + path
  }
}

///|
/// The places in node `v`: each station's home and its favorites under its name; while the stations are read the
/// first time, places to come in their bones (why they could not be read over them); nothing here where none lends a
/// folder.
fn station_pick_places(v : @view.View, src : Source, ws : String) -> Unit {
  v.pick(
    fn() {
      match pick_stations(src, ws).0 {
        None => PlacesReading
        Some(l) => if l.length() == 0 { PlacesNone } else { PlacesListed }
      }
    },
    fn(b, shows) {
      match shows {
        PlacesReading =>
          @sf.waiting_node(b, fn(w) { places_pick_sample(w) }, error=fn() { pick_stations(src, ws).1.unwrap_or("") })
        PlacesNone => narrow_empty_node(b, fn() { @sf.t("web-main.rail.filesNone") }, None)
        PlacesListed => {
          let lines = fn() { place_lines(src, ws, pick_stations(src, ws).0.unwrap_or([])) }
          @sf.panel_list_node(
            b,
            fn() { lines().map(pick_place_key) },
            fn(r, k) {
              // (what the line is as it is now, the one it was made for kept where it has gone: it goes with it)
              let made = @signals.untracked(lines)
              let first = made.length() > 0 && pick_place_key(made[0]) == k
              guard made.iter().find_first(fn(l) { pick_place_key(l) == k }) is Some(was) else { return }
              let line = fn() { lines().iter().find_first(fn(l) { pick_place_key(l) == k }).unwrap_or(was) }
              place_line(r, first, line)
            },
            est=pick_row_est,
            fills=true,
          )
          |> ignore
        }
      }
    },
  )
}

///|
/// Line `line` of the places in node `v` (`first`, the first of them): a station's name over its places (离线 while
/// away), or a place.
fn place_line(v : @view.View, first : Bool, line : () -> (DvStation, String, String, String, Bool)) -> Unit {
  let (_, root, _, name, home) = @signals.untracked(line)
  if root == "" && name == "" {
    let words_in = @sf.panel_words_in_node(v)
    v.box(fn(h) {
      @sf.style_node(h, fn() { words_in.then(if first { pick_head_first } else { pick_head }) })
      @sf.words_node(
        h,
        fn() {
          let s = line().0
          if s.online {
            s.name
          } else {
            s.name + " · " + @sf.t("web-pages.stations.offline")
          }
        },
        fn() { pick_head_words },
      )
      |> ignore
    })
    |> ignore
  } else {
    @sf.link_row_node(
      v,
      fn() { line().3 },
      fn() {
        let (s, root, path, name, _) = line()
        let root_name = if path == "" { name } else { dv_root_label(s.roots, root) }
        spick.at.set(Some({ station: s.station, station_name: s.name, root, root_name, path }))
      },
      note=fn() {
        let l = line()
        dv_absolute(l.1, l.2)
      },
      lead=@sf.LeadLine(fn(l) { pick_mark_node(l, fn() { if home { "server" } else { "folder" } }) }),
    )
  }
}

///|
/// A place's or an entry's mark (`icon`), in node `v`.
fn pick_mark_node(v : @view.View, icon : () -> String) -> Unit {
  @sf.icon_node(v, "", pick_mark, By(fn() { @sf.theme().p.muted }), name_now=icon) |> ignore
}

///|
/// The places to come while the stations are read (the library's Waiting, in its bones), in node `v`: a made-up
/// station's name and its places, as place_line draws them.
fn places_pick_sample(v : @view.View) -> Unit {
  let s = @sfbase.dv_station({ "station": "sample", "name": Json::string(@sf.sample_words(4)), "online": true })
  let rows : Array[(DvStation, String, String, String, Bool)] = [(s, "", "", "", false), (s, @sf.sample_words(12), "", @sf.sample_words(3), true)] +
    [(18, 5), (14, 7), (20, 4)].map(fn(n) { (s, @sf.sample_words(n.0), "", @sf.sample_words(n.1), false) })
  for i, l in rows {
    place_line(v, i == 0, fn() { l })
  }
}

///|
/// What a folder shows: read the first time, failing to be read, or what is in it.
#derive(Eq)
priv enum FolderShows {
  FolderReading
  FolderFailed
  FolderRead
}

///|
/// A folder in node `v`: itself to tick as a whole, then what is in it (a folder entered, a file ticked).
fn station_pick_folder(v : @view.View, src : Source, at : PickAt) -> Unit {
  let topic = @sfbase.hold(src, @sfbase.drive_scope, "drive", {
    "station": Json::string(at.station),
    "root": Json::string(at.root),
    "path": Json::string(at.path),
  })
  let shown = fn() {
    let entries = @sfbase.dv_entries(src, at.station, at.root, at.path).unwrap_or([])
    @sfbase.dv_shown(src, at.station, at.root, at.path, entries).unwrap_or([])
  }
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
  let ticked = fn(d : Dragged) { spick.ticked.get().iter().any(fn(x) { x.station == d.station && x.abs == d.abs }) }
  let toggle = fn(d : Dragged) {
    if ticked(d) {
      spick.ticked.set(spick.ticked.get().filter(fn(x) { !(x.station == d.station && x.abs == d.abs) }))
    } else {
      spick.ticked.set([..spick.ticked.get(), d])
    }
  }
  // its mark
  let mark = fn(icon : () -> String) { fn(l : @view.View) { pick_mark_node(l, icon) } }
  // a row ticked (✓ at its end while it is): its name and what is under it; pressed, ticked or not
  let tick_row = fn(r : @view.View, icon : () -> String, name : () -> String, sub : () -> String, d : () -> Dragged) {
    @sf.choice_row_node(r, name, fn() { ticked(d()) }, press=fn() { toggle(d()) }, note=sub, lead=mark(icon))
  }
  v.pick(
    fn() {
      let t = topic.get().snapshot()
      // (what is in it asked of the core as the folder is, from the first: not once the folder has come, as an old
      // body read both each frame)
      shown() |> ignore
      match (t.value, t.error) {
        (Some(_), _) => FolderRead
        (None, Some(_)) => FolderFailed
        (None, None) => FolderReading
      }
    },
    fn(b, shows) {
      match shows {
        // (重试: the folder read again as the files' page's 重试 reads it, the same topic said anew; meanwhile why and
        // 重试 stay, as there)
        FolderFailed =>
          narrow_retry_node(
            b,
            fn() {
              match topic.get().snapshot().error {
                Some(e) => dv_error(e)
                None => ""
              }
            },
            narrow_failed_words,
            fn() { refresh_folder(src, { station: at.station, root: Some(at.root), path: at.path }) },
          )
        // (read the first time: made-up entries' rows, in their bones)
        FolderReading =>
          @sf.waiting_node(b, fn(w) {
            let names = [5, 9, 7, 12, 6]
            for i, n in names {
              let (label, note) = (@sf.sample_words(n), @sf.sample_words(if i == 0 { 14 } else { 6 }))
              @sf.choice_row_node(w, fn() { label }, fn() { false }, note=fn() { note }, lead=mark(fn() {
                if i < 2 {
                  "folder"
                } else {
                  "file"
                }
              }))
            }
          })
        FolderRead =>
          @sf.panel_list_node(
            b,
            fn() { [""] + shown().map(fn(e) { e.name }) },
            fn(r, k) {
              if k == "" {
                tick_row(r, fn() { "folder" }, fn() { @sf.t("web-mobile.files.wholeFolder") }, fn() { whole.abs }, fn() {
                  whole
                })
                return
              }
              // (the entry as it is now, the one it was made for kept where it has gone: it goes with it)
              guard @signals.untracked(shown).iter().find_first(fn(e) { e.name == k }) is Some(was) else { return }
              let e = fn() { shown().iter().find_first(fn(e) { e.name == k }).unwrap_or(was) }
              let path = dv_join(at.path, k)
              let icon = fn() {
                let e = e()
                dv_kind_icon(if e.dir { "folder" } else { e.kind })
              }
              if was.dir {
                // (a folder: entered)
                @sf.link_row_node(r, fn() { k }, fn() { spick.at.set(Some({ ..at, path: path })) }, note=fn() { e().time_text }, lead=@sf.LeadLine(
                  mark(icon),
                ))
              } else {
                let d = fn() -> Dragged {
                  let e = e()
                  {
                    station: at.station,
                    station_name: at.station_name,
                    root: at.root,
                    path,
                    abs: dv_absolute(at.root, path),
                    name: e.name,
                    size: e.size,
                    dir: false,
                  }
                }
                let sub = fn() {
                  let e = e()
                  dv_words([if e.size_text == "" { @sf.file_size(e.size) } else { e.size_text }, e.time_text], " · ")
                }
                tick_row(r, icon, fn() { k }, sub, d)
              }
            },
            est=pick_row_est,
            fills=true,
          )
          |> ignore
      }
    },
  )
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
/// The way's line in the panel: its own room over and under it, its sides the panel's. Under it, room enough for a
/// finger's press on a step (26 tall: 9 over and under it, the first row's room as far again: rooms.mbt) before the list.
// kept across runs: a value (no field of it changes)
let pick_crumbs_row : @ui.Style = @ui.css("row pt=S0_5 pb=S0_5 align=ACenter")

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
/// The ＋'s sheet as tall as most of the window.
let station_pick_tall : Double = 0.86
