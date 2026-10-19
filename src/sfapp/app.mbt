// still.fail, as its Android app is (ember apps/android app/App.kt): signed out it is the sign-in page; signed in,
// the chats of one workspace are home (Home.kt), and everything else a page pushed over it (@ui.Nav: sliding in,
// swiped back from the left edge; a new chat rising from the bottom), or a sheet from the bottom (sheet.mbt). The
// places of the bottom bar (bar.mbt) are the pages at the stack's root, switched in place.

///|
/// A page of the stack.
pub(all) enum Page {
  Home
  /// a chat (chat.mbt)
  Chat(ChatRef)
  /// the archived chats (from the filter's menu)
  Archived
  /// settings (the gear)
  Settings
  /// 文件: every station's folders lent (drive.mbt)
  Files
  /// a page of a station's drive: its roots, or a folder (drive.mbt)
  Drive(DriveAt)
  /// a text of a drive, read (drive_reader.mbt)
  DriveRead(DriveAt)
  /// the decisions waiting for the viewer, one at a time (奏: decisions.mbt); the bar's 奏 place
  Decisions
  /// an agent's execution history (history.mbt): its chat, its session
  History(ChatRef, String)
  /// an entry of a history opened in full: the line it was under, its words
  Words(String, String)
  /// a new chat (newchat.mbt), rising from the bottom; it becomes the chat it makes, in place
  NewChat
  /// a place of the bottom bar's other than the chats, 奏 and 文件 (stations, profiles, connects, usage, archive):
  /// its page at the stack's root
  Place(String)
} derive(Eq)

///|
priv struct App {
  mut nav : @ui.Nav[Page]
  /// the workspace switched to here, before the core's prefs say it
  mut picked : String
  /// the list's filter chosen here, by workspace, before the prefs say it
  filters : Map[String, String]
  /// the filter's menu, and when it was opened
  mut menu : Bool
  mut menu_at : Double
  /// a place switched to on the bar: when, from which side (1 from the right, -1 the left, 0 from no side)
  mut switch_at : Double
  mut switch_way : Int
  /// a row held: its id, since when (the time shows while it is)
  mut held : Int
  mut held_at : Double
  /// what was said last of a write (a toast), and when
  mut toast : String
  mut toast_at : Double
}

///|
let app : App = {
  nav: new_nav(),
  picked: "",
  filters: {},
  menu: false,
  menu_at: 0.0,
  switch_at: -1.0e9,
  switch_way: 0,
  held: 0,
  held_at: 0.0,
  toast: "",
  toast_at: 0.0,
}

///|
/// What a page left leaves behind: a chat's topic and what it told the core.
let left_pages : Array[Page] = []

///|
fn new_nav() -> @ui.Nav[Page] {
  @ui.Nav::new(Home, on_leave=fn(p) { left_pages.push(p) })
}

///|
/// A chat opened over Home from the start (a link, a scripted run).
pub fn open_chat(r : ChatRef) -> Unit {
  app.nav.push(Chat(r))
}

///|
/// A page pushed over Home from the start (a scripted run; the bottom bar's places until there is one).
pub fn open_page(p : Page) -> Unit {
  app.nav.push(p)
}

///|
/// As at the start: Home alone, nothing chosen here yet (tests).
fn reset() -> Unit {
  attention.told = false
  attention.src = None
  app.nav = new_nav()
  app.picked = ""
  app.filters.clear()
  sheet_host.kind = NoSheet
  sheet_host.shown = NoSheet
  sheet_host.scrim = 0.0
  bar_reset()
  fresh.became = None
  fresh.made = ""
  fresh.sent = false
  fresh.starting = false
  new_fix.station = "st1"
  new_fix.model = "claude-opus-5-5"
  new_fix.runtime = "claude"
  new_fix.effort = "high"
  new_fix.d_model = "claude-opus-5-5"
  new_fix.d_runtime = "claude"
  new_fix.d_effort = "high"
  new_fix.d_profile = ""
  new_fix.made = 0
  app.switch_at = -1.0e9
  app.menu = false
  app.held = 0
  app.toast = ""
  read_views.clear()
  read_chats.clear()
  readings.clear()
  left_pages.clear()
  splash_first.val = -1.0
  drafts.clear()
  cui.attach = false
  cui.picking = None
  cui.was_down = false
  cui.press_new = false
  cui.released = false
  cui.moved = false
  cui.outside = false
  cui.room = 0.0
  cui.doing.clear()
  cui.hold = 0
  cui.picked = ""
  fix_chats.clear()
  fix_timers.clear()
  fix_drafts.clear()
  dv_reset()
  decide_reset()
  close_now()
}

