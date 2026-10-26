// What an app asks of the host about where it runs (its clock, the system, dark or light, the window's top row, the
// environment, its version), each through the fake host under a Tester: there nothing the app reads comes from the
// machine the test runs on. A Tester sets them (Tester::new's `platform`, `dark`, `window_inset`, `env`,
// `app_version`; Tester::set_dark, set_window_inset, set_env); by default macOS, light, no inset, an empty
// environment, version 0.

///|
/// The host's clock in ms (a Tester's: its frames'). Inside a view, Ctx::now is this frame's; read as a view is built,
/// followed as Ctx::now is (frame_watch.mbt).
pub fn now() -> Double {
  clock_read_here()
  h_now()
}

///|
/// Whether the run is on a clock of its own, not the machine's: its frames', still while the app awaits the host (a
/// picture's run: mac_app.m's settle, MBView's and web/host.js's shot_at; a Tester's). What runs beside the app on a
/// clock of its own (a core's timers) goes on the app's clock there, its timers the runtime's (Runtime::after: seen by
/// Tester::next_wake and Ctx::at_rest); elsewhere on the machine's.
pub fn own_clock() -> Bool {
  match fake.val {
    Some(_) => true
    None => @hostapi.own_clock()
  }
}

///|
/// A frame again `ms` from now (Ctx::wake_in inside a view).
pub fn wake_after(ms : Double) -> Unit {
  h_wake_after(ms)
}

