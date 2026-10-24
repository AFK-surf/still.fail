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
    other: fn(c, src, w, all, invited, page) { page_view(c, src, w, all, invited, page) },
    core: fn(src, w) { settings_core(src, w) },
    sheet: fn() { sheet_open() },
    lower: fn() {
      lower_sheet()
      dui.sheet = None
      dui.leaving = None
    },
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
