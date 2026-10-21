// A station's screen, full screen (ember apps/android app/remote/ScreenViewer.kt, ScreenActivity.kt;
// docs/remote-screens.md): the frame fitted whole (letterboxed), zoomed in place with two fingers; while driving it, a
// tap clicks, a long press right-clicks, a drag drags, two fingers moving together scroll, and the keyboard types into
// it. Upright, the bar is above the frame (close, the title and who is on it, 只看/控制, sending a file, pasting, 全屏);
// sideways, a rail beside it; 全屏, the screen alone, sideways, its tools folded into one button over the frame's
// corner. While driving it, a copy made on the screen (text or a picture) lands on the device's clipboard, the
// device's clipboard is pasted into it, and files picked go onto its machine (how far they have got, then where they
// are, over the frame's foot). How the view is (connecting, reconnecting, ended…) is the core's: on its way, said over
// the frame as it was last shown; over (ended, gone…), said in the screen's place, gone dark. While it is in sight the
// device stays awake; out of sight the view is let go of, and opened again from the frame it showed.

///|
/// What the viewer keeps of a view beside the session: the frame's zoom, the trackpad's pointer, the modifiers held,
/// 全屏 and its folded tools, the rail's line said, the press under way.
priv struct ScreenUi {
  zoom : ViewZoom
  pad : PadPointer
  held : HeldKeys
  mut full : Bool
  mut tools_open : Bool
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
  /// the picker asked for files, and where they go (as the state said when it was asked for)
  mut picking : @ui.Pick?
  mut drop_to : DropTo?
  /// a read of the device's clipboard under way, for a paste
  mut reading : @ui.ClipboardRead?
  /// the modifiers held from the keys row as each key went down (by its code), for it to go up with them too
  down_with : Map[String, Int]
  /// the copies made on the screen put on the device's clipboard
  mut copies : Int
  /// the device kept awake, the window sideways: as last told to the host
  mut awake : Bool
  mut sideways_told : Bool
}

///|
let screen_uis : Map[String, ScreenUi] = Map([])

///|
fn screen_ui(key : String) -> ScreenUi {
  match screen_uis.get(key) {
    Some(u) => u
    None => {
      let u : ScreenUi = {
        zoom: { scale: 1.0, x: 0.0, y: 0.0 },
        pad: { x: 0.5, y: 0.5, moves: 0 },
        held: { mods: 0 },
        full: false,
        tools_open: false,
        saying: false,
        sayings: 0,
        box_w: 0.0,
        box_h: 0.0,
        stage_x: 0.0,
        stage_y: 0.0,
        fit_for: None,
        over_seen: false,
        gesture: gesture_new(),
        picking: None,
        drop_to: None,
        reading: None,
        down_with: {},
        copies: 0,
        awake: false,
        sideways_told: false,
      }
      screen_uis[key] = u
      u
    }
  }
}

///|
/// The phases a view is over in (said in the screen's place, gone dark).
fn phase_over(p : String) -> Bool {
  p == "ended" || p == "outdated" || p == "gone" || p == "denied" || p == "failed"
}

///|
/// How long the rail's line stays said once asked for (ScreenViewer.kt Rail: 3000).
let rail_say_ms : Double = 3000.0

