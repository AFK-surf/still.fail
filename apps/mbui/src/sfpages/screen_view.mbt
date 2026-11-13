// A station's screen, full screen (still.fail apps/android app/remote/ScreenViewer.kt, ScreenActivity.kt;
//): the frame fitted whole (letterboxed), zoomed in place with two fingers; while driving it, a
// tap clicks, a long press right-clicks, a drag drags, two fingers moving together scroll, and the keyboard types into
// it. Upright, the bar is above the frame (close, the title, how the view goes and who is on it, 只看/控制, pasting,
// 控制中心: screen_panel.mbt); sideways, a rail beside it; 全屏, the screen alone, sideways, its tools folded into one
// button over the frame's corner. While driving it, a copy made on the screen (text or a picture) lands on the device's clipboard, the
// device's clipboard is pasted into it, and files picked go onto its machine (how far they have got, then where they
// are, over the frame's foot). How the view is (connecting, reconnecting, ended…) is the core's: on its way, said over
// the frame as it was last shown; over (ended, gone…), said in the screen's place, gone dark. While it is in sight the
// device stays awake; out of sight the view is let go of, and opened again from the frame it showed.
//
// That is touch's. With keyboard and mouse (not a phone's) there is nothing to make
// up for a phone's hand: the viewer's bar across the window's top (the way back, the screen's name and the core's line,
// how the view goes, 控制中心, 只看/控制), the picture under it; the mouse is the screen's pointer where it is (its moves,
// its buttons, its wheel: screen_mouse), the keyboard types into it once it is pressed, ⌘V pastes this device's
// clipboard there, and 全屏 is the window's.

///|
/// What the viewer keeps of a view beside the session: the frame's zoom, the trackpad's pointer, the modifiers held,
/// 全屏 and its folded tools, the rail's line said, the press under way.
priv struct ScreenUi {
  zoom : @kit.Zoom
  pad : PadPointer
  held : HeldKeys
  full : @signals.Signal[Bool]
  /// the window made to fill the screen by its 全屏 (keyboard and mouse's), put back as it closes
  mut fulled : Bool
  /// shown as a tab beside its chat, whose tab closes it: no close of its own (the same thing twice)
  mut in_tab : Bool
  /// the only tab of a panel of its own: the panel's bar, its style, in place of a row of the panel's over it
  mut own_bar : @ui.Style?
  mut tools_open : Bool
  /// how far the folded tools were dragged from their corner (so they cover another part of the screen)
  tools_moved : Afloat
  /// how far the mouse's buttons were dragged from theirs
  mouse_moved : Afloat
  mut saying : Bool
  /// how many times the rail's line was asked for: its 3 s start again from each
  mut sayings : Int
  /// the stage's size when last built (told as it changes: 控制中心's 分辨率 reads it), and the frame's size it was fitted
  /// for
  box_w : @signals.Signal[Double]
  box_h : @signals.Signal[Double]
  /// where the stage was drawn last (its top left in the window)
  mut stage_x : Double
  mut stage_y : Double
  mut fit_for : (Int, Int)?
  /// how much a device's case is round its picture each way, as shares of the picture (device_case); none: 0
  mut case_x : Double
  mut case_y : Double
  mut over_seen : Bool
  gesture : Gesture
  /// where the last tap, press held or drag driving it directly ended on the picture (0..1): where 左键 and 右键 click
  /// while the station says no pointer
  mut tapped_at : (Double, Double)?
  /// the page it is shown on, as last built (its title, whether it goes back once its screen is gone)
  mut at : ScreenAt?
  /// it drove the screen as last built
  mut drove : Bool
  /// its page under another on the stack (screen_covered): out of sight
  covered : @signals.Signal[Bool]
  /// a mouse on the stage (screen_mouse)
  mouse : MouseDrive
  /// a read of the device's clipboard under way, for a paste
  mut reading : @ui.ClipboardRead?
  /// the modifiers held from the keys row as each key went down (by its code), for it to go up with them too
  down_with : Map[String, Int]
  /// the copies made on the screen put on the device's clipboard
  mut copies : Int
  /// the device kept awake, the window sideways, a phone let turn as held: as last told to the host
  mut awake : Bool
  mut sideways_told : Bool
  mut turnable : Bool
  /// the keys row turned to the keys its first face had not the room for (keys_row's ⋯), by their names; none: its
  /// first face
  mut keys_turned : Array[String]
  /// the second of the frames' clock (Ctx::every) it was first seen live in, -1 not yet; the second counted last, and
  /// the frames and bytes come by then; the frames and bits a second over the last second, once one was counted
  mut first_tick : Int
  mut rate_tick : Int
  /// how many of those seconds it has been seen (told as each is counted: 控制中心's row reads it)
  seen : @signals.Signal[Int]
  mut rate_frames : Int
  mut rate_bytes : Int
  mut fps : Double?
  mut bps : Double?
  /// a simulator's log as far as it was read (screen_debug.mbt)
  logs : DebugLogs
  /// 控制中心 ("center"), the view's figures ("net"), 按键 ("keys") or a simulator's 日志 ("logs") or 重启 App ("apps") to
  /// open from the bar as it is next built (a fixture's: as if pressed); "" none
  mut asked_panel : String
  /// the panel this page opened over itself (控制中心 "center", 按键 "keys", the view's figures "stats", a simulator's
  /// "logs" or "apps"), the serial it was presented as (what is a step further in from it, presented after it, is its
  /// too: screen_panel_open_from) and whether the system's bars were down the side then (@sf.native_side); none since
  /// it was closed
  mut native_panel : (String, Int, Bool)?
  /// a browser's tab (screen_browser.mbt): its address bar's field and the address it was made holding, how many were
  /// made (its editor's key), whether it had the keys as last built (picked whole as it takes them), the keys asked for
  /// it (⌘L, a new tab), and how its page is closed (⌘W on its last tab)
  mut address : (String, @ui.Field)?
  mut address_made : Int
  mut address_in : Bool
  mut address_asked : Bool
  mut close_page : () -> Unit
  /// its bar laid out narrow as last built (a touch screen upright, a narrow window): 控制中心 offers a browser's → and
  /// ⟳ then
  mut narrow_bar : Bool
  /// a browser's own keys pressed (⌘T, ⌘W…), each told once the frame is built
  mut browser_keys : Int
  /// upright, the foot shows the keyboard's row (its 键盘 pressed), till it is put away again
  mut typing : Bool
}

///|
let screen_uis : Map[String, ScreenUi] = Map([])

///|
fn screen_ui(key : String) -> ScreenUi {
  match screen_uis.get(key) {
    Some(u) => u
    None => {
      let u : ScreenUi = {
        zoom: screen_zoom(),
        pad: { x: 0.5, y: 0.5, placed: false },
        held: { mods: 0 },
        full: @signals.signal(false),
        fulled: false,
        in_tab: false,
        own_bar: None,
        tools_open: false,
        tools_moved: afloat_new(),
        mouse_moved: afloat_new(),
        saying: false,
        sayings: 0,
        box_w: @signals.signal(0.0, same=fn(a, b) { a == b }),
        box_h: @signals.signal(0.0, same=fn(a, b) { a == b }),
        stage_x: 0.0,
        stage_y: 0.0,
        fit_for: None,
        case_x: 0.0,
        case_y: 0.0,
        over_seen: false,
        gesture: gesture_new(),
        tapped_at: None,
        at: None,
        drove: false,
        covered: @signals.signal(false, same=fn(a, b) { a == b }),
        mouse: mouse_drive_new(),
        reading: None,
        down_with: {},
        copies: 0,
        awake: false,
        sideways_told: false,
        turnable: false,
        keys_turned: [],
        first_tick: -1,
        rate_tick: -1,
        seen: @signals.signal(0, same=fn(a, b) { a == b }),
        rate_frames: 0,
        rate_bytes: 0,
        fps: None,
        bps: None,
        logs: debug_logs_new(),
        asked_panel: "",
        native_panel: None,
        address: None,
        address_made: 0,
        address_in: false,
        address_asked: false,
        close_page: fn() {  },
        narrow_bar: false,
        browser_keys: 0,
        typing: false,
      }
      screen_uis[key] = u
      u
    }
  }
}