///|
/// Back to Home (the stack's root), the sheets and the menu closed.
fn home() -> Unit {
  lower_sheet()
  app.menu = false
  dui.sheet = None
  dui.leaving = None
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
}

///|
/// The app over `src`: call each frame.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.begin(c)
  track_press(c)
  for p in left_pages {
    match p {
      Chat(r) => chat_left(src, r)
      DriveRead(at) => reader_left(at)
      History(r, key) => history_left(src, r, key)
      _ => ()
    }
  }
  left_pages.clear()
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    let accounts = (src.topic)("accounts", {})
    match (accounts.value, (src.fatal)()) {
      (_, Some(why)) => splash(c, Some(why), true)
      (Some(Array(list)), _) if list.length() == 0 => sign_in_page(c, src)
      (Some(Array(_)), _) => signed_in(c, src)
      (_, _) =>
        splash(
          c,
          match accounts.error {
            Some(e) => Some(text(Some(e), "message"))
            None => None
          },
          accounts.error is Some(_),
        )
    }
  })
  |> ignore
}

///|
/// Signed in: the workspace in view (the one switched to, else the one last open, else the first once every account
/// has answered), its Home at the root of the pages; the splash while none is known yet, and a page that says so when
/// there is none.
fn signed_in(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let ws = (src.topic)("workspaces", {})
  let prefs = (src.topic)("prefs", {})
  let (all, answered, invited) = workspaces_of(ws.value)
  let kept = if app.picked != "" {
    app.picked
  } else {
    text(prefs.value, "workspace")
  }
  let current = match all.iter().find_first(fn(w) { w.id == kept }) {
    Some(w) => Some(w)
    None =>
      if all.length() > 0 && (kept == "" || answered) {
        Some(all[0])
      } else {
        None
      }
  }
  match current {
    Some(w) => {
      attend(src, w.id)
      c.nav(app.nav, fn(page) { page_view(c, src, w, all, invited, page) }, bg=t.p.bg)
      |> ignore
      // a place's top page other than the chats, with nothing over it: back goes to the chats, in place
      let root = app.nav.top()
      if app.nav.depth() == 1 && root != Home && !app.menu && !sheet_open() {
        c.on_back(fn() { go_place(c, "chats", [], -1) })
      }
      // the bottom bar: on a place's top page with nothing over it
      bottom_bar(c, src, w, place_of(root), app.nav.depth() == 1 && place_of(root) is Some(_))
      // a file open over the pages (preview.mbt), under the menu, the sheet and the toasts
      preview(c, src)
      if app.menu {
        filter_menu(c, src, w)
      }
      sheet_layer(c, fn(kind) {
        match kind {
          Workspaces => workspaces_sheet(c, src, w, all)
          PickStation(scope) => pick_station_sheet(c, src, scope)
          RunPicker(station) => run_picker_sheet(c, src, station)
          NoSheet => ()
        }
      })
      // a chat's sheets (slice 8's: sheets.mbt, framed in decide.mbt)
      sheets(c, src, w)
      toast(c)
    }
    None =>
      if ws.value is Some(_) && answered {
        no_workspace(c, ws.value)
      } else {
        let failed = match ws.error {
          Some(e) => Some(text(Some(e), "message"))
          None => None
        }
        splash(
          c,
          Some(failed.unwrap_or(t_reading_workspaces(src))),
          failed is Some(_),
        )
      }
  }
}

///|
/// 正在读取你的 workspace, with what the core has been waiting on for a while under it (`status`).
fn t_reading_workspaces(src : Source) -> String {
  let status = (src.topic)("status", {})
  match text(status.value, "text") {
    "" => tr("android-misc.workspaces.loading")
    s => tr("android-misc.workspaces.loading") + "\n" + s
  }
}

///|
fn page_view(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
  page : Page,
) -> Unit {
  // a place switched to on the bar comes in from the side the ball goes to, fading in (220 ms; 180 from no side)
  let root = app.nav.depth() == 1
  let since = c.now() - app.switch_at
  let span = if app.switch_way == 0 { 180.0 } else { 220.0 }
  let e = if root && since < span && !c.stable() {
    c.request_frame()
    @ui.bezier(0.2, 0.8, 0.2, 1.0, dclamp(since / span, 0.0, 1.0))
  } else {
    1.0
  }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    tx=app.switch_way.to_double() * 30.0 * (1.0 - e),
    opacity=e,
    fn() {
      match page {
        Home => home_page(c, src, w, all, invited)
        Chat(r) => {
          chat_page(c, src, w, r)
          new_chat_leaving(c, src, w, r)
        }
        NewChat => new_chat_page(c, src, w)
        Place(p) => place_page(c, p)
        // 文件: a place of the bar at the stack's root, else a page pushed
        Files => files_page(c, src, w, place=app.nav.depth() == 1)
        Drive(at) => drive_page(c, src, w, at)
        DriveRead(at) => reader_page(c, src, at)
        Archived => placeholder_page(c, tr("android-chat.home.filter.archived"))
        Settings => placeholder_page(c, tr("android-chat.home.settings"))
        // 奏: a place of the bar at the stack's root, else a page pushed
        Decisions => decisions_page(c, src, w)
        History(r, key) => history_page(c, src, r, key)
        Words(head, words) => words_page(c, src, head, words)
      }
    },
  )
  |> ignore
}

