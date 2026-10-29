// A station's screen, full screen (ember apps/android app/remote/ScreenViewer.kt, ScreenActivity.kt;
// docs/remote-screens.md): the frame fitted whole (letterboxed), zoomed in place with two fingers; while driving it, a
// tap clicks, a long press right-clicks, a drag drags, two fingers moving together scroll, and the keyboard types into
// it. Upright, the bar is above the frame (close, the title, how the view goes and who is on it, 只看/控制, pasting,
// 控制中心: screen_panel.mbt); sideways, a rail beside it; 全屏, the screen alone, sideways, its tools folded into one
// button over the frame's corner. While driving it, a copy made on the screen (text or a picture) lands on the device's clipboard, the
// device's clipboard is pasted into it, and files picked go onto its machine (how far they have got, then where they
// are, over the frame's foot). How the view is (connecting, reconnecting, ended…) is the core's: on its way, said over
// the frame as it was last shown; over (ended, gone…), said in the screen's place, gone dark. While it is in sight the
// device stays awake; out of sight the view is let go of, and opened again from the frame it showed.
//
// That is touch's. With keyboard and mouse (web/src/screen/ScreenViewer.tsx's, not a phone's) there is nothing to make
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
  mut full : Bool
  /// the window made to fill the screen by its 全屏 (keyboard and mouse's), put back as it closes
  mut fulled : Bool
  /// shown as a tab beside its chat, whose tab closes it: no close of its own (the same thing twice)
  mut in_tab : Bool
  mut tools_open : Bool
  /// how far the folded tools were dragged from their corner (so they cover another part of the screen)
  tools_moved : Afloat
  /// how far the mouse's buttons were dragged from theirs
  mouse_moved : Afloat
  /// 鼠标左右键 as last chosen in 控制中心, before the prefs say so (none: as they say)
  mut mouse_set : Bool?
  /// the display's scale last asked for (0 none): asked once, not again each frame its pick still shows it
  mut scale_asked : Int
  /// the display's resolution last asked for (0 wide none): asked once, as the scale is
  mut size_asked : (Int, Int)
  mut saying : Bool
  /// how many times the rail's line was asked for: its 3 s start again from each
  mut sayings : Int
  /// the stage's size when last built, and the frame's size it was fitted for
  mut box_w : Double
  mut box_h : Double
  /// where the stage was drawn last (its top left in the window)
  mut stage_x : Double
  mut stage_y : Double
  mut fit_for : (Int, Int)?
  mut over_seen : Bool
  gesture : Gesture
  /// a mouse on the stage (screen_mouse)
  mouse : MouseDrive
  /// the picker asked for files, and where they go (as the state said when it was asked for)
  mut picking : @ui.Pick?
  mut drop_to : DropTo?
  /// a read of the device's clipboard under way, for a paste
  mut reading : @ui.ClipboardRead?
  /// the modifiers held from the keys row as each key went down (by its code), for it to go up with them too
  down_with : Map[String, Int]
  /// the press (by the frame it went down in) a mouse button last buzzed for, so it buzzes once as it goes down
  mut buzzed : Int
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
  mut rate_frames : Int
  mut rate_bytes : Int
  mut fps : Double?
  mut bps : Double?
  /// how many times 复制诊断 was pressed (已复制 said a moment after each)
  mut diag_copies : Int
  /// 控制中心 ("center") or the view's figures ("net") to open from the bar as it is next built (a fixture's: as if
  /// pressed); "" none
  mut asked_panel : String
  mut native_panel : (String, Int)?
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
        pad: { x: 0.5, y: 0.5, moves: 0 },
        held: { mods: 0 },
        full: false,
        fulled: false,
        in_tab: false,
        tools_open: false,
        tools_moved: afloat_new(),
        mouse_moved: afloat_new(),
        mouse_set: None,
        scale_asked: 0,
        size_asked: (0, 0),
        saying: false,
        sayings: 0,
        box_w: 0.0,
        box_h: 0.0,
        stage_x: 0.0,
        stage_y: 0.0,
        fit_for: None,
        over_seen: false,
        gesture: gesture_new(),
        mouse: mouse_drive_new(),
        picking: None,
        drop_to: None,
        reading: None,
        down_with: {},
        buzzed: -1,
        copies: 0,
        awake: false,
        sideways_told: false,
        turnable: false,
        keys_turned: [],
        first_tick: -1,
        rate_tick: -1,
        rate_frames: 0,
        rate_bytes: 0,
        fps: None,
        bps: None,
        diag_copies: 0,
        asked_panel: "",
        native_panel: None,
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
/// How long the rail's line stays said once asked for (ScreenViewer.kt Rail: 3000).
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
  // its 关闭: closed through the shell, the page it is; the window back as it was where its 全屏 filled the screen
  let close = fn() {
    if u.fulled && @ui.full_screen() {
      c.set_full_screen(false)
    }
    u.fulled = false
    match on_close {
      Some(f) => f()
      None => @sfbase.close_page(Screen(at)) |> ignore
    }
  }
  // open while the app is in sight (ScreenActivity onStart / onStop): the last frame kept between
  let shown = @ui.app_visible()
  c.after_build("screen-open/" + key, fn() {
    s.own_stream()
    // on a phone or a tablet, a page of the station's browser is laid out for the stage it is shown on, as this
    // device's own browser would lay it out (the station takes no notice of it for other screens)
    if @sf.soft_keyboard() && u.box_w > 0.0 && u.box_h > 0.0 && s.fit is None {
      s.fit = Some((u.box_w, u.box_h, c.scale))
    }
    // 自动 asks for a picture as large as the stage is in this device's pixels
    if u.box_w > 0.0 && u.box_h > 0.0 {
      s.stage_is((u.box_w * c.scale).round().to_int(), (u.box_h * c.scale).round().to_int())
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
    }
    // while it is looked at, a phone turns as it is held (ScreenViewer.kt: the activity's orientation unspecified),
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
  // over (ended, gone…): out of 全屏, the bar's × and what happened in sight
  let over = !s.open_now()
  if over && u.full {
    u.full = false
  }
  if u.full != u.sideways_told {
    let on = u.full
    c.after_build("screen-sideways/" + key, fn() {
      u.sideways_told = on
      @hostapi.set_sideways(on)
    })
  }
  // back in 全屏 leaves it first
  if u.full {
    c.on_back(fn() { u.full = false })
  }
  screen_count(c, s, u)
  screen_copies(c, s, u)
  screen_pasted(c, s, u)
  screen_picked(c, s, u)
  // unseen, where the keyboard's input goes
  let catcher = "screen-keys/" + key
  let kc = c.key_catcher(catcher)
  // no longer driving it (只看, the view ended): the keyboard goes
  if !s.driving() && kc.focused {
    c.catch_keys(catcher, false)
  }
  let typing = c.keyboard_up()
  screen_keys_in(c, s, u, kc.keys)
  let (ww, wh) = c.window_size()
  let sideways = ww > wh
  // 全屏 there: the system's bars put away too (no title, no actions), the frame edge to edge with its tools folded as
  // anywhere else
  let native = !in_tab && @sf.native_over_up(if u.full { "" } else { title }) && !u.full
  if native {
    screen_native(c, s, u, typing, catcher, close)
  }
  // inside the bars unless full (ScreenViewer.kt: windowInsetsPadding(safeDrawing); full, edge to edge)
  // (full, edge to edge: no room kept for what its frame keeps it from)
  let room = fn(h : Double) {
    if h > 0.0 && (!u.full || native) {
      c.box(style=@ui.style(w=Full, h=Fixed(h)), fn() {  }) |> ignore
    }
  }
  c.box(style=if u.full { screen_whole } else { screen_page_box }, fn() {
  room(frame.top)
  let within = if native { screen_within.then(@ui.style(pr=@sf.room_of(@sf.native_clear()))) } else { screen_within }
  c.box(style=within, fn() { c.box(style=if u.full { screen_page_full } else { screen_page_box }, fn() {
    if native {
      c.box(style=screen_fill, fn() {
        screen_stage(c, s, u, key)
        if s.can_take_over() {
          c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s) }) |> ignore }) |> ignore
        }
        if s.driving() && typing {
          c.layer(fn() { c.box(style=screen_foot_center, fn() { keys_capsule(c, s, u) }) |> ignore }) |> ignore
        }
      }) |> ignore
    } else if u.full {
      c.box(style=screen_fill, fn() {
        screen_stage(c, s, u, key)
        if s.can_take_over() {
          c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s) }) |> ignore }) |> ignore
        }
        if s.driving() && typing {
          c.layer(fn() { c.box(style=screen_foot_center.then(@sf.sides_clear(@ui.Space::S2.px())), fn() { keys_capsule(c, s, u) }) |> ignore })
          |> ignore
        }
        if !typing && mouse_shown(s, u) {
          c.layer(fn() { mouse_float(c, s, u) }) |> ignore
        }
        c.layer(fn() {
          c.box(style=screen_corner_end(screen_top_end), fn() { full_tools(c, s, u, typing, catcher, close) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    } else if !@sf.soft_keyboard() {
      // keyboard and mouse: the viewer's bar across the window's top, always there, the picture under it (what is at
      // the top of the screen, its windows' title bars, never under the bar); the keyboard and the mouse its own
      screen_viewer_bar(c, s, u, title, close)
      screen_stage(c, s, u, key)
    } else if sideways {
      c.box(style=screen_row, fn() {
        screen_rail(c, s, u, typing, catcher, close)
        c.box(style=screen_fill, fn() {
          screen_stage(c, s, u, key)
          // sideways the frame takes the height: who drives it floats over its top, while it does
          if s.can_take_over() {
            c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s) }) |> ignore })
            |> ignore
          }
          // the keys a phone's keyboard has not, over the frame's foot while it is up
          if s.driving() && typing {
            c.layer(fn() { c.box(style=screen_foot_center, fn() { keys_capsule(c, s, u) }) |> ignore })
            |> ignore
          } else if mouse_shown(s, u) {
            // else the mouse's buttons, floating over its foot's corner
            c.layer(fn() { mouse_float(c, s, u) }) |> ignore
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
        c.box(style=take_over_place, fn() { take_over(c, s) }) |> ignore
      }
      screen_stage(c, s, u, key)
      // upright, under the frame: trackpad or direct, the keys a phone's keyboard has not, the keyboard
      if s.driving() {
        foot(c, s, u, typing, catcher)
      }
    }
  })
  |> ignore }) |> ignore
  room(frame.foot)
  })
  |> ignore
}