///|
/// The phases a view is over in (said in the screen's place, gone dark); `here`: this machine's own display, never
/// opened.
fn phase_over(p : String) -> Bool {
  p == "ended" || p == "outdated" || p == "gone" || p == "denied" || p == "failed" || p == "here"
}

///|
/// How long the rail's line stays said once asked for.
let rail_say_ms : Double = 3000.0

///|
/// The viewer of `at.screen` on `at.station` (ScreenViewer): `at.title` until the core says one (the link's own, or the
/// row's it was opened from); one opened until its screen is gone (a login's page) goes back by itself then. Inside
/// the room its frame keeps over and under it (`frame`: the system's bars), unless full.
pub fn screen_page(
  c : @ui.Ctx,
  src : Source,
  at : ScreenAt,
  frame : PageFrame,
  on_close? : () -> Unit,
  in_tab? : Bool = false,
  own_bar? : @ui.Style? = None,
) -> Unit {
  let station = at.station
  let screen = at.screen
  let title = at.title
  let key = screen_key(station, screen)
  let s = screen_sess(src, station, screen)
  // (built again for each state that changed what it reads: taken as they come, a pointer's move alone builds nothing)
  s.said.get() |> ignore
  let u = screen_ui(key)
  u.in_tab = in_tab
  u.own_bar = own_bar
  u.at = Some(at)
  // its 关闭: closed through the shell, the page it is; the window back as it was where its 全屏 filled the screen
  let close = fn() {
    screen_panels_close(u)
    if u.fulled && @ui.full_screen() {
      c.set_full_screen(false)
    }
    u.fulled = false
    match on_close {
      Some(f) => f()
      None => @sfbase.close_page(Screen(at)) |> ignore
    }
  }
  u.close_page = close
  // open while the app is in sight (ScreenActivity onStart / onStop) and the page not under another: the last frame kept
  // between
  let shown = @ui.app_visible() && !u.covered.get()
  c.after_build("screen-open/" + key, fn() {
    s.own_stream()
    // on a phone or a tablet, a page of the station's browser is laid out for the stage it is shown on, as this
    // device's own browser would lay it out (the station takes no notice of it for other screens)
    if @sf.soft_keyboard() && u.box_w.get() > 0.0 && u.box_h.get() > 0.0 && s.fit is None {
      s.fit = Some((u.box_w.get(), u.box_h.get(), c.scale))
    }
    // 自动 asks for a picture as large as the stage is in this device's pixels
    if u.box_w.get() > 0.0 && u.box_h.get() > 0.0 {
      s.stage_is((u.box_w.get() * c.scale).round().to_int(), (u.box_h.get() * c.scale).round().to_int())
    }
    if shown {
      // 画质 chosen otherwise: opened again with it; open again where it was let go, not where it is over (重新打开
      // opens that)
      s.asked_again(src)
      if !phase_over(s.phase()) {
        s.open(src)
      }
    } else {
      s.pause(src)
    }
    // while it is looked at, the device stays awake: a screen is watched more than touched
    if u.awake != shown {
      u.awake = shown
      @ui.keep_awake(shown)
      // (into the device's performance record while it is kept: what warms a phone is mostly a screen looked at)
      @hostapi.perf_line("app: screen " + (if shown { "shown " } else { "hidden " }) + key)
    }
    // while it is looked at, a phone turns as it is held,
    // the rotation lock honoured: with it on, the system offers its turn button
    if u.turnable != shown {
      u.turnable = shown
      @hostapi.set_turnable(shown)
    }
  })
  // its screen gone (the login's tab closed as it ended): back to where it was opened from
  if at.until_gone && s.phase() == "gone" {
    c.after_build("screen-gone/" + key, close)
  }
  // a child popup opened from this tab while driving: follow it (returning here when its window closes)
  if shown && s.child_screen is Some(next) {
    s.child_screen = None
    c.after_build("screen-child/" + key, fn() {
      let child_at : ScreenAt = { station: s.station, screen: next, title: "", until_gone: true }
      match @sfbase.lone_page.val {
        Some(Screen(prev)) => {
          screen_left(src, prev.station, prev.screen)
          @sfbase.lone_page.val = Some(Screen({ ..child_at, until_gone: false }))
        }
        _ =>
          if u.in_tab {
            @sfbase.open_page(Screen(child_at))
          } else {
            @sfbase.app.nav.push(Screen(child_at))
          }
      }
    })
  }
  // over (ended, gone…): out of 全屏, the bar's × and what happened in sight
  let over = !s.open_now()
  if over && u.full.get() {
    u.full.set(false)
  }
  let sideways_on = u.full.get() && !u.covered.get()
  if sideways_on != u.sideways_told {
    let on = sideways_on
    c.after_build("screen-sideways/" + key, fn() {
      u.sideways_told = on
      @hostapi.set_sideways(on)
    })
  }
  // back in 全屏 leaves it first
  if u.full.get() {
    c.on_back(fn() { u.full.set(false) })
  }
  screen_count(c, s, u)
  screen_copies(c, s, u)
  screen_pasted(c, s, u)
  // unseen, where the keyboard's input goes
  let catcher = "screen-keys/" + key
  let kc = c.key_catcher(catcher)
  // no longer driving it (只看, the view ended): the keyboard goes, and as it stops, the modifiers held on the keys row
  if !s.driving() && kc.focused {
    c.catch_keys(catcher, false)
  }
  if u.drove && !s.driving() {
    u.held.mods = 0
    u.down_with.clear()
    u.typing = false
  }
  u.drove = s.driving()
  // (the keys row over the frame while the soft keyboard is up; the keyboard's button by where the keys go, a keyboard
  // plugged in raising none)
  let typing = c.keyboard_up()
  let catching = kc.focused
  screen_keys_in(c, s, u, kc.keys)
  let (ww, wh) = c.window_size()
  let sideways = ww > wh
  // 全屏 there: the system's bars put away too (no title, no actions), the frame edge to edge with its tools folded as
  // anywhere else
  // (while it is the page shown, or the window it has of its own: its part kept or built again)
  let lone = on_close is Some(_) && !in_tab
  let native = !in_tab &&
    @sf.native_over_up(if u.full.get() { "" } else { title }, alive=fn() { lone || @sfbase.app.nav.top() == Screen(at) }) &&
    !u.full.get()
  if native {
    screen_native(c, s, u, catching, catcher, close)
  }
  // inside the bars unless full (ScreenViewer.kt: windowInsetsPadding(safeDrawing); full, edge to edge)
  // (full, edge to edge: no room kept for what its frame keeps it from)
  let room = fn(h : Double) {
    if h > 0.0 && (!u.full.get() || native) {
      c.box(style=@ui.style(w=Full, h=Fixed(h)), fn() {  }) |> ignore
    }
  }
  c.box(style=if u.full.get() { screen_whole } else { screen_page_box }, fn() {
  room(frame.top)
  let within = if native { screen_within.then(@ui.style(pr=@sf.room_of(@sf.native_clear()))) } else { screen_within }
  c.box(style=within, fn() { c.box(style=if u.full.get() { screen_page_full } else { screen_page_box }, fn() {
    if native {
      if browser_shown(s) {
        browser_bar(c, s, u, close)
      }
      c.box(style=screen_fill, fn() {
        // as sideways: the keys a phone's keyboard has not while it is up, else the mouse's buttons (the stage's foot's)
        screen_content(c, s, u, key, pair=!(s.driving() && typing) && mouse_shown(s))
        if s.can_take_over() {
          c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s, u) }) |> ignore }) |> ignore
        }
        if s.driving() && typing {
          c.layer(fn() { c.box(style=screen_foot_center, fn() { keys_capsule(c, s, u) }) |> ignore }) |> ignore
        }
      }) |> ignore
    } else if u.full.get() {
      c.box(style=screen_fill, fn() {
        screen_stage(c, s, u, key, pair=!typing && mouse_shown(s))
        if s.can_take_over() {
          c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s, u) }) |> ignore }) |> ignore
        }
        if s.driving() && typing {
          c.layer(fn() { c.box(style=screen_foot_center.then(@sf.sides_clear(@ui.Space::S2.px())), fn() { keys_capsule(c, s, u) }) |> ignore })
          |> ignore
        }
        c.layer(fn() {
          c.box(style=screen_corner_end(screen_top_end), fn() { full_tools(c, s, u, catching, catcher, close) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    } else if !@sf.soft_keyboard() {
      // keyboard and mouse: the viewer's bar across the window's top, always there, the picture under it (what is at
      // the top of the screen, its windows' title bars, never under the bar); the keyboard and the mouse its own
      screen_viewer_bar(c, s, u, title, close)
      if browser_shown(s) {
        browser_bar(c, s, u, close)
      }
      screen_content(c, s, u, key)
    } else if sideways {
      c.box(style=screen_row, fn() {
        screen_rail(c, s, u, catching, catcher, close)
        c.box(style=screen_fill, fn() {
          // (the mouse's buttons, the keyboard down, floating over its foot's corner: the stage's foot's)
          screen_content(c, s, u, key, pair=!(s.driving() && typing) && mouse_shown(s))
          // sideways the frame takes the height: who drives it floats over its top, while it does
          if s.can_take_over() {
            c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s, u) }) |> ignore })
            |> ignore
          }
          // the keys a phone's keyboard has not, over the frame's foot while it is up
          if s.driving() && typing {
            c.layer(fn() { c.box(style=screen_foot_center, fn() { keys_capsule(c, s, u) }) |> ignore })
            |> ignore
          }
        })
        |> ignore
        // the rail's line, said beside it over its foot once the people on it are tapped
        if u.saying && s.state is Some(_) {
          c.layer(fn() {
            c.box(style=rail_say_place, fn() {
              c.box(style=rail_say_box, fn() { c.text(text(s.state, "line"), style=rail_say_words) |> ignore })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    } else {
      screen_top_bar(c, s, u, title, close)
      if s.can_take_over() {
        c.box(style=take_over_place, fn() { take_over(c, s, u) }) |> ignore
      }
      screen_content(c, s, u, key)
      // upright, under the frame: trackpad or direct, the keys a phone's keyboard has not, the keyboard (a simulator's
      // only while typing: it has a keyboard of its own, and buttons of its own under the frame)
      if s.driving() && (!s.simulator() || typing) {
        foot(c, s, u, catching, catcher)
      }
    }
  })
  |> ignore }) |> ignore
  room(frame.foot)
  })
  |> ignore
}

