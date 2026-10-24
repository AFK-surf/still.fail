// Where the files' place starts on the desktop (ember web/src/pages/Drive.tsx DriveHome, DrivePage, Roots, RootRow;
// Drive.css.ts): 文件 in the rail opens the folder in front of the tabs as they were left (else the folder last open on
// this page), else this machine's home, else the first folder pinned on any station, else the first station's home;
// none, says so (with 选择文件夹 for one who may pin). A station's own files with no folder asked (or one without a drive,
// or one from before drives) is its list of the folders it pins, or why there is none.

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
          match (mine, pinned, home) {
            (Some(s), _, _) => Some({ station: s.station, root: Some(s.home), path: "" })
            (_, Some(s), _) => Some({ station: s.station, root: Some(s.roots[0].path), path: "" })
            (_, _, Some(s)) => Some({ station: s.station, root: Some(s.home), path: "" })
            _ => None
          }
        }
      }
  }
  match first {
    Some(at) => files_shell(c, src, w.id, stations, at, room)
    None => {
      let can = pin_stations(src, w.id)
      desk_page(c, core, "files-home", @sf.t("web-pages.drive.title"), [
        fn() {
          if known is None {
            @sf.waiting(c, count=4, text=@sf.t("common.readingStations"))
          } else {
            @sf.empty(c, fn() {
              c.text(@sf.t("web-main.rail.filesNone"), style=fs_empty_words) |> ignore
              if can.length() > 0 && @sf.button(c, @sf.t("web-pages.drive.pick"), key="files-home/pick", tone=Primary) {
                add_folder(can)
              }
            })
          }
        },
      ])
      drive_dialogs(c, src, w.id)
    }
  }
}

///|
/// A station's files at `at` (DrivePage), in whichever frame: a folder where there is one to show (the one asked, else
/// the one folder pinned, else the home for a member who browses every folder), else its folders pinned (Roots). Laid
/// out by its own width: wide, the files' page (its tabs, the folder's head, its ways); narrow, the narrow app's page
/// (drive_narrow.mbt) in the frame it is given (`narrow`: back, the room over and under it). `go`: a folder shown in
/// place of this one (the side in front, by default).
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
    (None, Some(s)) if s.drive =>
      match s.roots {
        [r] if r.state == "ok" => Some(r.path)
        _ => if s.anywhere && s.home != "" { Some(s.home) } else { None }
      }
    _ => None
  }
  let look = look_of(c)
  let manage = st is Some(s) && pin_stations(src, w.id).iter().any(fn(p) { p.station == s.station })
  match (st, root, look) {
    (Some(s), Some(r), Wide) if s.drive => {
      let (dk, _) = drive_stations(src, w.id)
      files_shell(c, src, w.id, dk.unwrap_or(stations), { station: at.station, root: Some(r), path: at.path }, room)
    }
    (Some(s), Some(r), Narrow) if s.drive => {
      let here : DriveAt = { station: at.station, root: Some(r), path: at.path }
      folder_narrow(
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
          manage: Some(fn() { manage_roots(s.station) }),
        },
        narrow,
      )
      drive_dialogs(c, src, w.id)
    }
    (_, _, Narrow) => roots_narrow(c, src, w.id, st, known is None, error, manage, narrow, go)
    _ => {
      desk_page(
        c,
        core,
        "files-roots/" + at.station,
        @sf.t("web-pages.drive.title"),
        [fn() { files_roots(c, st, known is None, error, manage) }],
        lead=match st {
          Some(s) => s.name
          None => ""
        },
      )
      drive_dialogs(c, src, w.id)
    }
  }
}

///|
/// A station's folders pinned (Roots): while read, their shapes (why not, if it failed); from before drives, says so;
/// none, says so (Pin 文件夹 for one who may); else a row each.
fn files_roots(c : @ui.Ctx, st : DvStation?, reading : Bool, error : String?, manage : Bool) -> Unit {
  match st {
    _ if reading => @sf.waiting(c, count=6, error=error.unwrap_or(""))
    None => @sf.empty(c, fn() { c.text(@sf.t("web-pages.workspace.noSuchStation"), style=fs_empty_words) |> ignore })
    Some(s) if !s.overview => @sf.waiting(c, count=6)
    Some(s) if !s.drive =>
      @sf.empty(c, fn() { c.text(@sf.t("web-pages.drive.oldStation"), style=fs_empty_words) |> ignore })
    Some(s) if s.roots.length() == 0 =>
      @sf.empty(c, fn() {
        c.text(@sf.t(if manage { "web-pages.drive.noneManage" } else { "web-pages.drive.noneMember" }), style=fs_empty_words)
        |> ignore
        if manage && @sf.button(c, @sf.t("web-pages.drive.pick"), key="files-roots/pick", tone=Primary) {
          add_folder([s])
        }
      })
    Some(s) =>
      c.box(style=fs_list, fn() {
        for r in s.roots {
          files_root_row(c, s, r)
        }
      })
      |> ignore
  }
}

///|
/// A folder pinned (RootRow): its mark, its name, what is wrong with it under it (and what to do), a chevron; pressed,
/// it opens among the tabs.
fn files_root_row(c : @ui.Ctx, s : DvStation, r : DvRoot) -> Unit {
  let t = @sf.theme()
  let id = c.id("files-root/" + s.station + "/" + r.path)
  c.cursor(id, Hand)
  if c.clicked(id) {
    c.tell("files-root", fn() { files_go({ station: s.station, root: Some(r.path), path: "" }) })
  }
  let b = c.box(style=if c.lit(id) { fs_row_hot } else { fs_row }, id~, fn() {
    @sf.icon(c, "folder", size=fs_icon, color=t.p.muted) |> ignore
    c.box(style=fs_row_words, fn() {
      c.text(r.name, style=fs_row_name) |> ignore
      match dv_trouble(r.state) {
        Some((what, hint)) =>
          c.rich([@ui.span(what, weight=600), @ui.span(" · " + hint)], style=fs_row_trouble) |> ignore
        None => ()
      }
    })
    |> ignore
    @sf.icon(c, "chevron-right", size=fs_chevron, color=t.p.muted) |> ignore
  })
  c.semantics(b, Button, id~, label=r.name)
  @sf.tip(c, "files-root-tip/" + r.path, id, r.path)
}

///|
// kept across runs: a value (no field of it changes)
let fs_empty_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true)

///|
/// The folders pinned (Drive.css.ts list, row): a row each, 10 by 12 in, its mark 12 before its name, its ground under
/// the pointer.
// kept across runs: a value (no field of it changes)
let fs_list : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let fs_row : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S3 radius=Lg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let fs_row_hot : @ui.Style = fs_row.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let fs_row_words : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let fs_row_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let fs_row_trouble : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger)

///|
let fs_icon : Double = 20.0

///|
let fs_chevron : Double = 16.0
