// The wide frame's pages still in this package (the frame itself, the rail and their parts are sfdesk's: frame.mbt,
// rail.mbt), given to it as it is drawn (desk_pages): the chat, a settings page, a place's, the files', the phone's page
// of the rest, the sidebars of the places other than the chats' (wide_place_side.mbt), and what the frame asks
// of the app.

///|
/// What the wide frame's pages still here keep of their own (the frame's own is sfdesk's `shell`; the rest is the
/// stack's and the core's).
priv struct Wide {
  /// 快捷键一览 (⌘/) open
  mut keys_open : Bool
  /// the chat's "…" open (what is done with it), its services' popover open
  mut info_open : Bool
  mut jobs_open : Bool
  /// the job picked in the 任务 tab ("" the first)
  mut job_picked : String
  /// ⌘F's bar (wide_find.mbt): the chat it is open in ("" closed), its field, what is typed, what the core found
  /// (None nothing asked yet), the time the reader is at (which of its messages, which time in it), whether what is
  /// not on the device is being read, the message the chat's window was last moved about for it
  mut find_chat : String
  find_field : @ui.Field
  mut find_query : String
  mut found : Found?
  mut find_at : Int
  mut find_k : Int
  mut bringing : Bool
  mut find_around : Double
  /// a model control's panel open (model_triple.mbt): its station and pick ("" none), its accounts' panel beside it,
  /// its filter's field and words; the borrowing it asks to confirm ("" none)
  mut triple : String
  mut triple_accounts : Bool
  triple_field : @ui.Field
  mut triple_query : String
  mut borrow_asking : String
  /// an agent's history in the side panel (wide_history.mbt): 只看收发, its details folded; where its runtime keeps
  /// each session's transcript (by station and session; "" none), asked once; its context's 管理 menu open, clearing
  /// it asked to confirm (its session's key, "" none)
  mut history_io : Bool
  mut history_shut : Bool
  transcripts : Map[String, String]
  mut context_menu : String
  mut clear_asking : String
  /// the new chat's station chooser open (wide_newchat.mbt)
  mut station_menu : Bool
  /// the page picked in a place with a list of its own (Station's, Profile's: wide_places.mbt), by place
  place_pick : Map[String, @settings.Route]
  /// 待处理's panel: what was let go in it (忽略, `decision.dismiss`) until the core no longer lists it, by station and
  /// chat; the stations' trouble as looked at when it opened, as it shows it while open (None: closed)
  gone : Array[String]
  mut trouble_seen : String?
}

///|
let wide : Wide = {
  keys_open: false,
  info_open: false,
  jobs_open: false,
  job_picked: "",
  find_chat: "",
  find_field: @ui.Field::new(),
  find_query: "",
  found: None,
  find_at: -1,
  find_k: 0,
  bringing: false,
  find_around: -1.0,
  triple: "",
  triple_accounts: false,
  triple_field: @ui.Field::new(),
  triple_query: "",
  borrow_asking: "",
  history_io: false,
  history_shut: false,
  transcripts: {},
  context_menu: "",
  clear_asking: "",
  station_menu: false,
  place_pick: {},
  gone: [],
  trouble_seen: None,
}

///|
/// Whether this frame is drawn wide (what the phone's parts read where they differ: the chat's rows' sides, the
/// composer's Enter).
let wide_on : Ref[Bool] = Ref(false)

///|
fn wide_reset() -> Unit {
  wide.keys_open = false
  wide.info_open = false
  wide.jobs_open = false
  wide.job_picked = ""
  side_slide_reset()
  find_forget()
  wide.triple = ""
  wide.triple_accounts = false
  wide.triple_field.set("")
  wide.triple_query = ""
  wide.borrow_asking = ""
  wide.history_io = false
  wide.history_shut = false
  wide.transcripts.clear()
  wide.context_menu = ""
  wide.clear_asking = ""
  wide.station_menu = false
  wide.place_pick.clear()
  wide_switch_reset()
  wide.gone.clear()
  wide.trouble_seen = None
  wide_on.val = false
  corners_on.val = false
  recent_open.val = false
  recent_over.val = None
}