///|
/// The serial of what is open of the panel this page opened as `root` (it, or what a step further in from it shows,
/// each presented after it); 0 none.
fn screen_panel_open_from(root : Int) -> Int {
  for n = root; n <= @sf.last_presented(); n = n + 1 {
    if @sf.presented_open_of(n) {
      return n
    }
  }
  0
}

///|
/// Whether the panel this page opened as `id` is up, or one a step further in from it.
fn screen_panel_on(u : ScreenUi, id : String) -> Bool {
  match u.native_panel {
    Some((key, root, _)) => key == id && screen_panel_open_from(root) > 0
    None => false
  }
}

///|
/// What this page opened over itself closed, and what a step further in from it shows: so it never outlives what it
/// was opened for (the page closed or let go, 全屏, 只看/控制 changed, the keyboard toggled, another of the system bar's
/// actions pressed: the reviewer with pengxiao, 2026-11-12; the system's bars turned to another edge, where the item it
/// was opened at is no longer: screen_native).
fn screen_panels_close(u : ScreenUi) -> Unit {
  match u.native_panel {
    Some((_, root, _)) => {
      let open = screen_panel_open_from(root)
      if open > 0 {
        @sf.close_presented_of(open)
      }
    }
    None => ()
  }
  u.native_panel = None
}

///|
/// This page's panel `id` opened by `open` (what it is opened by pressed), what else it opened closed first; where it is
/// up already, closed instead.
fn screen_panel_toggle(u : ScreenUi, id : String, open : () -> Unit) -> Unit {
  let was = screen_panel_on(u, id)
  screen_panels_close(u)
  if was {
    return
  }
  open()
  u.native_panel = Some((id, @sf.last_presented(), @sf.native_side()))
}

///|
fn screen_native_anchor(c : @ui.Ctx) -> @sf.Anchor {
  let at = @hostapi.nav_tapped_at
  let (w, h) = c.window_size()
  if at[2] <= 0.0 && @sf.native_side() { return At(w - @sf.native_clear(), h / 2.0, 0.0, 0.0) }
  let x = if @sf.native_side() { dmin(at[0], w - @sf.native_clear()) } else { at[0] }
  At(x, at[1], at[2], at[3])
}

///|
/// The screen's actions handed to the system's bars (an iPhone Duo's), the least needed last, as the system folds those
/// it has not the room for from the end (the keyboard up, it keeps three): close, 只看/控制, the keyboard, 控制中心, 按键.
/// What else there is is 控制中心's (the reviewer with pengxiao, 2026-11-12). Each but a panel's own closes what this
/// page opened over itself before it acts. What it opened closes as the bars turn to another edge (down the side, or
/// across): the system says where an item is only as it is pressed, so what was opened at it would stay where it was.
fn screen_native(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, catching : Bool, catcher : String, close : () -> Unit) -> Unit {
  if u.native_panel is Some((_, _, side)) && side != @sf.native_side() {
    screen_panels_close(u)
  }
  @sf.native_over_act("screen-close", @sf.t("android-misc.screen.close"), "close", close, lead=true)
  if s.choosable() {
    // (as mode_button: what it is now, on while driving)
    let on = s.controlling()
    @sf.native_over_act("screen-mode", @sf.t(if on { "android-misc.screen.drive" } else { "android-misc.screen.look" }),
      if on { "cursor" } else { "eye" }, fn() { control_chosen(c, s, u, !s.controlling()) }, active=on)
  }
  if s.driving() {
    @sf.native_over_act("screen-keyboard", @sf.t("android-misc.screen.keyboard"), "keyboard", fn() { keyboard_toggled(c, u, catcher, catching) }, active=catching)
  }
  if s.open_now() {
    @sf.native_over_act("screen-center", @sf.t("web-pages.screen.panel"), "sliders", fn() {
      let from = screen_native_anchor(c)
      screen_panel_toggle(u, "center", fn() {
        @sf.panel_nodes(@sf.t("web-pages.screen.panel"), fn(v, done) { center_node(c, v, s, u, from, close, done) }, from~, side=screen_panel_side(), focus=false)
      })
    }, active=screen_panel_on(u, "center"))
  }
  if s.driving() && !s.simulator() {
    @sf.native_over_act("screen-keys", @sf.t("web-pages.screen.keysPanel"), "keycap", fn() {
      keys_open(s, u, screen_native_anchor(c))
    }, active=screen_panel_on(u, "keys"))
  }
}

