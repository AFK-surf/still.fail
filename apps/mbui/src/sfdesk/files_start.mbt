// Where the files' place starts on the desktop (ember web/src/pages/Drive.tsx DriveHome, DrivePage, Roots, RootRow;
// Drive.css.ts): 文件 in the rail opens the folder in front of the tabs as they were left (else the folder last open on
// this page), else this machine's home, another station's home, an older configured root or a favorite; none, says so.
// A station without a home offers its configured folders, or says why there is none.

///|
/// The pane's width: what the frame lays its page out in (Ctx::sized: the window less the rail and the sidebar, or on
/// the tape the page's panel), the page's own `c.width` already.
fn files_room(c : @ui.Ctx) -> Double {
  c.width
}

///|
/// 文件 in the rail (DriveHome): the folder it opens at, else the page saying there is none. `room`: the pane's width.
fn files_home(c : @ui.Ctx, src : Source, w : Workspace, core : Core, room : Double) -> Unit {
  // (the tabs not known yet: as none kept, the core has them from this device at once)
  let tabs = files_tabs(src, w.id).unwrap_or(None)
  let (known, _) = drive_stations(src, w.id)
  let stations = known.unwrap_or([])
  let here = this_machine()
  let first : DriveAt? = match tabs {
    Some(t) if t.tabs.length() > 0 => Some(t.front)
    _ =>
      match last_files_page(w.id) {
        Some(at) => Some(at)
        None => {
          let mine = stations.iter().find_first(fn(s) { s.station == here && s.anywhere && s.home != "" })
          let pinned = stations.iter().find_first(fn(s) { s.roots.length() > 0 })
          let home = stations.iter().find_first(fn(s) { s.anywhere && s.home != "" })
          let saved = favorites_in(src, w.id, stations).iter().find_first(fn(f) { stations.iter().any(fn(s) { s.station == f.station && s.drive }) })
          match (mine, pinned, home, saved) {
            (Some(s), _, _, _) => Some({ station: s.station, root: Some(s.home), path: "" })
            (_, _, Some(s), _) => Some({ station: s.station, root: Some(s.home), path: "" })
            (_, Some(s), _, _) => Some({ station: s.station, root: Some(s.roots[0].path), path: "" })
            (_, _, _, Some(f)) => Some({ station: f.station, root: Some(f.root), path: f.path })
            _ => None
          }
        }
      }
  }
  match first {
    Some(at) => files_shell(c, src, w.id, stations, at, room)
    None => {
      let can = favorite_stations(src, w.id)
      desk_page(c, core, "files-home", @sf.t("web-pages.drive.title"), [
        fn() {
          if known is None {
            @sf.waiting(c, fn() { roots_sample(c) }, text=@sf.t("common.readingStations"))
          } else {
            @sf.empty(c, fn() {
              c.text(@sf.t("web-main.rail.filesNone"), style=fs_empty_words) |> ignore
              if can.length() > 0 && @sf.button(c, @sf.t("web-pages.files.addFavorite"), key="files-home/pick", tone=Primary) {
                add_favorite_folder(src, w.id, can, picked=fn(f) { files_go({ station: f.station, root: Some(f.root), path: f.path }) })
              }
            })
          }
        },
      ])
    }
  }
}

///|
/// A station's files at `at` (DrivePage), in whichever frame: a folder where there is one to show (the one asked, else
/// the home where there is one, else a configured root), else its configured folders (Roots). The
/// folder is its page (drive_page.mbt), one on every screen; what holds it by the room: wide, the files' page's tabs
/// (files.mbt), whose bar holds what can be done to it; narrow, its own bar in the frame it is given (`narrow`: back,
/// the room over and under it). `go`: a folder shown in place of this one (the side in front, by default).
pub fn files_station(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  core : Core,
  at : DriveAt,
  room : Double,
  narrow? : NarrowOf = narrow_bare(),
  go? : (DriveAt) -> Unit = files_go,
) -> Unit {
  let (known, error) = dv_stations(src, w.id)
  let stations = known.unwrap_or([])
  let st = stations.iter().find_first(fn(s) { s.station == at.station })
  let root = match (at.root, st) {
    (Some(r), _) => Some(r)
    (None, Some(s)) if s.drive && s.anywhere && s.home != "" => Some(s.home)
    (None, Some(s)) if s.drive =>
      match s.roots {
        [r] if r.state == "ok" => Some(r.path)
        _ => if s.anywhere && s.home != "" { Some(s.home) } else { None }
      }
    _ => None
  }
  let look = look_of(c)
  // (the page's arrangement said once, here, for what draws it: wide, the tabs' sides; narrow, its own frame)
  @sf.with_look(look, fn() { files_station_in(c, src, w, core, at, room, narrow, go, st, root, look, known, error, stations) })
}

///|
/// files_station's page in its arrangement.
fn files_station_in(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  core : Core,
  at : DriveAt,
  room : Double,
  narrow : NarrowOf,
  go : (DriveAt) -> Unit,
  st : DvStation?,
  root : String?,
  look : @sf.Look,
  known : Array[DvStation]?,
  error : String?,
  stations : Array[DvStation],
) -> Unit {
  match (st, root, look) {
    (Some(s), Some(r), Wide) if s.drive => {
      let (dk, _) = drive_stations(src, w.id)
      files_shell(c, src, w.id, dk.unwrap_or(stations), { station: at.station, root: Some(r), path: at.path }, room)
    }
    (Some(s), Some(r), Narrow) if s.drive => {
      let here : DriveAt = { station: at.station, root: Some(r), path: at.path }
      folder_page(
        c,
        src,
        {
          // (a place of its own for each folder's page: on a stack the one under it is drawn as this one slides in)
          key: "narrow/" + here.station + "\n" + r + "\n" + at.path,
          ws: w.id,
          st: s,
          rights: dv_rights(src, w.id, Some(s)),
          at: here,
          front: true,
          room,
          go: fn(to, _) { go(to) },
          open_in: None,
          go_to: None,
        },
        Some(narrow),
      )
    }
    // (its folders pinned: one page, laid out by its own width)
    _ => roots_page(c, src, w.id, st, known is None, error, narrow, go)
  }
}

///|
// kept across runs: a value (no field of it changes)
let fs_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)
