// The wide frame's pages still in this package (the frame itself, the rail, the settings, the places and their parts
// are sfdesk's: frame.mbt, rail.mbt, settings_frame.mbt, places.mbt), given to it as it is drawn (desk_pages): the
// chat, the files', the phone's page of the rest, and what the frame asks of the app.

///|
/// Whether this frame is drawn wide (what the phone's parts read where they differ: the chat's rows' sides, the
/// composer's Enter).
let wide_on : Ref[Bool] = Ref(false)

///|
fn wide_reset() -> Unit {
  @sfdesk.side_slide_reset()
  @sfdesk.find_forget()
  find_around.val = -1.0
  wide_on.val = false
  corners_on.val = false
  recent_open.val = false
  recent_over.val = None
}

///|
/// What the wide frame (sfdesk) draws of this package's: the pages in its pane, and what it asks.
fn desk_pages() -> @sfdesk.Pages {
  {
    // the chat's page is sfdesk's (chat_page.mbt): its messages and composer this package's (wide_chat.mbt), what
    // comes and goes with a new chat (sfdesk's newchat.mbt, switch.mbt), what its side panel shows of this package's,
    // how ⌘F goes along its list, its sharing's and publishing's sheets
    chat_layers: fn(c, src, r, v, pane, composer) { chat_layers(c, src, r, v, pane, composer) },
    share: fn(c, r, thread) { open_sheet(c, XShare(r, thread)) },
    publish: fn(c, station, thread) { open_sheet(c, Publish(station, thread)) },
    // 文件: a folder under its bar, as the web's (wide_files.mbt)
    files: fn(c, src, w) { files_landing(c, src, w) },
    folder: fn(c, src, w, at) { wide_folder(c, src, w, at) },
    other: fn(c, src, w, all, invited, page) { page_view(c, src, w, all, invited, page) },
    keys: fn(c, src, w, escape) { page_keys(c, src, w, escape) },
    offered: fn(c, src) { chat_offered(c, src) },
    core: fn(src, w) { settings_core(src, w) },
    gate: fn(c, src, w) { lock_gate(c, src, w) |> ignore },
    drop: fn(c, src, key, pane) {
      drop_hint(c, pane)
      chat_drop(c, src, key, pane)
    },
    sheet: fn() { sheet_open() },
    lower: fn() { lower_sheet() },
    home: fn() { home() },
    new_workspace: fn() { open_new_workspace() },
    answer: fn(src, account, id, join, name) { respond_invitation(src, account, id, join, name) },
  }
}

///|
/// Settings from the gear (or ⌘,), and at one of its pages (快捷键 from the shortcuts' dialog): the frame's.
fn open_settings() -> Unit {
  @sfdesk.open_settings(desk_pages())
}

///|
fn open_settings_at(route : @settings.Route) -> Unit {
  @sfdesk.open_settings_at(desk_pages(), route)
}

///|
/// The system's side of still.fail (before @ui.run). The desktop's window: 1280 by 820 at first, as still.fail's
/// desktop app opens (apps/desktop main.ts), its size not kept (the desktop app keeps none either); at least 360 by
/// 560, a phone's page below the breakpoint; on macOS its title bar the app's (its buttons in its top row, as the
/// desktop app's hiddenInset: the rail's and the sidebar's tops, a phone's page under their band), on Windows the
/// system's. On a phone the app is
/// Android's whatever the phone: on iOS too its lists fling, give at their edges and show no scroll bar as Android's,
/// its fields take a tap, draw their caret and handles and pick words as Android's (@ui.feel_as).
pub fn host_setup() -> Unit {
  @hostapi.window_setup(360.0, 560.0, 1280.0, 820.0, inset=true)
  if @ui.platform() == 1 {
    @ui.feel_as(2)
  }
}

///|
/// The files' place with no folder open: the first station's start (none with a drive: the phone's page of the files).
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
/// The files' page at a folder (src/sfdesk/files.mbt), the sidebar's width off it; a station without a drive, or one
/// that pins nothing for its viewer, on the phone's page of a station's files.
fn wide_folder(c : @ui.Ctx, src : Source, w : Workspace, at : DriveAt) -> Unit {
  let stations = dv_stations(src, w.id).0.unwrap_or([])
  let st = match stations.iter().find_first(fn(x) { x.station == at.station }) {
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
  // the files picked to go up
  dv_take_picked(src, here, [])
  let room = c.width - @sfdesk.rail_w - (if @sfdesk.wide.folded { 0.0 } else { @sfdesk.wide.side_w })
  @sfdesk.files_shell(c, src, w.id, stations, here, room)
}