///|
/// A frame as soon as the host can.
pub fn request_frame() -> Unit {
  h_request_frame()
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser, 5 Linux (a Tester's `platform`; a program's over its
/// host's: set_platform).
pub fn platform() -> Int {
  match fake.val {
    Some(_) => h_platform()
    None => if said_platform.val >= 0 { said_platform.val } else { h_platform() }
  }
}

///|
/// The system a program says it plays, over its host's (set_platform); -1: its host's.
// kept across runs: what the program says once as it starts, before any frame
let said_platform : Ref[Int] = Ref(-1)

///|
/// The system this program plays from now on, over its host's (None: its host's again), as a Tester plays its
/// `platform`: a run on one system made as another's (a phone's screens and flows recorded on a Mac: sffix's and the
/// app's MBUI_PLATFORM). What the app reads of the system (platform, and by it the hand's default: pointing) and how its
/// touches and fields feel (feel_as) are that system's; the host's own keys and window stay its own. A Tester's own is
/// over it.
pub fn set_platform(p : Int?) -> Unit {
  said_platform.val = p.unwrap_or(-1)
}

///|
/// What the person points with: a finger on the screen, or a mouse or a trackpad moving a pointer over it.
pub(all) enum Pointing {
  Finger
  Mouse
} derive(Eq, Show, Debug)

///|
/// What the person points with here (a Tester's: its `pointing`, by default its `platform`'s): a finger on a phone's or a tablet's system (iOS,
/// Android), a mouse or a trackpad on a desktop's. The one source of how things answer a person's hand: whether
/// anything is hovered (a finger hovers over nothing: Ctx::hovered, a tooltip, a hover card), how a menu is asked for
/// (Ctx::menu_asked), what shows only to a pointer resting on it, how a press, a drag and Enter work. Never what the
/// window's size or the system's size classes decide (the layout: how many panes, how wide, how large the words);
/// never these by them. Read so: what reads it as it is built is built again as it changes (hand.mbt).
pub fn pointing() -> Pointing {
  hand.pointing.get() |> ignore
  match fake.val {
    Some(f) => f.pointing
    None =>
      match said_pointing.val {
        Some(p) => p
        None =>
          match host_pointing.val {
            Some(p) => p
            None => platform_pointing(platform())
          }
      }
  }
}

///|
/// What the host last said a pointer's event came from (@hostapi.event_finger), on a machine that has both a touch
/// screen and a mouse (Windows'): the hand of the moment from then on. None: nothing said.
// kept across runs: a real host's alone (a Tester's is its fake host's pointing)
let host_pointing : Ref[Pointing?] = Ref(None)

///|
/// A pointer's event said to come from a finger (1) or a mouse or a pen (0): pointing() is that from now on (the fake
/// host's own, under a Tester); -1, nothing said, leaves it.
fn pointing_said_by_host(by : Int) -> Unit {
  if by < 0 {
    return
  }
  let p = if by == 1 { Finger } else { Mouse }
  match fake.val {
    Some(f) => f.pointing = p
    None => host_pointing.val = Some(p)
  }
}

///|
/// What the app was started to be used with (the native input), the same the whole run: a Tester's `native` (by
/// default its system's); else, where a program plays another system (set_platform), that system's; else what the
/// host can tell at launch (@hostapi.native_pointing: a pointer on an iPad, a mouse on Android, a touch screen and no
/// mouse on Windows), its system's where it cannot. Read once, at the first ask. How things answer the hand of the
/// moment is pointing's.
pub fn native_pointing() -> Pointing {
  match fake.val {
    Some(f) => f.native
    None =>
      match native_input_read.val {
        Some(p) => p
        None => {
          let p = if said_platform.val >= 0 {
            platform_pointing(said_platform.val)
          } else {
            match @hostapi.native_pointing() {
              1 => Finger
              2 => Mouse
              _ => platform_pointing(platform())
            }
          }
          native_input_read.val = Some(p)
          p
        }
      }
  }
}

///|
/// The native input as first read (native_pointing).
// kept across runs: read once as the app starts, the same the whole run
let native_input_read : Ref[Pointing?] = Ref(None)

///|
/// The hand a program says it is pointed at with, over its system's (set_pointing); None: its system's.
// kept across runs: what the program says once as it starts, before any frame
let said_pointing : Ref[Pointing?] = Ref(None)

///|
/// The hand this program is pointed at with from now on, over its system's (None: its system's again): a run on one
/// system made as another's (a phone's screens drawn on a Mac, pointed at as a phone is: sffix's MBUI_POINTING). A
/// Tester's own (Tester::new's `pointing`) is over it.
pub fn set_pointing(p : Pointing?) -> Unit {
  said_pointing.val = p
}

///|
/// What a system is pointed at with: a finger on a phone's or a tablet's (iOS, Android), a mouse or a trackpad on a
/// desktop's.
fn platform_pointing(platform : Int) -> Pointing {
  match platform {
    1 | 2 => Finger
    _ => Mouse
  }
}

///|
/// Whether a keyboard is at hand now, part of the current input as pointing is: what says an action's keys (a tip, a
/// menu's row) says them while one is, from the moment one is plugged in to the moment it is taken away; never what
/// is shown otherwise, where or how big. A Tester's `keyboard` (by default its system's); else, where a program plays
/// another system (set_platform), that system's; else the host's as it is asked (@hostapi.keyboard: a Mac's and a
/// PC's always, a phone's or a tablet's while one is connected), its system's where it cannot tell.
pub fn keyboard() -> Bool {
  match fake.val {
    Some(f) => f.keyboard
    None if said_platform.val >= 0 => platform_keyboard(said_platform.val)
    None =>
      match @hostapi.keyboard() {
        1 => true
        0 => false
        _ => platform_keyboard(platform())
      }
  }
}

///|
/// A system's keyboard where nothing tells otherwise: a desktop's, at hand; a phone's or a tablet's (iOS, Android), not.
fn platform_keyboard(platform : Int) -> Bool {
  !(platform == 1 || platform == 2)
}

///|
/// Whether the system is set to dark (a Tester's `dark`).
pub fn system_dark() -> Bool {
  match fake.val {
    Some(f) => f.dark
    None => @hostapi.system_dark()
  }
}

///|
/// How much bigger the system's setting makes words (@hostapi.font_scale; a Tester's `set_font_scale`): what Ctx's words
/// are drawn at, times their size.
pub fn font_scale() -> Double {
  match fake.val {
    Some(f) => f.font_scale
    None => @hostapi.font_scale()
  }
}

///|
/// Whether the window's buttons are in the app's top row now (@hostapi.window_inset; a Tester's `window_inset`).
pub fn window_inset() -> Bool {
  match fake.val {
    Some(f) => f.inset
    None => @hostapi.window_inset()
  }
}

///|
/// Whether the window's buttons in the app's top row are the system's, at its left (macOS: the app leaves them their
/// room there).
pub fn window_keys_left() -> Bool {
  window_inset() && platform() != 3 && platform() != 5
}

///|
/// Whether the window's buttons in the app's top row are the app's to draw, at its right (Windows and Linux: their
/// systems draw none in a window with no title bar of its own): minimize, maximize or back, close
/// (@hostapi.window_act), the maximize one the host's too (window_snap, window_snap_state: Windows').
pub fn window_keys_own() -> Bool {
  window_inset() && (platform() == 3 || platform() == 5)
}

///|
/// Whether the window is maximized now (@hostapi.window_zoomed; a Tester's as set_window_zoomed made it).
pub fn window_zoomed() -> Bool {
  match fake.val {
    Some(f) => f.zoomed
    None => @hostapi.window_zoomed()
  }
}

///|
/// How the pointer stands on the window's maximize button the app draws, which only its host sees (0 not on it, 1 on
/// it, 2 pressing it: @hostapi.window_snap_state; a Tester's as set_window_snap made it).
pub fn window_snap_state() -> Int {
  match fake.val {
    Some(f) => f.snap_state
    None => @hostapi.window_snap_state()
  }
}

///|
/// What the window's own buttons do, asked by the app where it draws them (window_keys_own): 1 minimized, 2 maximized
/// or back as it was, 3 closed.
pub fn window_act(what : Int) -> Unit {
  h_window_act(what)
}

///|
/// Whether the app can open a window of its own beside this one (@hostapi.window_opens; a Tester's as
/// set_window_opens made it).
pub fn window_opens() -> Bool {
  match fake.val {
    Some(f) => f.window_opens
    None => @hostapi.window_opens()
  }
}

///|
/// Another window of the app opened beside this one, for `what` (@hostapi.window_open): whether it was.
pub fn window_open(what : String) -> Bool {
  h_window_open(what)
}

///|
/// Where the app draws the window's maximize button this frame, in points (w 0: none): the host's there
/// (@hostapi.window_snap).
pub fn window_snap(x : Double, y : Double, w : Double, h : Double) -> Unit {
  h_window_snap(x, y, w, h)
}

///|
/// Whether the desktop's window fills the screen now (@hostapi.full_screen; a Tester's as Ctx::set_full_screen last
/// made it).
pub fn full_screen() -> Bool {
  match fake.val {
    Some(f) => f.full
    None => @hostapi.full_screen()
  }
}

///|
/// How round the system draws the window's corners now (@hostapi.window_corner; a Tester's `window_corner`, none while
/// it fills the screen): the outermost container of all (corners.mbt).
pub fn window_corner() -> Double {
  match fake.val {
    Some(f) =>
      if f.full {
        0.0
      } else {
        match f.window_corners {
          Some(k) => k.fold(init=0.0, fn(m, r) { dmax(m, r) })
          None => f.window_corner
        }
      }
    None => @hostapi.window_corner()
  }
}

///|
/// How round the system draws the window's corner `k` (0 top left, then round it: @hostapi.window_corner_at; a
/// Tester's `window_corners`, else its `window_corner`), each its own where they differ (an iPhone Duo's outer screen:
/// 8 along its hinge), window_corner the roundest of them.
pub fn window_corner_at(k : Int) -> Double {
  match fake.val {
    Some(f) =>
      if f.full {
        0.0
      } else {
        match f.window_corners {
          Some(c) => c[k & 3]
          None => f.window_corner
        }
      }
    None => @hostapi.window_corner_at(k)
  }
}

///|
/// The host's environment variable `name`, "" unset (a Tester's `env`).
pub fn env(name : String) -> String {
  h_env(name)
}

///|
fn h_env(name : String) -> String {
  match fake.val {
    Some(f) => f.env.get(name).unwrap_or("")
    None => @hostapi.env(name)
  }
}

///|
/// This build's version code, 0 where the app does not update itself (a Tester's `app_version`).
pub fn app_version() -> Int {
  match fake.val {
    Some(f) => f.app_version
    None => @hostapi.app_version()
  }
}

///|
/// The system set to dark or light from the next frame on.
pub fn Tester::set_dark(self : Tester, dark : Bool) -> Unit {
  self.fake.dark = dark
  self.fake.wants = true
}

///|
/// The system's size of words (as Android's fontScale), from the next frame on.
pub fn Tester::set_font_scale(self : Tester, scale : Double) -> Unit {
  self.fake.font_scale = scale
  self.fake.wants = true
}

///|
/// The window's buttons in the app's top row, or not (full screen), from the next frame on.
pub fn Tester::set_window_inset(self : Tester, inset : Bool) -> Unit {
  self.fake.inset = inset
  self.fake.wants = true
}

///|
/// The environment variable `name` set to `value` ("" unsets it).
pub fn Tester::set_env(self : Tester, name : String, value : String) -> Unit {
  if value == "" {
    self.fake.env.remove(name)
  } else {
    self.fake.env[name] = value
  }
  self.fake.wants = true
}

///|
/// The system lays out the app's tabs and its actions itself from the next frame on, as an iPhone Duo's does
/// (@hostapi.nav_bar_able, nav_bar showing what it is handed), or not.
pub fn Tester::set_nav_able(self : Tester, able : Bool) -> Unit {
  self.fake.nav_able = able
  @hostapi.nav_bar_again()
  self.fake.wants = true
}

///|
/// The bars the app handed the system last (@hostapi.nav_bar's JSON: nav.mbt), "" where it handed none.
pub fn Tester::nav_said(self : Tester) -> String {
  self.fake.nav_said
}

///|
fn nav_able() -> Bool {
  match fake.val {
    Some(f) => f.nav_able
    None => false
  }
}

///|
fn nav_bar_said(spec : String) -> Int {
  match fake.val {
    Some(f) => {
      f.nav_said = spec
      if f.nav_able { 1 } else { 0 }
    }
    None => 0
  }
}