///|
/// A standalone remote screen uses Duo's system actions, putting away the app's places. A screen in a chat tab
/// keeps the pane's own controls. The picture is fitted clear of the system column in screen_page.
fn screen_native_panel_on(u : ScreenUi, id : String) -> Bool {
  u.native_panel is Some((key, serial)) && key == id && @sf.presented_open_of(serial)
}

///|
fn screen_native_panel(u : ScreenUi, id : String, open : () -> Unit) -> Unit {
  if u.native_panel is Some((key, serial)) && @sf.presented_open_of(serial) {
    @sf.close_presented_of(serial)
    u.native_panel = None
    if key == id { return }
  }
  open()
  u.native_panel = Some((id, @sf.last_presented()))
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
fn screen_native(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, typing : Bool, catcher : String, close : () -> Unit) -> Unit {
  @sf.native_over_act("screen-close", @sf.t("android-misc.screen.close"), "close", close, lead=true)
  if s.choosable() {
    let on = s.controlling()
    @sf.native_over_act("screen-mode", @sf.t(if on { "android-misc.screen.look" } else { "android-misc.screen.drive" }),
      if on { "eye" } else { "cursor" }, fn() { control_chosen(c, s, !s.controlling()) })
  }
  if s.driving() {
    @sf.native_over_act("screen-pad", @sf.t("android-misc.screen.trackpad"), "trackpad", fn() { pad_chosen(c, s, !s.pad(s.src)) })
    @sf.native_over_act("screen-keyboard", @sf.t("android-misc.screen.keyboard"), "keyboard", fn() { keyboard_toggled(c, catcher, typing) })
  }
  if s.pastes() {
    @sf.native_over_act("screen-paste", @sf.t("android-misc.screen.paste"), "paste", fn() { paste_asked(c, s, u) })
  }
  if s.audio_ready {
    @sf.native_over_act("screen-audio", @sf.t(if s.audio_muted { "web-pages.drive.player.unmute" } else { "web-pages.drive.player.mute" }),
      if s.audio_muted { "volume-x" } else { "volume" }, fn() {
        s.toggle_audio()
      })
  }
  if s.open_now() {
    @sf.native_over_act("screen-center", @sf.t("web-pages.screen.panel"), "sliders", fn() {
      let from = screen_native_anchor(c)
      screen_native_panel(u, "center", fn() {
        @sf.panel(@sf.t("web-pages.screen.panel"), fn(c, done) { center_panel(c, s, u, from, close, done) }, from~, side=screen_panel_side(), focus=false)
      })
    }, active=screen_native_panel_on(u, "center"))
    @sf.native_over_act("screen-stats", @sf.t("web-pages.screen.stats"), "chart", fn() {
      net_panel_open(s, u, screen_native_anchor(c))
    }, active=screen_native_panel_on(u, "stats"))
    @sf.native_over_act("screen-full", @sf.t("android-misc.screen.full"), "landscape", fn() { u.full = true })
    let line = text(s.state, "line")
    if line != "" {
      @sf.native_over_act("screen-people", line, "users", fn() {
        screen_native_panel(u, "people", fn() {
          @sf.panel(line, fn(_, _) {  }, from=screen_native_anchor(c), side=screen_panel_side(), focus=false)
        })
      }, active=screen_native_panel_on(u, "people"))
    }
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
      if u.fulled && @ui.full_screen() { @ui.current().set_full_screen(false) }
      if u.sideways_told {
        @hostapi.set_sideways(false)
      }
      if u.awake {
        @ui.keep_awake(false)
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
/// pictures, else its text (ScreenViewer.kt paste; ScreenClips.kt pasteKind). Asked of the system as the button is
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
        Png(png) => c.tell("screen-paste/" + s.view, fn() { s.paste_png(s.src, png, done) })
        TooLarge => {
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
  guard s.drops_to() is Some(to) else { return }
  match @ui.pick(Files) {
    Some(p) => {
      u.picking = Some(p)
      u.drop_to = Some(to)
    }
    None => say(c, @sf.t("android-chat.composer.noFiles"))
  }
}

///|
/// The files picked, once the system has answered: each going onto the machine, one after another.
fn screen_picked(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  guard u.picking is Some(p) else { return }
  guard p.files() is Some(files) else { return }
  u.picking = None
  match u.drop_to {
    Some(to) => {
      let n = s.drops_serial
      c.tell("screen-send/" + s.view + "/\{n}", fn() { s.send_files(files, to) })
    }
    None => ()
  }
}

///|
/// Trackpad or direct, said as it is chosen: how a finger drives it now.
fn pad_chosen(c : @ui.Ctx, s : ScreenSess, on : Bool) -> Unit {
  say(c, @sf.t(if on { "android-misc.screen.padOn" } else { "android-misc.screen.padOff" }))
  c.tell("screen-pad/" + s.view, fn() {
    s.choose_pad(s.src, on, screen_act(c, @sf.t("android-misc.screen.touchWhat")))
  })
}

///|
/// 只看 or 控制, chosen.
fn control_chosen(c : @ui.Ctx, s : ScreenSess, on : Bool) -> Unit {
  s.wants_control = Some(on)
  c.tell("screen-control/" + s.view, fn() { s.control(s.src, on) })
}

///|
/// What the keyboard sends (the key catcher's: committed words, named keys and shortcuts as taps), as the screen takes
/// it (Input.kt KeyCatcher), with the modifiers held on the keys row: words typed with one held go as keys with it, a
/// key goes down with them and up with what it went down with.
fn screen_keys_in(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, keys : Array[@ui.KeyIn]) -> Unit {
  if keys.is_empty() {
    return
  }
  let sent : Array[Json] = []
  let send = fn(j : Json) { sent.push(j) }
  for k in keys {
    match k {
      Text(words) => type_words(send, u.held, words)
      // ⌘V (Ctrl+V): this device's clipboard onto the screen's and pasted there, where it carries one, as a paste is
      // on the web's page (its keys are not sent)
      Key(down~, code="KeyV", mods~, ..) if (mods & (mod_meta | mod_ctrl)) != 0 &&
        (mods & mod_alt) == 0 &&
        s.pastes() => if down { paste_asked(c, s, u) }
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
  let n = c.frame_number()
  c.tell("screen-keys/" + s.view + "/\{n}", fn() {
    for j in sent {
      s.input(s.src, j)
    }
  })
}

///|
/// The keyboard up or down (ScreenViewer.kt keyboard()).
fn keyboard_toggled(c : @ui.Ctx, catcher : String, typing : Bool) -> Unit {
  c.catch_keys(catcher, !typing)
}

// ── the bar, the rail, the folded tools ──────────────────────────────────

///|
/// A round button with an icon (40, its icon 20), its name for those who cannot see it; `on`: pressed (the keyboard
/// up, 控制). True when tapped.
fn round_button(c : @ui.Ctx, key : String, icon : String, label : String, on? : Bool = false) -> Bool {
  let id = c.id(key)
  let i = c.box(style=round_button_box, selected=on, id~, fn() {
    @sf.icon(c, icon, size=round_icon, color=c.color(Fg)) |> ignore
  })
  c.semantics(i, Button, id~, label~, pressed=on, actions=[Activate])
  c.clicked(id)
}

///|
/// Upright: close, the title over how the view goes (live: the signal mark and how long it has been seen, pressed its
/// figures) and the core's line (只看 or 控制, who else is on it), 只看/控制, pasting, 控制中心 (sending files and 全屏
/// there).
fn screen_top_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, title : String, close : () -> Unit) -> Unit {
  c.box(style=screen_bar, fn() {
    if !u.in_tab && round_button(c, "screen-close", "close", @sf.t("android-misc.screen.close")) {
      close()
    }
    let live = s.phase() == "live"
    let words = c.id("screen-net")
    let w = c.box(style=screen_bar_words, id=if live { words } else { 0 }, fn() {
      let said = match opt_text(s.state, "title") {
        Some(t) if t != "" => t
        _ => if title != "" { title } else { @sf.t("android-misc.screen.title") }
      }
      c.text(said, style=screen_title_words) |> ignore
      // while another drives it, who does is said below (with 接管), not twice
      let line = text(s.state, "line")
      let said_line = line != "" && s.open_now() && !s.can_take_over()
      if live {
        c.box(style=screen_line_row, fn() {
          signal_bars(c, text(field(screen_net(s), "rtt"), "level"))
          c.text(seen_for(u), style=screen_time_words) |> ignore
          // (short of room, the core's line leaves the row whole before it is cut to a word: how long is kept)
          if said_line {
            c.box(drop=1, fn() { c.text("· " + line, style=screen_line_words) |> ignore }) |> ignore
          }
        })
        |> ignore
      } else if said_line {
        c.text(line, style=screen_line_words) |> ignore
      }
    })
    if live {
      c.semantics(w, Button, id=words, label=@sf.t("web-pages.screen.stats"), actions=[Activate])
      if c.clicked(words) || u.asked_panel == "net" {
        u.asked_panel = ""
        net_panel_open(s, u, Of(words))
      }
    }
    if s.choosable() {
      let now = control_seg(c, "screen-mode/" + s.view, s.controlling())
      if now != s.controlling() {
        control_chosen(c, s, now)
      }
    }
    paste_button(c, s, u)
    // (全屏 in 控制中心: the title keeps its room)
    if s.open_now() {
      center_button(c, s, u, close)
    }
  })
  |> ignore
}

///|
/// With keyboard and mouse: the viewer's bar across the window's top (@sf.viewer_bar, as the web's ViewerBar): back by
/// its name, the screen's name and the core's line (只看 or 控制, who else is on it) in its middle, and its tools: live,
/// how the view goes (pressed, its figures), 控制中心 while it is open, then 只看/控制; while someone else drives it, who
/// does and 接管 in their place.
fn screen_viewer_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, title : String, close : () -> Unit) -> Unit {
  let said = match opt_text(s.state, "title") {
    Some(t) if t != "" => t
    _ => if title != "" { title } else { @sf.t("android-misc.screen.title") }
  }
  let line = if s.open_now() && !s.can_take_over() { text(s.state, "line") } else { "" }
  let ink = @sf.page_viewer_ink()
  let back = @sf.viewer_bar(c, "screen-bar", @sf.t("common.back"), said, line, false, ink, fn() {
    if s.can_take_over() {
      take_over(c, s, in_bar=true)
      return
    }
    if s.phase() == "live" {
      net_chip(c, s, u)
    }
    if s.open_now() {
      center_chip(c, s, u, close)
    }
    if s.choosable() {
      let now = control_seg(c, "screen-mode/" + s.view, s.controlling())
      if now != s.controlling() {
        control_chosen(c, s, now)
      }
    }
  }, capsule_end=true)
  if back {
    close()
  }
}

///|
/// 只看 / 控制 (Parts.kt Seg, 32 high, its corner 16): the choice, as tapped.
fn control_seg(c : @ui.Ctx, key : String, controlling : Bool) -> Bool {
  let items = [
    @kit.item("look", label=@sf.t("android-misc.screen.look")),
    @kit.item("drive", label=@sf.t("android-misc.screen.drive")),
  ]
  let now = @kit.toggle_group(
    c,
    key,
    items,
    [if controlling { "drive" } else { "look" }],
    slide=true,
    look=fn(c, st) {
      c.box(style=seg_item, fn() {
        c.text(st.label, style=if st.on { seg_on_words } else { seg_off_words }) |> ignore
      })
      |> ignore
    },
    thumb=fn(c, w, h) {
      c.box(style=seg_thumb.then(@ui.style(w=Fixed(w), h=Fixed(h))), fn() {  }) |> ignore
    },
    ground=fn(c, _, items) { c.box(style=seg_track, items) |> ignore },
  ).value
  match now {
    ["drive"] => true
    ["look"] => false
    // the chosen one tapped again stays chosen
    _ => controlling
  }
}

///|
/// Pasting the device's clipboard (where the station carries text or pictures), while driving it.
fn paste_button(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.pastes() &&
    round_button(c, "screen-paste", "paste", @sf.t("android-misc.screen.paste"), on=s.pasting) {
    paste_asked(c, s, u)
  }
}

///|
/// 全屏 (on) or not.
fn full_button(c : @ui.Ctx, u : ScreenUi) -> Unit {
  let label = @sf.t(if u.full { "android-misc.screen.unfull" } else { "android-misc.screen.full" })
  if round_button(c, "screen-full", "landscape", label, on=u.full) {
    u.full = !u.full
  }
}

///|
/// Trackpad (on) or direct, as a round button that is on while it is a trackpad.
fn pad_button(c : @ui.Ctx, s : ScreenSess) -> Unit {
  let on = s.pad(s.src)
  if round_button(c, "screen-pad", "trackpad", @sf.t("android-misc.screen.trackpad"), on~) {
    pad_chosen(c, s, !on)
  }
}

///|
/// 只看/控制 as one round button (the rail's, the folded tools'): the pointer while driving, an eye while looking.
fn mode_button(c : @ui.Ctx, s : ScreenSess) -> Unit {
  let on = s.controlling()
  let (icon, label) = if on {
    ("cursor", @sf.t("android-misc.screen.drive"))
  } else {
    ("eye", @sf.t("android-misc.screen.look"))
  }
  if round_button(c, "screen-mode-btn", icon, label, on~) {
    control_chosen(c, s, !on)
  }
}

///|
fn keyboard_button(c : @ui.Ctx, catcher : String, typing : Bool) -> Unit {
  if round_button(c, "screen-keyboard", "keyboard", @sf.t("android-misc.screen.keyboard"), on=typing) {
    keyboard_toggled(c, catcher, typing)
  }
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
  typing : Bool,
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
    if round_button(c, "screen-tools", icon, label, on=u.tools_open) {
      u.tools_open = !u.tools_open
    }
    if u.tools_open {
      if s.choosable() {
        mode_button(c, s)
      }
      if s.driving() {
        pad_button(c, s)
      }
      paste_button(c, s, u)
      if s.driving() {
        keyboard_button(c, catcher, typing)
      }
      center_button(c, s, u, close)
      full_button(c, u)
    }
  })
  |> ignore
  afloat_kept(c, u.tools_moved, capsule, laid_dx, laid_dy)
}

///|
/// Sideways: the same down the side, the line said when the people on it are tapped.
fn screen_rail(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  typing : Bool,
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
      if !u.in_tab && round_button(c, "screen-close", "close", @sf.t("android-misc.screen.close")) {
        close()
      }
      c.spacer()
      if s.state is Some(_) && line != "" && s.open_now() {
        let others = items(s.state, "others").length()
        c.box(style=rail_people, fn() {
          if round_button(c, "screen-people", "users", line, on=u.saying) {
            u.saying = !u.saying
            u.sayings += 1
          }
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
        mode_button(c, s)
      }
      if s.driving() {
        pad_button(c, s)
      }
      paste_button(c, s, u)
      if s.driving() {
        keyboard_button(c, catcher, typing)
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
/// Upright, under the frame while driving it: trackpad or direct, the keys row, the keyboard.
fn foot(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, typing : Bool, catcher : String) -> Unit {
  c.box(style=screen_foot, fn() {
    pad_button(c, s)
    c.box(style=screen_fill_w, fn() { keys_row(c, s, u) }) |> ignore
    keyboard_button(c, catcher, typing)
  })
  |> ignore
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
/// keys (lit while turned; pressed again, back): nothing scrolled, nothing wrapped, nothing over the keyboard.
fn keys_row(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let mouse = mouse_shown(s, u)
  let keys = screen_row_keys().filter(fn(k) { k.button == 0 || mouse })
  let held = fn(k : RowKey) { k.mod_ != 0 && (u.held.mods & k.mod_) != 0 }
  let leaves = fn(k : RowKey) { if held(k) { 0 } else { k.drop } }
  let slot = fn(k : RowKey) { c.id("screen-key-slot/" + s.view + "/" + k.name) }
  let more = c.id("screen-keys-more/" + s.view)
  if c.clicked(more) {
    // (turned to those the first face left out as last laid out: read back, the frame built again where that
    // changes; or back)
    u.keys_turned = if u.keys_turned.is_empty() {
      keys.filter(fn(k) { leaves(k) > 0 && c.left_out(slot(k)) }).map(fn(k) { k.name })
    } else {
      []
    }
  }
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
      button_felt(c, u, id, k.button, c.clicked(id))
    }
    if c.clicked(id) {
      if k.mod_ != 0 {
        u.held.toggle(k.mod_)
      } else if k.button != 0 {
        button_clicked(c, s, u, k.button)
      } else {
        let mods = u.held.take()
        let n = c.frame_number()
        c.tell("screen-row-key/" + s.view + "/\{n}", fn() { stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, mods) })
      }
    }
  }
  let more_key = fn() {
    let i = c.box(style=row_key_box, selected=turned, id=more, fn() {
      @sf.icon(c, "more", size=key_icon, color=c.color(if turned { Bg } else { Fg })) |> ignore
    })
    c.semantics(i, Button, id=more, label=@sf.t("common.more"), pressed=turned, actions=[Activate])
  }
  c.box(style=keys_row_box, fn() {
    if turned {
      for k in keys {
        if u.keys_turned.contains(k.name) {
          key(k)
        }
      }
      more_key()
    } else {
      for k in keys {
        c.box(id=slot(k), taps=false, drop=leaves(k), fn() { key(k) }) |> ignore
      }
      // (the ⋯, there only while a key is out)
      c.box(more=true, fn() { more_key() }) |> ignore
    }
  })
  |> ignore
}

///|
/// Mouse button `button` clicked where the pointer is (the trackpad's, else the screen's own), the modifiers the keys
/// row holds round it.
fn button_clicked(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, button : Int) -> Unit {
  let mods = u.held.take()
  let at = pointer_now(s, u).unwrap_or(u.pad.at())
  let n = c.frame_number()
  c.tell("screen-click/" + s.view + "/\{button}/\{n}", fn() { click(fn(j) { s.input(s.src, j) }, at, button, mods) })
}

///|
/// A mouse button `id` felt as it goes down (the click itself goes as it is let go; a tap down and up between two
/// frames, felt as it is clicked): once a press, the right button as a context click, the left as a key.
fn button_felt(c : @ui.Ctx, u : ScreenUi, id : Int, button : Int, clicked : Bool) -> Unit {
  let p = c.press()
  if !clicked && !(p.down && c.press_within(id)) {
    return
  }
  let at = p.frame
  if u.buzzed != at {
    u.buzzed = at
    let kind : @ui.Haptic = if button == btn_secondary { ContextClick } else { KeyboardTap }
    c.after_build("screen-felt/\{at}", fn() { @ui.haptic(kind) })
  }
}

///|
/// Whether the mouse's buttons show while driving (prefs `screenMouse`, 控制中心's 鼠标左右键): the keys row's two, and
/// their floating pair in 全屏 and sideways.
fn mouse_shown(s : ScreenSess, u : ScreenUi) -> Bool {
  s.driving() &&
  (match u.mouse_set {
    Some(on) => on
    None => text((s.src.topic)("prefs", {}).value, "screenMouse") != "off"
  })
}

///|
/// 左键 and 右键 side by side over the frame's foot corner (全屏 and sideways, the keyboard down: the keys row is not
/// there), each a round button floating on its own, the two dragged anywhere together by either, as the folded tools
/// are.
fn mouse_float(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let capsule = c.id("screen-mouse-capsule")
  let (laid_dx, laid_dy) = (u.mouse_moved.dx, u.mouse_moved.dy)
  c.box(style=screen_corner_end(screen_foot_end), fn() {
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
        let clicked = c.clicked(id)
        button_felt(c, u, id, b.3, clicked)
        if clicked {
          button_clicked(c, s, u, b.3)
        }
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
/// Someone else drives it (an agent at work) and this view only looks: who, and 接管 in one tap (`screen.control` true:
/// their input waits while this person drives; the line then says so).
fn take_over(c : @ui.Ctx, s : ScreenSess, in_bar? : Bool = false) -> Unit {
  let who = items(s.state, "controllers").filter_map(fn(j) {
    match j {
      String(n) => Some(n)
      _ => None
    }
  })
  // a capsule round a 32 high button 6 in from its edge: its corner 6 + 16; in the viewer's bar, a row of its tools
  c.box(style=if in_bar { take_over_bar_row } else { take_over_box }, fn() {
    c.box(style=take_over_dot, fn() {  }) |> ignore
    c.box(style=take_over_words_box, fn() {
      c.text(
        if who.is_empty() {
          @sf.t("android-misc.screen.someoneDrives")
        } else {
          @sf.t("android-misc.screen.drives", args=[("who", who.join(@sf.t("web-main.list.separator")))])
        },
        style=take_over_words,
      )
      |> ignore
    })
    |> ignore
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
    if c.clicked(id) {
      control_chosen(c, s, true)
    }
  })
  |> ignore
}