///|
/// The view's page put under another (a chat opened over it from a notice; `covered`) or on top again: under it, not
/// built but as it slides away, the view is let go of as out of sight, the last frame kept, the device let sleep and
/// turn as it did; on top again its page, built again for it, opens it (screen_page's after_build).
pub fn screen_covered(src : Source, station : String, screen : String, covered : Bool) -> Unit {
  let key = screen_key(station, screen)
  guard screen_uis.get(key) is Some(u) else { return }
  u.covered.set(covered)
  if !covered {
    return
  }
  match screens_open.get(key) {
    Some(s) => s.pause(src)
    None => ()
  }
  if u.sideways_told {
    u.sideways_told = false
    @hostapi.set_sideways(false)
  }
  if u.awake {
    u.awake = false
    @ui.keep_awake(false)
    @hostapi.perf_line("app: screen hidden " + key)
  }
  if u.turnable {
    u.turnable = false
    @hostapi.set_turnable(false)
  }
}

///|
/// The view's page gone: the view, its decoder and its files let go of; upright (held upright only again) and asleep
/// again.
pub fn screen_left(src : Source, station : String, screen : String) -> Unit {
  let key = screen_key(station, screen)
  match screens_open.get(key) {
    Some(s) => s.close(src)
    None => ()
  }
  match screen_uis.get(key) {
    Some(u) => {
      screen_panels_close(u)
      if u.fulled && @ui.full_screen() { @hostapi.set_full_screen(false) }
      if u.sideways_told {
        @hostapi.set_sideways(false)
      }
      if u.awake {
        @ui.keep_awake(false)
        @hostapi.perf_line("app: screen closed " + key)
      }
      if u.turnable {
        @hostapi.set_turnable(false)
      }
    }
    None => ()
  }
  screens_open.remove(key)
  screen_uis.remove(key)
}

// ── what goes between the device and the screen ─────────────────────────

///|
/// `run` (a call to the screen) under way; its failure said as 无法<what>：<why>.
fn screen_act(
  c : @ui.Ctx,
  what : String,
) -> (Result[Json, Json]) -> Unit {
  fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => say(c, @sf.t("android-misc.act.failed", args=[("what", what), ("error", error_words(e))]))
    }
  }
}

///|
/// A copy made on the screen: onto the device's clipboard, text as it is, a picture as a PNG (the latest copy wins).
/// Where the system says so itself (Android 13 and later, with a preview), nothing more; else it is said here.
fn screen_copies(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.copied.is_empty() {
    return
  }
  let got = s.copied.copy()
  s.copied.clear()
  let label = match opt_text(s.state, "title") {
    Some(t) if t != "" => t
    _ => "still.fail"
  }
  let types = s.clip_types()
  // (what came on the core's stream, put on the clipboard once: the copies are taken out above, in the build that saw
  // them)
  c.tell("screen-copied/" + s.view + "/\{u.copies}", fn() {
    for g in got {
      match g {
        CopiedText(t) => {
          @ui.clipboard_set(t, label~)
          if !@ui.copy_shown() {
            say(c, @sf.t("android-misc.screen.copied"))
          }
        }
        // only from a screen that says it carries pictures (a station from before them sends none)
        CopiedPng(b) =>
          if types.contains("png") {
            @ui.clipboard_set_png(b, label~)
            if !@ui.copy_shown() {
              say(c, @sf.t("android-misc.screen.copiedImage"))
            }
          }
      }
    }
  })
  u.copies += got.length()
}

///|
/// The device's clipboard, pasted into the screen where its focus is: its picture as PNG where the screen carries
/// pictures, else its text. Asked of the system as the button is
/// tapped (paste_asked), taken here once it answers.
fn screen_pasted(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  guard u.reading is Some(r) else { return }
  guard r.got() is Some(got) else { return }
  u.reading = None
  let types = s.clip_types()
  let image = !(got.picture is NoPicture)
  let words = got.text
  let what = @sf.t("android-misc.screen.pasteWhat")
  let done = fn(r : Result[Json, Json]) {
    s.pasting = false
    (screen_act(c, what))(r)
  }
  let kind = if image && types.contains("png") {
    "image"
  } else if words != "" && types.contains("text") {
    "text"
  } else if image && words == "" {
    "no-images"
  } else if words != "" {
    "no-text"
  } else {
    "empty"
  }
  match kind {
    "image" =>
      match got.picture {
        Png(png) if png.length() <= clip_png_max =>
          c.tell("screen-paste/" + s.view, fn() { s.paste_png(s.src, png, done) })
        Png(_) | TooLarge => {
          s.pasting = false
          say(c, @sf.t("android-misc.screen.imageTooLarge"))
        }
        _ => {
          s.pasting = false
          say(c, @sf.t("android-misc.screen.imageUnread"))
        }
      }
    "text" => c.tell("screen-paste/" + s.view, fn() { s.paste(s.src, words, done) })
    "no-images" => {
      s.pasting = false
      say(c, @sf.t("android-misc.screen.noImages"))
    }
    "no-text" => {
      s.pasting = false
      say(c, @sf.t("android-misc.screen.noText"))
    }
    _ => {
      s.pasting = false
      say(c, @sf.t("android-misc.screen.clipboardEmpty"))
    }
  }
}

///|
/// 粘贴手机剪贴板 tapped (or ⌘V): the device's clipboard read (the system answers; screen_pasted takes it), asked once
/// the frame's builds are over, as the last says it.
fn paste_asked(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.pasting {
    return
  }
  c.after_build("screen-paste/" + s.station + "/" + s.screen, fn() {
    if s.pasting {
      return
    }
    match @ui.clipboard_read() {
      Some(r) => {
        s.pasting = true
        u.reading = Some(r)
      }
      None => say(c, @sf.t("android-misc.screen.clipboardEmpty"))
    }
  })
}

///|
/// 发送文件 tapped: the system's picker, the files it gives going where the state says now.
fn send_asked(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  ignore(u)
  guard s.drops_to() is Some(to) else { return }
  if @ui.pick(Files, on_got=fn(files) { if !files.is_empty() { s.send_files(files, to) } }) is None {
    say(c, @sf.t("android-chat.composer.noFiles"))
  }
}

///|
/// 安装 App tapped: the system's picker, what it gives going up to be installed on the device.
fn install_asked(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  ignore(u)
  let folder = text(s.state, "install")
  guard folder != "" else { return }
  let to : DropTo = { folder, reveal: false, install: true }
  if @ui.pick(Files, on_got=fn(files) { if !files.is_empty() { s.send_files(files, to) } }) is None {
    say(c, @sf.t("android-chat.composer.noFiles"))
  }
}

///|
/// Trackpad or direct, said as it is chosen: how a finger drives it now. A trackpad starts where the screen's pointer is.
fn pad_chosen(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, on : Bool) -> Unit {
  if on {
    u.pad.start_at(s.cursor())
  }
  say(c, @sf.t(if on { "android-misc.screen.padOn" } else { "android-misc.screen.padOff" }))
  c.tell("screen-pad/" + s.view, fn() {
    s.choose_pad(s.src, on, screen_act(c, @sf.t("android-misc.screen.touchWhat")))
  })
}

///|
/// 只看 or 控制, chosen.
fn control_chosen(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, on : Bool) -> Unit {
  screen_panels_close(u)
  s.wants_control = Some(on)
  c.tell("screen-control/" + s.view, fn() { s.control(s.src, on) })
}

