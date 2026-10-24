// The files' page in the wide frame: the desk's (src/sfdesk: files_nav.mbt the sidebar, files.mbt the tabs and the
// sides, drive.mbt a folder's page, files_go.mbt going somewhere), with what is still the app's given to it: the
// sidebar's band, the sheets (a folder pinned, a station's folders managed), 传输, what is dragged.

///|
/// A folder opened in the pane (the stack's page above the place, in place of what was open).
fn files_go(at : DriveAt) -> Unit {
  if ftab.building {
    ftab_go(at.station, at.root.unwrap_or(""), at.path)
    return
  }
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.push(Drive(at))
}

///|
/// The files' sidebar (src/sfdesk/files_nav.mbt), what is dragged over it moved on or let go first; Pin 文件夹 the
/// picker of the one station it can be done on, else which.
fn files_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  fdrag_frame(c, src, w)
  @sfdesk.files_nav(c, src, w.id, {
    top: @sfdesk.side_top,
    go: files_go,
    pin: fn(pins) {
      match pins {
        [s] => dv_open_picker(c, s.station, s.roots.map(fn(r) { r.path }))
        _ => dv_open(c, LendOn(pins))
      }
    },
  })
}

///|
/// The files' place with no folder open: the first station's start.
fn files_landing(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let (list, _) = dv_stations(src, w.id)
  let first = match list {
    Some(l) => l.iter().find_first(fn(s) { s.drive && @sfdesk.drive_start(s) is Some(_) })
    None => None
  }
  match first {
    Some(s) => wide_folder(c, src, w, { station: s.station, root: @sfdesk.drive_start(s), path: "" })
    None => files_page(c, src, w)
  }
}

///|
/// The files' page at a folder: the desk's shell (src/sfdesk/files.mbt), what is the app's own until it is the desk's
/// given to it (传输, the sheets, what is dragged). The folder in front is the stack's top (what the sidebar and opening
/// a folder move).
fn wide_folder(c : @ui.Ctx, src : Source, w : Workspace, at : DriveAt) -> Unit {
  let (list, _) = dv_stations(src, w.id)
  let stations = list.unwrap_or([])
  let s = stations.iter().find_first(fn(x) { x.station == at.station })
  let st = match s {
    Some(v) if v.drive => v
    _ => {
      drive_page(c, src, w, at)
      return
    }
  }
  let root = match at.root {
    Some(r) => r
    None =>
      match @sfdesk.drive_start(st) {
        Some(r) => r
        None => {
          drive_page(c, src, w, at)
          return
        }
      }
  }
  let here : DriveAt = { station: at.station, root: Some(root), path: at.path }
  dv.building = dv_page_of(Some(here))
  // what is dragged moved on or let go; the files picked to go up
  fdrag_frame(c, src, w)
  dv_take_picked(src, here, [])
  let room = c.width - @sfdesk.rail_w - (if @sfdesk.wide.folded { 0.0 } else { @sfdesk.wide.side_w })
  @sfdesk.files_shell(c, src, w.id, stations, here, room, {
    go: fn(to, _) { files_go(to) },
    transfers: fn(c) { files_transfers(c, src, w.id) },
    manage: fn(p) { dv_open(c, View(p, dv_rights(src, w.id, Some(st)).manage && p.path == "")) },
    over: fn(c, page) {
      dv_sheets(c, src, w, dv_page_of(Some(here)))
      files_clash_dialog(c)
      fdrag_ghost(c, page)
    },
  })
}

///|
/// A button of the bar that is lit while what it says is so (收藏, pin): the accent's ink then.
fn files_lit_button(c : @ui.Ctx, key : String, icon : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=files_icon_button, id~, fn() {
    @sf.icon(c, icon, size=files_icon, color=if on { t.p.accent } else { t.p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// A row's mark (16, as the web's rows) and the folder's room in from the pane's sides (32 before it, 40 after: the
/// page's, as the preview beside it ends where the head does).
let files_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let files_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// A tab's close (10).
let files_close_icon : Double = 10.0

///|
/// The line under the bar (Files.css.ts: the pane's line across it).
// kept across runs: a value (no field of it changes)
let files_bar_rule : @ui.Style = @ui.style(w=Full, h=SPx, bg=Line)

///|
/// A row (Drive.css.ts row: 36 high, 8 in, the field's corner), chosen on the selected ground.
// kept across runs: a value (no field of it changes)
let files_row_style : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=S9,
  px=S2,
  gap=S2,
  align=ACenter,
  radius=Lg,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let fgo_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let files_icon_button : @ui.Style = @ui.style(
  w=S8,
  h=S8,
  radius=Xl,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