///|
/// A place from the bottom bar (AppState.place): its page takes the stack's root, in place (nothing to go back to),
/// coming in from the side the ball goes to (App.kt placeSwitch); the same place again changes nothing. `sets`, `cur`:
/// the bar it is chosen in (none: from no side).
fn go_place(c : @ui.Ctx, place : String, sets : Array[Array[String]], cur : Int) -> Unit {
  let page = match place {
    "chats" => Home
    "files" => Files
    "decisions" => Decisions
    p => Place(p)
  }
  if app.nav.depth() == 1 && app.nav.top() == page {
    return
  }
  lower_sheet()
  app.menu = false
  let from = match place_of(app.nav.top()) {
    Some(p) => p
    None => ""
  }
  let bar_now = if cur >= 0 && cur < sets.length() { sets[cur] } else { [] }
  let a = bar_now.search(from).unwrap_or(-1)
  let b = bar_now.search(place).unwrap_or(-1)
  app.switch_way = if a < 0 || b < 0 || a == b {
    0
  } else if b > a {
    1
  } else {
    -1
  }
  app.switch_at = c.now()
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.replace(page)
}

///|
/// What a write said (Sheet.kt ToastHost): over the foot, in ink, 2.6s.
fn toast(c : @ui.Ctx) -> Unit {
  if app.toast == "" {
    return
  }
  let t = @sf.theme()
  // said from a call's answer, between frames: from this frame on
  if app.toast_at < 0.0 {
    app.toast_at = c.now()
  }
  let age = c.now() - app.toast_at
  if age > 2800.0 {
    app.toast = ""
    return
  }
  c.wake_in(2800.0 - age)
  c.layer(align=ACenter, fn() {
    c.spacer()
    c.box(padx=16.0, pady=10.0, bg=t.p.text, radius=18.0, fn() {
      c.text(app.toast, size=14.0, color=t.p.bg, line=20.0) |> ignore
    })
    |> ignore
    c.box(h=Px(90.0), fn() {  }) |> ignore
  })
  |> ignore
}

///|
fn say(c : @ui.Ctx, words : String) -> Unit {
  app.toast = words
  app.toast_at = c.now()
}

///|
/// The app starting, or waiting for what every page needs (Parts.kt Splash): still.fail's mark floating; what it
/// waits for said only once it takes a while (a second), or at once when `now` (a failure).
fn splash(c : @ui.Ctx, label : String?, now : Bool) -> Unit {
  let t = @sf.theme()
  let since = splash_since(c)
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    pad=24.0,
    gap=16.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      let lift = if c.stable() {
        0.0
      } else {
        c.request_frame()
        // 900 ms up, 900 down, eased
        let k = c.now() / 1800.0
        let f = k - k.floor()
        let p = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
        p * p * (3.0 - 2.0 * p)
      }
      c.box(ty=-5.0 * lift, fn() {
        @sf.drawable(
          c,
          if t.dark {
            "stillfail_mark_dark"
          } else {
            "stillfail_mark"
          },
          56.0,
        )
        |> ignore
      })
      |> ignore
      match label {
        Some(s) => {
          let shown = now || c.now() - since > 1000.0
          if !shown {
            c.wake_in(1000.0 - (c.now() - since))
          }
          c.box(opacity=if shown { 1.0 } else { 0.0 }, fn() {
            c.text(s, size=13.0, color=t.p.muted, center=true, line=18.0)
            |> ignore
          })
          |> ignore
        }
        None => ()
      }
    },
  )
  |> ignore
}

///|
let splash_first : Ref[Double] = { val: -1.0 }

///|
fn splash_since(c : @ui.Ctx) -> Double {
  if splash_first.val < 0.0 {
    splash_first.val = c.now()
  }
  splash_first.val
}