///|
/// What the keyboard sends (the key catcher's: committed words, named keys and shortcuts as taps), as the screen takes
/// it, with the modifiers held on the keys row: words typed with one held go as keys with it, a
/// key goes down with them and up with what it went down with.
fn screen_keys_in(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, keys : Array[@ui.KeyIn]) -> Unit {
  if keys.is_empty() {
    return
  }
  let sent : Array[Json] = []
  let send = fn(j : Json) { sent.push(j) }
  for k in keys {
    match k {
      Text(words) => {
        type_words(send, u.held, words)
        // (no paste on Xcode 27's yet, the keys; said when it is what was just typed)
        if s.simulator() && text(s.state, "title").contains("iOS 27") && words.iter().any(fn(ch) { ch.to_int() > 0x7e }) {
          u.logs.relaunch_said = @sf.t("web-pages.screen.debug.keysNote")
        }
      }
      // ⌘V (Ctrl+V): this device's clipboard onto the screen's and pasted there, where it carries one, as a paste is
      // on the web's page (its keys are not sent)
      Key(down~, code="KeyV", mods~, ..) if (mods & (mod_meta | mod_ctrl)) != 0 &&
        (mods & mod_alt) == 0 &&
        s.pastes() => if down { paste_asked(c, s, u) }
      // a browser's own keys on a tab of the station's browser (⌘L, ⌘T, ⌘W, ⌘R, ⌘[, ⌘]): the viewer's, as a browser's
      Key(down~, code~, mods~, ..) if browser_key(c, s, u, code, mods, down) => ()
      Key(down~, key~, code~, mods~) => {
        let extra = if down {
          let m = u.held.take()
          u.down_with[code] = m
          m
        } else {
          let m = u.down_with.get(code).unwrap_or(0)
          u.down_with.remove(code)
          m
        }
        send(key_input(if down { "down" } else { "up" }, key, code, mods | extra))
      }
    }
  }
  c.tell("screen-keys/" + s.view, fn() {
    for j in sent {
      s.input(s.src, j)
    }
  })
}

///|
/// The keyboard taken or let go (ScreenViewer.kt keyboard()): by whether the keys go to the screen (`catching`), not
/// whether the soft keyboard is up (none with a keyboard plugged in, or put away by the system with the keys still
/// here).
fn keyboard_toggled(c : @ui.Ctx, u : ScreenUi, catcher : String, catching : Bool) -> Unit {
  screen_panels_close(u)
  c.catch_keys(catcher, !catching)
  // (upright, the foot is the keyboard's row from now till it is put away again: a key of it pressed takes nothing
  // from it)
  u.typing = !catching
}

// ── the bar, the rail, the folded tools ──────────────────────────────────

///|
/// A round button with an icon (40, its icon 20), its name for those who cannot see it and as its tip; `on`: pressed
/// (the keyboard up, 控制); tapped, `on_press` (as it is let go: Ctx::on_press).
fn round_button(c : @ui.Ctx, key : String, icon : String, label : String, on? : Bool = false, on_press~ : () -> Unit) -> Unit {
  let id = c.id(key)
  let i = c.box(style=round_button_box, selected=on, id~, fn() {
    @sf.icon(c, icon, size=round_icon, color=c.color(Fg)) |> ignore
  })
  c.semantics(i, Button, id~, label~, pressed=on, actions=[Activate])
  @sf.tip(c, key, id, label)
  c.on_press(id, on_press)
}

///|
/// Upright (the user, 2026-11-13: 「连带着远程控制的 UI 一起重构」): one row, close, then the screen's name and the core's
/// line (only looking, who else is on it), the view's tabs folded into a button counting them where it has them (a
/// desktop's windows), 控制中心 (只看, pasting, sending files, 全屏, how the view goes: all there); a tab of the
/// station's browser has ← and its address bar in its name's place (screen_browser.mbt).
fn screen_top_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, title : String, close : () -> Unit) -> Unit {
  u.narrow_bar = true
  c.box(style=match u.own_bar { Some(own) => own; None => if u.in_tab { screen_bar_in_tabs } else { screen_bar } }, fn() {
    if !u.in_tab {
      round_button(c, "screen-close", "close", @sf.t("android-misc.screen.close"), on_press=fn() {
        close()
      })
    }
    if browser_shown(s) {
      browser_seen(s)
      c.box(style=screen_bar_tools, fn() { browser_tools(c, s, u, close, true) }) |> ignore
    } else {
      c.box(style=screen_bar_words, fn() {
        let said = match opt_text(s.state, "title") {
          Some(t) if t != "" => t
          _ => if title != "" { title } else { @sf.t("android-misc.screen.title") }
        }
        // (among a panel's tabs, the tab in front names it)
        if !u.in_tab || u.own_bar is Some(_) {
          c.text(said, style=screen_title_words) |> ignore
        }
        // while another drives it, who does is said below (with 接管), not twice
        let line = text(s.state, "line")
        if line != "" && s.open_now() && !s.can_take_over() {
          c.text(line, style=screen_line_words) |> ignore
        }
      })
      |> ignore
      let (tabs, _) = view_tabs(s)
      if !tabs.is_empty() {
        tabs_button(c, s, u, tabs.length(), close)
      }
    }
    if s.open_now() {
      center_button(c, s, u, close)
    }
    // (a panel's bar of its own: the panel's close at its end, beside what it closes, where the system has bars too:
    // among the chat's actions in them it read as another thing's; the user, 2026-11-06)
    if u.own_bar is Some(_) {
      round_button(c, "screen-close", "close", @sf.t("android-misc.screen.close"), on_press=fn() {
        close()
      })
    }
  })
  |> ignore
}

///|
/// Whether the link to the screen's station is poor now (its round trip amber or red): the viewer's bar says so then,
/// and only then (its figures are 控制中心's).
fn net_poor(s : ScreenSess) -> Bool {
  let level = text(field(screen_net(s), "rtt"), "level")
  level == "amber" || level == "red"
}

///|
/// With keyboard and mouse: the viewer's bar across the window's top (@sf.viewer_bar), one row (the user, 2026-11-13):
/// back by its name, the view's tabs in the name's place where it has them (a person's pages on the station's browser,
/// ＋ after them; a desktop's whole screen and its windows), else the screen's name and the core's line; at its end
/// the link's figures only while it is poor, 组合键 while driving a desktop, 控制中心 (只看 is there), and 接管 while
/// someone else drives it, who does said in the line's place. Narrow, the tabs fold into a button counting them.
fn screen_viewer_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, title : String, close : () -> Unit) -> Unit {
  let narrow = view_narrow(c, u)
  u.narrow_bar = narrow
  let said = match opt_text(s.state, "title") {
    Some(t) if t != "" => t
    _ => if title != "" { title } else { @sf.t("android-misc.screen.title") }
  }
  let line = if !s.open_now() { "" } else if s.can_take_over() { drives_words(s) } else { text(s.state, "line") }
  let ink = @sf.page_viewer_ink()
  let combos = s.driving() && !s.simulator()
  let (tabs, add) = view_tabs(s)
  let middle = if tabs.is_empty() || narrow { None } else { Some(fn() { tabs_row(c, s, u, tabs, add, close) }) }
  @sf.viewer_bar(c, "screen-bar", @sf.t("common.back"), said, line, false, ink, fn() {
    if s.phase() == "live" && net_poor(s) {
      net_chip(c, s, u)
    }
    // narrow, the tabs folded into the button counting them (a browser's is by its address bar)
    if narrow && !tabs.is_empty() && !browser_shown(s) {
      tabs_button(c, s, u, tabs.length(), close)
    }
    // (组合键 while driving: the keyboard has the rest)
    if combos {
      combos_chip(c, s, u)
    }
    if s.open_now() {
      center_chip(c, s, u, close)
    }
    if s.can_take_over() {
      take_over(c, s, u, in_bar=true)
    }
  }, capsule_end=s.can_take_over(), on_back=close, middle?)
}

///|
/// Pasting the device's clipboard (where the station carries text or pictures), while driving it.
fn paste_button(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.pastes() {
    round_button(c, "screen-paste", "paste", @sf.t("android-misc.screen.paste"), on=s.pasting, on_press=fn() { paste_asked(c, s, u) })
  }
}