///|
/// What the wide frame (sfdesk) draws of this package's: the pages in its pane, the sidebars, and what it asks.
fn desk_pages() -> @sfdesk.Pages {
  {
    chat: fn(c, src, w, r) {
      wide_chat_page(c, src, w, r)
      new_chat_leaving_wide(c, src, w, r)
      // (come to from a new chat by the sidebar: the new chat fading over it)
      switch_new_out(c, src, w)
    },
    setting: fn(c, src, w, r) { setting_page(c, src, w, r) },
    // Station and Profile a list of their own beside their page (wide_places.mbt); the others under their title
    place: fn(c, src, w, p) {
      match p {
        "stations" | "profiles" => place_page_wide(c, src, w, p)
        _ => wide_place(c, src, w, p)
      }
    },
    // 文件: a folder under its bar, as the web's (wide_files.mbt)
    files: fn(c, src, w) { files_landing(c, src, w) },
    folder: fn(c, src, w, at) { wide_folder(c, src, w, at) },
    other: fn(c, src, w, all, invited, page) { page_view(c, src, w, all, invited, page) },
    // the settings', the files', the stations', the profiles' (wide_place_side.mbt)
    side: fn(c, src, w, width) { sidebar(c, src, w, width) },
    rename: fn(c, src, item) { side_rename(c, src, item) },
    jobs: fn(c, src, w) { open_jobs(c, src, w) },
    act: fn(src, what, call, params, done) { act(src, what, "", call, params, done~) },
    gated: fn(src, w) { @settings.lock_waiting(settings_core(src, w), w.id) },
    gate: fn(c, src, w) { lock_gate(c, src, w) |> ignore },
    switching: fn(c) { wide_switch_frame(c) },
    updating: fn() { side_update_shown() },
    update: fn(c, src, bar, s, inset) { side_update(c, src, bar, s, inset) },
    bell: fn(src, w) { bell_lit(src, w) },
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
/// Whether the desktop app has a newer build to offer, or one on its way in (brand.tsx UpdateButton: the app's update
/// state, none while there is none).
fn side_update_shown() -> Bool {
  update.available is Some(_) || update_busy() || update.phase == "failed"
}

///|
/// The desktop app's newer build (brand.tsx UpdateButton, brand.css.ts sidebarUpdate): 更新 at the open sidebar's top
/// right, 12 in from its edge, or past the rail (and the window's buttons) when it is closed, moved with it; how far it
/// has downloaded, 正在重启 while it is put in place, 更新失败，重试 when it failed (why, its tip). Pressed, the build is
/// downloaded and the app restarts as it.
fn side_update(c : @ui.Ctx, src : Source, bar : Bool, s : Double, inset : Bool) -> Unit {
  // (its phase as the host says it, what went wrong said once: updates.mbt)
  update_progress() |> ignore
  let v = try Some(@json.parse(@ui.update_state())) catch { _ => None }
  let busy = update_busy()
  let label = match update.phase {
    "downloading" | "retrying" =>
      fill("web-main.appUpdate.downloading", [("percent", dmax(0.0, number(v, "percent")).to_int().to_string())])
    "installing" => tr("web-main.appUpdate.restarting")
    "failed" => tr("web-main.appUpdate.failed")
    _ => tr("web-main.versions.update")
  }
  let tip = if update.phase == "failed" {
    update_error(text(v, "error"))
  } else {
    fill("web-main.appUpdate.title", [("version", text(update.available, "versionName")), ("app", "still.fail")])
  }
  let id = c.id("side/update")
  // open, its end 12 in from the sidebar's (translateX(-100%)); closed, its start past the rail and the window's buttons
  let width = match c.laid_size(id) {
    Some((w, _)) => w
    None => 0.0
  }
  let (left, tx) = if bar {
    (if inset { update_closed_inset } else { update_closed_in }, 0.0)
  } else {
    (@sfdesk.rail_w + s - @sfdesk.bar_in, -width)
  }
  c.cursor(id, Hand)
  c.layer(fn() {
    let b = c.box(style=update_at, moves="side-update", left~, top=update_top, tx~, id~, fn() {
      @sf.pill(c, label, tone=Accented)
    })
    c.semantics(b, Button, id~, label~)
  })
  |> ignore
  @sf.tip(c, "side/update-tip", id, tip, side=Bottom)
  if c.clicked(id) && !busy {
    update_install(src)
  }
}

///|
/// Where 更新 is (brand.css.ts sidebarUpdate): 11 down in the desktop app; closed, 68 from the window's edge (80 with
/// the window's buttons in the app's top row); the page bars' start clear of it then (72, 84).
let update_top : Double = 11.0

///|
let update_closed_in : Double = 68.0

///|
let update_closed_inset : Double = 80.0

///|
let bar_update_in : Double = 72.0

///|
let bar_update_inset : Double = 84.0

///|
/// 更新's box: its pill's size.
// kept across runs: a value (no field of it changes)
let update_at : @ui.Style = @ui.style(row=true)

///|
/// A place of the rail's (Station, Profile, 连接, 用量) in the pane: its title as a page's head (pages.css.ts), what
/// the settings' page of it shows under it.
fn wide_place(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  let t = @sf.theme()
  let side = dmax(24.0, (c.width - 792.0) / 2.0) + 16.0
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    let head = c.id("place-head")
    if @ui.window_inset() {
      c.window_drag(head)
    }
    // (a place across the pane has its page's own head, its title and what it does: settings' place_page)
    if !@sfdesk.place_bare(place) {
      c.box(w=Fill(1.0), pl=side, pr=side, pt=40.0, pb=12.0, id=head, fn() {
        c.text(place_label(place), size=22.0, weight=600, color=t.p.text, wrap=false, line=34.0) |> ignore
      })
      |> ignore
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      match @settings.route_of(place) {
        Some(r) => {
          let core = settings_core(src, w)
          @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
        }
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
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