///|
/// Signed out (SignIn.kt SignInScreen): the illustration, what still.fail is for, and 登录或注册.
fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let busy = (src.signing_in)()
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    padx=30.0,
    pady=40.0,
    gap=12.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_sign_in_dark"
        } else {
          "illus_sign_in"
        },
        dmin(300.0, c.width - 60.0),
      )
      |> ignore
      c.box(pt=10.0, fn() {
        c.text(
          tr("android-settings.signIn.title"),
          size=28.0,
          weight=700,
          color=t.p.text,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
      c.text(
        tr("android-settings.signIn.note"),
        size=15.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=21.0,
      )
      |> ignore
      c.box(h=Px(6.0), fn() {  }) |> ignore
      let id = c.id("sign-in")
      if c.clicked(id) && !busy {
        (src.sign_in)()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(50.0),
        radius=25.0,
        bg=if c.pressed(id) {
          @sf.mix(t.p.text, 0.85, t.p.bg)
        } else {
          t.p.text
        },
        align=ACenter,
        justify=JCenter,
        id~,
        fn() {
          c.text(
            if busy {
              tr("common.opening")
            } else {
              tr("android-settings.signIn.google")
            },
            size=16.0,
            weight=600,
            color=t.p.bg,
            wrap=false,
          )
          |> ignore
        },
      )
      |> ignore
      c.text(
        tr("android-settings.signIn.many"),
        size=12.0,
        color=t.p.muted,
        wrap=false,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// Signed in, with no workspace yet (Workspaces.kt Landing): said so. (Making one, or joining by an invitation, is
/// a later slice's.)
fn no_workspace(c : @ui.Ctx, ws : Json?) -> Unit {
  let t = @sf.theme()
  let email = match ws {
    Some(Array(a)) if a.length() > 0 => text(field(Some(a[0]), "account"), "email")
    _ => ""
  }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    padx=24.0,
    pady=40.0,
    gap=12.0,
    align=ACenter,
    fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_sign_in_dark"
        } else {
          "illus_sign_in"
        },
        dmin(260.0, c.width - 48.0),
      )
      |> ignore
      c.text(
        tr("android-misc.workspace.none"),
        size=22.0,
        weight=700,
        color=t.p.text,
        center=true,
        w=Fill(1.0),
      )
      |> ignore
      c.text(
        fill("android-misc.workspace.none.lead", [
          ("app", "still.fail"),
          ("email", email),
        ]),
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// How far something opened at `at` has come in (0 … 1, eased out over `ms`): all the way at once in screenshots.
fn opening(c : @ui.Ctx, at : Double, ms : Double) -> Double {
  if c.stable() {
    return 1.0
  }
  let p = (c.now() - at) / ms
  if p >= 1.0 {
    return 1.0
  }
  c.request_frame()
  let q = 1.0 - (if p < 0.0 { 0.0 } else { p })
  1.0 - q * q * q
}

///|
/// What this app last told the core of its attention (`client.focus`): shown, in front, the workspace in view; and
/// where to tell it again when the system says the app left the front between frames.
priv struct Attention {
  mut told : Bool
  mut visible : Bool
  mut focused : Bool
  mut workspace : String
  mut src : Source?
}

///|
let attention : Attention = {
  told: false,
  visible: false,
  focused: false,
  workspace: "",
  src: None,
}

///|
/// Tells the core where this app's attention is, as the Android app's activity and App.kt do: shown and in front or
/// not (`client.focus {visible, focused}`, as the system says: @ui.app_visible, app_focused) and the workspace in view
/// (`workspace`); a chat's own place (`chat`, `left`) is chat.mbt's. Only a change is told. What is read follows from
/// it: the core marks a chat read only while a page in view (visible) shows its end, and shows no notice of a chat
/// one in front shows.
fn attend(src : Source, workspace : String) -> Unit {
  if attention.src is None {
    // the system's say between frames (Android's activity pausing: no frame comes after it)
    @ui.on_app_change(fn(_, _) {
      match attention.src {
        Some(s) => attend(s, attention.workspace)
        None => ()
      }
    })
  }
  attention.src = Some(src)
  let visible = @ui.app_visible()
  let focused = @ui.app_focused()
  if attention.told &&
    visible == attention.visible &&
    focused == attention.focused &&
    workspace == attention.workspace {
    return
  }
  attention.told = true
  attention.visible = visible
  attention.focused = focused
  attention.workspace = workspace
  let params : Map[String, Json] = {
    "visible": Json::boolean(visible),
    "focused": Json::boolean(focused),
    "workspace": Json::string(workspace),
  }
  (src.call)("client.focus", Json::object(params), fn(_) {  })
}