///|
/// 全屏 (on) or not.
fn full_button(c : @ui.Ctx, u : ScreenUi) -> Unit {
  let label = @sf.t(if u.full.get() { "android-misc.screen.unfull" } else { "android-misc.screen.full" })
  round_button(c, "screen-full", "landscape", label, on=u.full.get(), on_press=fn() {
    screen_panels_close(u)
    u.full.set(!u.full.get())
  })
}

///|
/// 只看/控制 as one round button (the rail's, the folded tools'): the pointer while driving, an eye while looking.
fn mode_button(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let on = s.controlling()
  let (icon, label) = if on {
    ("cursor", @sf.t("android-misc.screen.drive"))
  } else {
    ("eye", @sf.t("android-misc.screen.look"))
  }
  round_button(c, "screen-mode-btn", icon, label, on~, on_press=fn() {
    control_chosen(c, s, u, !on)
  })
}

///|
fn keyboard_button(c : @ui.Ctx, u : ScreenUi, catcher : String, catching : Bool) -> Unit {
  round_button(c, "screen-keyboard", "keyboard", @sf.t("android-misc.screen.keyboard"), on=catching, on_press=fn() {
    keyboard_toggled(c, u, catcher, catching)
  })
}

///|
/// 全屏's tools, folded into one round button over the frame's corner (in the letterbox, as a screen wider than the
/// device leaves one): open, the same as the rail's down from it — 只看/控制, trackpad, pasting, the keyboard,
/// 控制中心, 退出全屏. Its button dragged, they go where it is let go, kept inside the window (what is under the corner
/// in sight again).
fn full_tools(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  catching : Bool,
  catcher : String,
  close : () -> Unit,
) -> Unit {
  let capsule = c.id("screen-tools-capsule")
  let (laid_dx, laid_dy) = (u.tools_moved.dx, u.tools_moved.dy)
  // a round button 4 in from the capsule's edge: its corner 20 + 4
  c.box(style=full_tools_box, id=capsule, tx=laid_dx, ty=laid_dy, fn() {
    let (icon, label) = if u.tools_open {
      ("close", @sf.t("android-misc.screen.toolsClose"))
    } else {
      ("more", @sf.t("android-misc.screen.tools"))
    }
    let id = c.id("screen-tools")
    afloat_dragged(c, u.tools_moved, id)
    round_button(c, "screen-tools", icon, label, on=u.tools_open, on_press=fn() {
      u.tools_open = !u.tools_open
    })
    if u.tools_open {
      if s.choosable() {
        mode_button(c, s, u)
      }
      if s.driving() {
        keys_button(c, s, u)
      }
      paste_button(c, s, u)
      if s.driving() {
        keyboard_button(c, u, catcher, catching)
      }
      center_button(c, s, u, close)
      full_button(c, u)
    }
  })
  |> ignore
  afloat_kept(c, u.tools_moved, capsule, laid_dx, laid_dy)
}