///|
/// The viewer of `screen` on `station` (ScreenViewer): `title` until the core says one (the link's own, or the row's it
/// was opened from).
fn screen_page(c : @ui.Ctx, src : Source, station : String, screen : String, title : String) -> Unit {
  let key = screen_key(station, screen)
  let s = screen_sess(src, station, screen)
  let u = screen_ui(key)
  // open while the app is in sight (ScreenActivity onStart / onStop): the last frame kept between
  let shown = @ui.app_visible()
  c.after_build("screen-open/" + key, fn() {
    s.own_stream()
    if shown {
      s.open(src)
    } else {
      s.pause(src)
    }
    // while it is looked at, the device stays awake: a screen is watched more than touched
    if u.awake != shown {
      u.awake = shown
      @ui.keep_awake(shown)
    }
  })
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
  // inside the bars unless full (ScreenViewer.kt: windowInsetsPadding(safeDrawing); full, edge to edge)
  within_bars(c, top=!u.full, foot=!u.full, ground=if u.full { bars_fill } else { screen_page_box }, fn() { c.box(style=if u.full { screen_page_full } else { screen_page_box }, fn() {
    if u.full {
      c.box(style=screen_fill, fn() {
        screen_stage(c, s, u, key)
        if s.can_take_over() {
          c.layer(fn() { c.box(style=screen_top_center, fn() { take_over(c, s) }) |> ignore }) |> ignore
        }
        if s.driving() && typing {
          c.layer(fn() { c.box(style=screen_foot_center, fn() { keys_capsule(c, s, u) }) |> ignore })
          |> ignore
        }
        c.layer(fn() {
          c.box(style=screen_top_end, fn() { full_tools(c, s, u, typing, catcher) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    } else if sideways {
      c.box(style=screen_row, fn() {
        screen_rail(c, s, u, typing, catcher)
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
      screen_top_bar(c, s, u, title)
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
  |> ignore })
}

///|
/// The view's page gone: the view, its decoder and its files let go of; upright and asleep again.
fn screen_left(src : Source, station : String, screen : String) -> Unit {
  let key = screen_key(station, screen)
  match screens_open.get(key) {
    Some(s) => s.close(src)
    None => ()
  }
  match screen_uis.get(key) {
    Some(u) => {
      if u.sideways_told {
        @hostapi.set_sideways(false)
      }
      if u.awake {
        @ui.keep_awake(false)
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
      Err(e) => say(c, fill("android-misc.act.failed", [("what", what), ("error", error_words(e))]))
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
            say(c, tr("android-misc.screen.copied"))
          }
        }
        // only from a screen that says it carries pictures (a station from before them sends none)
        CopiedPng(b) =>
          if types.contains("png") {
            @ui.clipboard_set_png(b, label~)
            if !@ui.copy_shown() {
              say(c, tr("android-misc.screen.copiedImage"))
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
  let what = tr("android-misc.screen.pasteWhat")
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
          say(c, tr("android-misc.screen.imageTooLarge"))
        }
        _ => {
          s.pasting = false
          say(c, tr("android-misc.screen.imageUnread"))
        }
      }
    "text" => c.tell("screen-paste/" + s.view, fn() { s.paste(s.src, words, done) })
    "no-images" => {
      s.pasting = false
      say(c, tr("android-misc.screen.noImages"))
    }
    "no-text" => {
      s.pasting = false
      say(c, tr("android-misc.screen.noText"))
    }
    _ => {
      s.pasting = false
      say(c, tr("android-misc.screen.clipboardEmpty"))
    }
  }
}

///|
/// 粘贴手机剪贴板 tapped: the device's clipboard read (the system answers; screen_pasted takes it).
fn paste_asked(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.pasting {
    return
  }
  match @ui.clipboard_read() {
    Some(r) => {
      s.pasting = true
      u.reading = Some(r)
    }
    None => say(c, tr("android-misc.screen.clipboardEmpty"))
  }
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
    None => say(c, "这个版本在这台设备上还不能选文件")
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
  say(c, tr(if on { "android-misc.screen.padOn" } else { "android-misc.screen.padOff" }))
  c.tell("screen-pad/" + s.view, fn() {
    s.choose_pad(s.src, on, screen_act(c, tr("android-misc.screen.touchWhat")))
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
/// Upright: close, the title over the core's line (只看 or 控制, who else is on it), 只看/控制, the clipboard and files,
/// 全屏.
fn screen_top_bar(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, title : String) -> Unit {
  c.box(style=screen_bar, fn() {
    if round_button(c, "screen-close", "close", tr("android-misc.screen.close")) {
      app.nav.pop() |> ignore
    }
    c.box(style=screen_bar_words, fn() {
      let said = match opt_text(s.state, "title") {
        Some(t) if t != "" => t
        _ => if title != "" { title } else { tr("android-misc.screen.title") }
      }
      c.text(said, style=screen_title_words) |> ignore
      // while another drives it, who does is said below (with 接管), not twice
      let line = text(s.state, "line")
      if line != "" && s.open_now() && !s.can_take_over() {
        c.text(line, style=screen_line_words) |> ignore
      }
    })
    |> ignore
    if s.choosable() {
      let now = control_seg(c, "screen-mode/" + s.view, s.controlling())
      if now != s.controlling() {
        control_chosen(c, s, now)
      }
    }
    clip_buttons(c, s, u)
    if s.open_now() {
      full_button(c, u)
    }
  })
  |> ignore
}

///|
/// 只看 / 控制 (Parts.kt Seg, 32 high, its corner 16): the choice, as tapped.
fn control_seg(c : @ui.Ctx, key : String, controlling : Bool) -> Bool {
  let items = [
    @kit.item("look", label=tr("android-misc.screen.look")),
    @kit.item("drive", label=tr("android-misc.screen.drive")),
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
/// Sending a file (where the station takes them) and pasting (where it carries text or pictures), while driving it.
fn clip_buttons(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.drops_to() is Some(_) &&
    round_button(c, "screen-send", "upload", tr("android-misc.screen.sendFile")) {
    send_asked(c, s, u)
  }
  if s.pastes() &&
    round_button(c, "screen-paste", "paste", tr("android-misc.screen.paste"), on=s.pasting) {
    paste_asked(c, s, u)
  }
}

///|
/// 全屏 (on) or not.
fn full_button(c : @ui.Ctx, u : ScreenUi) -> Unit {
  let label = tr(if u.full { "android-misc.screen.unfull" } else { "android-misc.screen.full" })
  if round_button(c, "screen-full", "landscape", label, on=u.full) {
    u.full = !u.full
  }
}

///|
/// Trackpad (on) or direct, as a round button that is on while it is a trackpad.
fn pad_button(c : @ui.Ctx, s : ScreenSess) -> Unit {
  let on = s.pad(s.src)
  if round_button(c, "screen-pad", "trackpad", tr("android-misc.screen.trackpad"), on~) {
    pad_chosen(c, s, !on)
  }
}

///|
/// 只看/控制 as one round button (the rail's, the folded tools'): the pointer while driving, an eye while looking.
fn mode_button(c : @ui.Ctx, s : ScreenSess) -> Unit {
  let on = s.controlling()
  let (icon, label) = if on {
    ("cursor", tr("android-misc.screen.drive"))
  } else {
    ("eye", tr("android-misc.screen.look"))
  }
  if round_button(c, "screen-mode-btn", icon, label, on~) {
    control_chosen(c, s, !on)
  }
}

///|
fn keyboard_button(c : @ui.Ctx, catcher : String, typing : Bool) -> Unit {
  if round_button(c, "screen-keyboard", "keyboard", tr("android-misc.screen.keyboard"), on=typing) {
    keyboard_toggled(c, catcher, typing)
  }
}

///|
/// 全屏's tools, folded into one round button over the frame's corner (in the letterbox, as a screen wider than the
/// device leaves one): open, the same as the rail's down from it — 只看/控制, trackpad, the clipboard and files, the
/// keyboard, 退出全屏.
fn full_tools(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, typing : Bool, catcher : String) -> Unit {
  // a round button 4 in from the capsule's edge: its corner 20 + 4
  c.box(style=full_tools_box, fn() {
    let (icon, label) = if u.tools_open {
      ("close", tr("android-misc.screen.toolsClose"))
    } else {
      ("more", tr("android-misc.screen.tools"))
    }
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
      clip_buttons(c, s, u)
      if s.driving() {
        keyboard_button(c, catcher, typing)
      }
      full_button(c, u)
    }
  })
  |> ignore
}

///|
/// Sideways: the same down the side, the line said when the people on it are tapped.
fn screen_rail(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, typing : Bool, catcher : String) -> Unit {
  // said for 3 s once asked for
  if u.saying && @kit.after(c, "screen-saying/\{u.sayings}", true, rail_say_ms) {
    u.saying = false
  }
  let line = text(s.state, "line")
  c.box(fn() {
    c.box(style=rail_box, fn() {
      if round_button(c, "screen-close", "close", tr("android-misc.screen.close")) {
        app.nav.pop() |> ignore
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
      clip_buttons(c, s, u)
      if s.driving() {
        keyboard_button(c, catcher, typing)
      }
      if s.open_now() {
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
}

///|
fn screen_row_keys() -> Array[RowKey] {
  let k = fn(label, name, key, code, mod_, icon) -> RowKey { { label, name, key, code, mod_, icon } }
  [
    k("Esc", "Esc", "Escape", "Escape", 0, ""),
    k("Tab", "Tab", "Tab", "Tab", 0, ""),
    k("⌘", tr("android-misc.screen.key.command"), "", "", mod_meta, ""),
    k("⌃", tr("android-misc.screen.key.control"), "", "", mod_ctrl, ""),
    k("⌥", tr("android-misc.screen.key.option"), "", "", mod_alt, ""),
    k("⇧", tr("android-misc.screen.key.shift"), "", "", mod_shift, ""),
    k("", tr("android-misc.screen.key.left"), "ArrowLeft", "ArrowLeft", 0, "arrow-left"),
    k("", tr("android-misc.screen.key.up"), "ArrowUp", "ArrowUp", 0, "arrow-up"),
    k("", tr("android-misc.screen.key.down"), "ArrowDown", "ArrowDown", 0, "arrow-down"),
    k("", tr("android-misc.screen.key.right"), "ArrowRight", "ArrowRight", 0, "arrow-right"),
  ]
}

///|
/// The keys a phone's keyboard has not (Esc, Tab, the arrows) and the modifiers (⌘ ⌃ ⌥ ⇧: held, shown solid, for the
/// next key, typed or here), in a row that scrolls when it is wider than its room.
fn keys_row(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  c.sideways("screen-keys-row/" + s.view, fn() {
    c.box(style=keys_row_box, fn() {
      for k in screen_row_keys() {
        let on = k.mod_ != 0 && (u.held.mods & k.mod_) != 0
        let id = c.id("screen-key/" + k.name)
        let i = c.box(style=row_key_box, selected=on, id~, fn() {
          if k.icon != "" {
            @sf.icon(c, k.icon, size=key_icon, color=c.color(Fg)) |> ignore
          } else {
            c.text(k.label, style=if on { row_key_on_words } else { row_key_words }) |> ignore
          }
        })
        c.semantics(i, Button, id~, label=k.name, pressed=on, actions=[Activate])
        if c.clicked(id) {
          if k.mod_ != 0 {
            u.held.toggle(k.mod_)
          } else {
            let mods = u.held.take()
            let n = c.frame_number()
            c.tell("screen-row-key/" + s.view + "/\{n}", fn() {
              stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, mods)
            })
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The keys row floating over the frame's foot (sideways and 全屏, while the keyboard is up).
fn keys_capsule(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  c.box(style=keys_capsule_box, fn() { keys_row(c, s, u) }) |> ignore
}

///|
/// Someone else drives it (an agent at work) and this view only looks: who, and 接管 in one tap (`screen.control` true:
/// their input waits while this person drives; the line then says so).
fn take_over(c : @ui.Ctx, s : ScreenSess) -> Unit {
  let who = items(s.state, "controllers").filter_map(fn(j) {
    match j {
      String(n) => Some(n)
      _ => None
    }
  })
  // a capsule round a 32 high button 6 in from its edge: its corner 6 + 16
  c.box(style=take_over_box, fn() {
    c.box(style=take_over_dot, fn() {  }) |> ignore
    c.box(style=take_over_words_box, fn() {
      c.text(
        if who.is_empty() {
          tr("android-misc.screen.someoneDrives")
        } else {
          fill("android-misc.screen.drives", [("who", who.join("、"))])
        },
        style=take_over_words,
      )
      |> ignore
    })
    |> ignore
    // the main solid button, as the web's primary (dark in the light theme, light in the dark one), not the accent
    let id = c.id("screen-take-over")
    let i = c.box(style=take_over_button, id~, fn() {
      c.text(tr("android-misc.screen.takeOver"), style=take_over_button_words) |> ignore
    })
    c.semantics(i, Button, id~, label=tr("android-misc.screen.takeOver"), actions=[Activate])
    if c.clicked(id) {
      control_chosen(c, s, true)
    }
  })
  |> ignore
}