///|
/// Sideways: the same down the side, the line said when the people on it are tapped (there while others are).
fn screen_rail(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  catching : Bool,
  catcher : String,
  close : () -> Unit,
) -> Unit {
  // said for 3 s once asked for
  if u.saying && @kit.after(c, "screen-saying/\{u.sayings}", true, rail_say_ms) {
    u.saying = false
  }
  let line = text(s.state, "line")
  c.box(fn() {
    c.box(style=rail_box, fn() {
      if !u.in_tab {
        round_button(c, "screen-close", "close", @sf.t("android-misc.screen.close"), on_press=fn() {
          close()
        })
      }
      c.spacer()
      let others = items(s.state, "others").length()
      if s.state is Some(_) && line != "" && s.open_now() && others > 0 {
        c.box(style=rail_people, fn() {
          round_button(c, "screen-people", "users", @sf.t("android-misc.screen.people"), on=u.saying, on_press=fn() {
            u.saying = !u.saying
            u.sayings += 1
          })
          if others > 0 {
            c.layer(fn() {
              c.box(style=rail_badge_place, fn() {
                // 4 out past the button's right, 2 over its top
                c.box(style=rail_badge, tx=rail_badge_out, ty=-rail_badge_up, fn() {
                  c.text("\{others}", style=rail_badge_words) |> ignore
                })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      }
      if s.choosable() {
        mode_button(c, s, u)
      }
      if s.driving() {
        keys_button(c, s, u)
      }
      paste_button(c, s, u)
      if s.driving() {
        keyboard_button(c, u, catcher, catching)
      }
      if s.open_now() {
        center_button(c, s, u, close)
        full_button(c, u)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Where the count of the others on it sits past the rail's people button's top right corner.
let rail_badge_out : Double = 4.0

///|
let rail_badge_up : Double = 2.0

///|
/// Upright, under the frame while driving it (the user, 2026-11-13: 「小屏下面的操作…不够直观，不够方便」). Not typing: a
/// few large actions, each its mark over its name — 键盘, 粘贴 (where the station takes the clipboard), 按键 (组合键,
/// F1–F12…; not a simulator's), and with the trackpad 左键 and 右键 (directly, a tap clicks and a press held clicks
/// right). Typing: what a phone's keyboard has not (Esc, Tab, ⌘ ⌃ ⌥ ⇧, the arrows) over it, the keyboard put away at
/// its end, as a keyboard's row of keys over a phone's own.
fn foot(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, catching : Bool, catcher : String) -> Unit {
  if catching || u.typing {
    c.box(style=screen_foot, fn() {
      // (按键 first: what the row and the keyboard have not, 组合键 and F1–F12)
      keys_button(c, s, u)
      c.box(style=screen_fill_w, fn() { keys_row(c, s, u, mouse=false) }) |> ignore
      // the keyboard put away, and the row with it (already down, the system's own: the row alone)
      round_button(c, "screen-keyboard", "keyboard", @sf.t("android-misc.screen.keyboard"), on=true, on_press=fn() {
        screen_panels_close(u)
        if catching {
          c.catch_keys(catcher, false)
        }
        u.typing = false
      })
    })
    |> ignore
    return
  }
  c.box(style=screen_foot_actions, fn() {
    foot_action(c, "screen-keyboard", "keyboard", @sf.t("android-misc.screen.keyboard"), @sf.t("android-misc.screen.keyboard"), fn() {
      keyboard_toggled(c, u, catcher, catching)
    })
    if s.pastes() {
      foot_action(c, "screen-paste", "paste", @sf.t("web-pages.screen.paste"), @sf.t("android-misc.screen.paste"), on=s.pasting, fn() {
        paste_asked(c, s, u)
      })
    }
    if !s.simulator() {
      let id = c.id("screen-keys")
      foot_action(c, "screen-keys", "keycap", @sf.t("web-pages.screen.keysPanel"), @sf.t("web-pages.screen.keysPanel"), on=screen_panel_on(u, "keys"), fn() {
        keys_open(s, u, Of(id))
      })
      // (a fixture's, asked as it is built)
      if u.asked_panel == "keys" {
        u.asked_panel = ""
        keys_open(s, u, Of(id))
      }
    }
    if mouse_shown(s) && s.pad(s.src) {
      let left = @sf.t("android-misc.screen.key.mouseLeft")
      let right = @sf.t("android-misc.screen.key.mouseRight")
      foot_action(c, "screen-click", "mouse-left", left, left, felt=btn_primary, fn() { button_clicked(s, u, btn_primary) })
      foot_action(c, "screen-click-right", "mouse-right", right, right, felt=btn_secondary, fn() { button_clicked(s, u, btn_secondary) })
    }
  })
  |> ignore
}

///|
/// One of the foot's actions: its mark over its name, as wide as its share of the row, lit while `on`; its name for
/// those who cannot see it `label` (粘贴's says whose clipboard).
fn foot_action(
  c : @ui.Ctx,
  key : String,
  icon : String,
  words : String,
  label : String,
  on? : Bool = false,
  felt? : Int = 0,
  press : () -> Unit,
) -> Unit {
  let id = c.id(key)
  let b = c.box(style=foot_action_box, selected=on, id~, fn() {
    @sf.icon(c, icon, size=round_icon, color=c.color(Fg)) |> ignore
    c.text(words, style=foot_action_words) |> ignore
  })
  c.semantics(b, Button, id~, label~, pressed=on, actions=[Activate])
  // (a mouse's button felt as it goes down, as the keys row's were)
  if felt != 0 {
    button_felt(c, id, felt)
  }
  c.on_press(id, press)
}

///|
/// A key of the keys row: what it sends, or a modifier held for the next key (`mod`, its bit).
priv struct RowKey {
  label : String
  name : String
  key : String
  code : String
  mod_ : Int
  icon : String
  /// where the row has not the room for every key: the k-th to leave it for its ⋯ (Ctx::box `drop`; 0: never)
  drop : Int
  /// a mouse button (btn_primary, btn_secondary) clicked where the pointer is, instead of a key; 0 a key
  button : Int
}

///|
fn screen_row_keys() -> Array[RowKey] {
  let k = fn(label, name, key, code, mod_, icon, drop) -> RowKey { { label, name, key, code, mod_, icon, drop, button: 0 } }
  let b = fn(name, icon, button) -> RowKey {
    { label: "", name, key: "", code: "", mod_: 0, icon, drop: 0, button }
  }
  // (short of room the least used leave first: ⌥, ⌃, ⇧, Tab, ⌘, then up and down, left and right last; the mouse's
  // buttons and Esc stay)
  [
    b(@sf.t("android-misc.screen.key.mouseLeft"), "mouse-left", btn_primary),
    b(@sf.t("android-misc.screen.key.mouseRight"), "mouse-right", btn_secondary),
    k("Esc", "Esc", "Escape", "Escape", 0, "", 0),
    k("Tab", "Tab", "Tab", "Tab", 0, "", 4),
    k("⌘", @sf.t("android-misc.screen.key.command"), "", "", mod_meta, "", 5),
    k("⌃", @sf.t("android-misc.screen.key.control"), "", "", mod_ctrl, "", 2),
    k("⌥", @sf.t("android-misc.screen.key.option"), "", "", mod_alt, "", 1),
    k("⇧", @sf.t("android-misc.screen.key.shift"), "", "", mod_shift, "", 3),
    k("", @sf.t("android-misc.screen.key.left"), "ArrowLeft", "ArrowLeft", 0, "arrow-left", 7),
    k("", @sf.t("android-misc.screen.key.up"), "ArrowUp", "ArrowUp", 0, "arrow-up", 6),
    k("", @sf.t("android-misc.screen.key.down"), "ArrowDown", "ArrowDown", 0, "arrow-down", 6),
    k("", @sf.t("android-misc.screen.key.right"), "ArrowRight", "ArrowRight", 0, "arrow-right", 7),
  ]
}

///|
/// The mouse's two buttons (clicked where the pointer is: the trackpad's, else the screen's own), the keys a phone's
/// keyboard has not (Esc, Tab, the arrows) and the modifiers (⌘ ⌃ ⌥ ⇧: held, shown solid, for the next key or click,
/// typed or here), in a row. Where it has not the room for them all, the least used leave it (RowKey's
/// `drop`; a modifier held never), and a ⋯ key at its end turns the row to them, as a keyboard turns to its other
/// keys (lit while turned; pressed again, on to those that had not the room there either, or back): nothing scrolled,
/// nothing wrapped, nothing over the keyboard.
fn keys_row(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, mouse? : Bool = mouse_shown(s)) -> Unit {
  let keys = screen_row_keys().filter(fn(k) { k.button == 0 || mouse })
  let held = fn(k : RowKey) { k.mod_ != 0 && (u.held.mods & k.mod_) != 0 }
  let leaves = fn(k : RowKey) { if held(k) { 0 } else { k.drop } }
  let slot = fn(k : RowKey) { c.id("screen-key-slot/" + s.view + "/" + k.name) }
  let more = c.id("screen-keys-more/" + s.view)
  let on_face = fn(k : RowKey) { u.keys_turned.is_empty() || u.keys_turned.contains(k.name) }
  c.on_press(more, fn() {
    // (turned to those this face left out as last laid out, read back, the frame built again where that changes: from
    // the first face its others, and from them, where they too have not the room, the rest; none left out, back)
    u.keys_turned = keys.filter(fn(k) { on_face(k) && leaves(k) > 0 && c.left_out(slot(k)) }).map(fn(k) { k.name })
  })
  let turned = !u.keys_turned.is_empty()
  let key = fn(k : RowKey) {
    let on = held(k)
    let id = c.id("screen-key/" + k.name)
    let i = c.box(style=row_key_box, selected=on, id~, fn() {
      if k.icon != "" {
        @sf.icon(c, k.icon, size=key_icon, color=c.color(Fg)) |> ignore
      } else {
        c.text(k.label, style=if on { row_key_on_words } else { row_key_words }) |> ignore
      }
    })
    c.semantics(i, Button, id~, label=k.name, pressed=on, actions=[Activate])
    if k.button != 0 {
      button_felt(c, id, k.button)
    }
    c.on_press(id, fn() {
      if k.mod_ != 0 {
        u.held.toggle(k.mod_)
      } else if k.button != 0 {
        button_clicked(s, u, k.button)
      } else {
        let mods = u.held.take()
        stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, mods)
      }
    })
  }
  let more_key = fn() {
    let i = c.box(style=row_key_box, selected=turned, id=more, fn() {
      @sf.icon(c, "more", size=key_icon, color=c.color(if turned { Bg } else { Fg })) |> ignore
    })
    c.semantics(i, Button, id=more, label=@sf.t("common.more"), pressed=turned, actions=[Activate])
  }
  c.box(style=keys_row_box, fn() {
    for k in keys {
      if on_face(k) {
        c.box(id=slot(k), taps=false, drop=leaves(k), fn() { key(k) }) |> ignore
      }
    }
    // (the ⋯: on the first face there only while a key is out; turned, always, the way on or back)
    if turned {
      more_key()
    } else {
      c.box(more=true, fn() { more_key() }) |> ignore
    }
  })
  |> ignore
}

///|
/// Mouse button `button` clicked where the pointer is (the trackpad's, else the screen's own; the station saying none,
/// where a finger last pressed on the picture, else the trackpad's), the modifiers the keys row holds round it.
fn button_clicked(s : ScreenSess, u : ScreenUi, button : Int) -> Unit {
  let mods = u.held.take()
  let at = match pointer_now(s, u) {
    Some(at) => at
    None => u.tapped_at.unwrap_or(u.pad.at())
  }
  click(fn(j) { s.input(s.src, j) }, at, button, mods)
}

///|
/// A mouse button `id` felt as a press goes down on it (the click itself goes as it is let go): the right button as a
/// context click, the left as a key.
fn button_felt(c : @ui.Ctx, id : Int, button : Int) -> Unit {
  let kind : @ui.Haptic = if button == btn_secondary { ContextClick } else { KeyboardTap }
  c.follow_press(id, fn(step) {
    if step is Down(_, _, _) {
      @ui.haptic(kind)
    }
  })
}

///|
/// Whether the mouse's buttons show while driving a screen that is no simulator's: the keys row's two, and their
/// floating pair in 全屏 and sideways. Never turned off (pengxiao, 2026-11-12: nobody does, and the keys row folds what
/// has not the room).
fn mouse_shown(s : ScreenSess) -> Bool {
  s.driving() && !s.simulator()
}

///|
/// 左键 and 右键 side by side at the end of the frame's foot (the system bar's, 全屏 and sideways, the keyboard down: the
/// keys row is not there; screen_stage's foot, what else is there laid out clear of them), each a round button
/// floating on its own, the two dragged anywhere together by either, as the folded tools are.
fn mouse_float(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let capsule = c.id("screen-mouse-capsule")
  let (laid_dx, laid_dy) = (u.mouse_moved.dx, u.mouse_moved.dy)
  c.box(style=mouse_pair_end, fn() {
    c.box(style=mouse_pair_box, id=capsule, tx=laid_dx, ty=laid_dy, fn() {
      afloat_dragged(c, u.mouse_moved, capsule)
      for b in [
        ("screen-mouse-left", "mouse-left", "android-misc.screen.key.mouseLeft", btn_primary),
        ("screen-mouse-right", "mouse-right", "android-misc.screen.key.mouseRight", btn_secondary),
      ] {
        let id = c.id(b.0)
        let label = @sf.t(b.2)
        let i = c.box(style=mouse_button_box, id~, fn() {
          @sf.icon(c, b.1, size=round_icon, color=c.color(Fg)) |> ignore
        })
        c.semantics(i, Button, id~, label~, actions=[Activate])
        button_felt(c, id, b.3)
        c.on_press(id, fn() { button_clicked(s, u, b.3) })
      }
    })
    |> ignore
  })
  |> ignore
  afloat_kept(c, u.mouse_moved, capsule, laid_dx, laid_dy)
}

///|
/// How far a floating capsule (the folded tools, the mouse's buttons) was dragged from its corner, and from where a
/// drag of it began.
priv struct Afloat {
  mut dx : Double
  mut dy : Double
  mut from : (Double, Double)?
  /// the window's size as it was last built: its layout before is of another window once it changes
  mut win : (Double, Double)
}

///|
fn afloat_new() -> Afloat {
  { dx: 0.0, dy: 0.0, from: None, win: (0.0, 0.0) }
}

///|
/// Drag area `id` moving the capsule with the finger (a press on it that does not move is a tap of what is under it).
fn afloat_dragged(c : @ui.Ctx, f : Afloat, id : Int) -> Unit {
  c.drag_on(id, axis=Free)
  match c.drag_of(id) {
    Some(d) => {
      if d.moving {
        let (fx, fy) = match f.from {
          Some(at) => at
          None => {
            let at = (f.dx, f.dy)
            f.from = Some(at)
            at
          }
        }
        f.dx = fx + d.x - d.x0
        f.dy = fy + d.y - d.y0
      } else {
        f.from = None
      }
      d.take_end() |> ignore
    }
    None => ()
  }
}

///|
/// The capsule kept inside the window as it was last laid out (moved past its edge, opened longer): laid out moved as
/// far as it was drawn (`laid_dx`, `laid_dy`), its corner's place is that less how far. The window turned, back to its
/// corner.
fn afloat_kept(c : @ui.Ctx, f : Afloat, capsule : Int, laid_dx : Double, laid_dy : Double) -> Unit {
  // (the window turned or resized: back to its corner, where it is laid out in the window as it is now; what was
  // laid out before is of another window)
  let now = c.window_size()
  if f.win != now {
    f.win = now
    f.dx = 0.0
    f.dy = 0.0
    return
  }
  match c.laid_rect(capsule) {
    Some((x, y, w, h)) => {
      let (ww, wh) = now
      let x0 = x - laid_dx
      let y0 = y - laid_dy
      // (its panel still past the window's edge, on the tape: nothing to keep it inside of yet)
      if x0 < 0.0 || x0 + w > ww {
        return
      }
      f.dx = dmax(-x0, dmin(ww - w - x0, f.dx))
      f.dy = dmax(-y0, dmin(wh - h - y0, f.dy))
    }
    None => ()
  }
}

///|
/// The keys row floating over the frame's foot (sideways and 全屏, while the keyboard is up).
fn keys_capsule(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  c.box(style=keys_capsule_box, fn() { keys_row(c, s, u) }) |> ignore
}

///|
/// Who else drives it, as the state names them.
fn drivers_of(s : ScreenSess) -> Array[String] {
  items(s.state, "controllers").filter_map(fn(j) {
    match j {
      String(n) => Some(n)
      _ => None
    }
  })
}

///|
/// 「<who> 正在控制」, or 「他人正在控制」 where the state names nobody.
fn drives_words(s : ScreenSess) -> String {
  let who = drivers_of(s)
  if who.is_empty() {
    @sf.t("android-misc.screen.someoneDrives")
  } else {
    @sf.t("android-misc.screen.drives", args=[("who", who.join(@sf.t("web-main.list.separator")))])
  }
}

///|
/// Someone else drives it (an agent at work) and this view only looks: who, and 接管 in one tap (`screen.control` true:
/// their input waits while this person drives; the line then says so).
fn take_over(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, in_bar? : Bool = false) -> Unit {
  let who = drivers_of(s)
  // a capsule round a 32 high button 6 in from its edge: its corner 6 + 16; in the viewer's bar, a row of its tools, who
  // drives said by the bar's line
  c.box(style=if in_bar { take_over_bar_row } else { take_over_box }, fn() {
    if !in_bar {
      c.box(style=take_over_dot, fn() {  }) |> ignore
      c.box(style=take_over_words_box, fn() {
        c.text(drives_words(s), style=take_over_words) |> ignore
      })
      |> ignore
    }
    // the main solid button, as the web's primary (dark in the light theme, light in the dark one), not the accent
    let id = c.id("screen-take-over")
    // (whole, what says who drives cut short beside it)
    let i = c.box(style=take_over_button, id~, keep=true, fn() {
      c.text(@sf.t("android-misc.screen.takeOver"), style=take_over_button_words) |> ignore
    })
    c.semantics(i, Button, id~, label=@sf.t("android-misc.screen.takeOver"), actions=[Activate])
    // what it does: their input waits while this person drives
    let names = if who.is_empty() { @sf.t("web-pages.screen.someone") } else { who.join(@sf.t("web-pages.screen.and")) }
    @sf.tip(c, "screen-take-over-tip", id, @sf.t("web-pages.screen.takeOverTip", args=[("names", names)]))
    c.on_press(id, fn() {
      control_chosen(c, s, u, true)
    })
  })
  |> ignore
}

///|
/// The screens open as the device's performance record says them (@ui.perf_also "screens"): each its codec and size,
/// the 帧率 and 画质 asked, the frames and bytes that came since last asked (as 控制中心's 连接 counts them: ScreenSess::came),
/// over `span` ms; "" where none is open.
pub fn screens_perf(span : Double) -> String {
  let line = StringBuilder()
  for key, s in screens_open {
    let (frames, bytes) = s.came()
    let (f0, b0) = screens_perf_was.get(key).unwrap_or((frames, bytes))
    screens_perf_was[key] = (frames, bytes)
    let secs = (if span > 1.0 { span } else { 1.0 }) / 1000.0
    let size = match s.size {
      Some((w, h)) => "\{w}x\{h}"
      None => "-"
    }
    line.write_string(
      (if line.is_empty() { "" } else { " | " }) +
      "\{s.codec.unwrap_or("-")} \{size} asked=\{s.asked}/\{s.asked_fps}fps fps=\{((frames - f0).to_double() / secs).round()} kbps=\{((bytes - b0).to_double() * 8.0 / 1000.0 / secs).round()} phase=\{s.phase()}",
    )
  }
  for key in screens_perf_was.keys().collect() {
    if !screens_open.contains(key) {
      screens_perf_was.remove(key)
    }
  }
  line.to_string()
}

///|
/// Each open screen's frames and bytes as screens_perf last said them, by its key.
// kept across runs: the record's counts, put back as a screen closes (screens_perf)
let screens_perf_was : Map[String, (Int, Int)] = Map([])
