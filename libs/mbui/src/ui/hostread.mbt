// What an app asks of the host about where it runs (whether its clock is its own, the system, dark or light, the window's top row, the
// environment, its version), each through the fake host under a Tester: there nothing the app reads comes from the
// machine the test runs on. A Tester sets them (Tester::new's `platform`, `dark`, `window_inset`, `env`,
// `app_version`; Tester::set_dark, set_window_inset, set_env); by default macOS, light, no inset, an empty
// environment, version 0.

///|
/// Whether the run is on a clock of its own, not the machine's: its frames', still while the app awaits the host (a
/// picture's run: mac_app.m's settle, MBView's and web/host.js's shot_at; a Tester's). What runs beside the app on a
/// clock of its own (a core's timers) goes on the app's clock there, its timers the runtime's (Runtime::after: seen by
/// Tester::next_wake and Ctx::at_rest); elsewhere on the machine's.
pub fn own_clock() -> Bool {
  @hostapi.own_clock()
}

///|
/// A frame again `ms` from now (Ctx::wake_in inside a view).
pub fn wake_after(ms : Double) -> Unit {
  h_wake_after(ms)
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser, 5 Linux (a Tester's `platform`; a program's over its
/// host's: set_platform).
pub fn platform() -> Int {
  if said_platform.val >= 0 {
    said_platform.val
  } else {
    h_platform()
  }
}

///|
/// The system whose keys the person types with, as `platform` numbers them: its field's moves (⌥← a word on Apple's,
/// Ctrl+← elsewhere), undo, the command key of shortcuts (⌘ on Apple's, Ctrl elsewhere). The host's own system, but a
/// browser's the one under it (a page on a Mac types as a Mac); a Tester's the system it plays.
pub fn keys_system() -> Int {
  h_keys()
}

///|
/// The system a program says it plays, over its host's (set_platform); -1: its host's.
// kept across runs: what the program says once as it starts, before any frame
let said_platform : Ref[Int] = Ref(-1)

///|
/// The system this program plays from now on, over its host's (None: its host's again), as a Tester plays its
/// `platform`: a run on one system made as another's (a phone's screens and flows recorded on a Mac: sffix's and the
/// app's MBUI_PLATFORM). What the app reads of the system (platform, and by it the hand's default: pointing) and how its
/// touches and fields feel (feel_as) are that system's; the host's own keys and window stay its own. A program's, said
/// as it starts (a Tester's own is Tester::new's `platform`).
pub fn set_platform(p : Int?) -> Unit {
  said_platform.val = p.unwrap_or(-1)
}

///|
/// What the person points with: a finger on the screen, or a mouse or a trackpad moving a pointer over it.
#derive(Eq, Debug)
pub(all) enum Pointing {
  Finger
  Mouse
}

///|
/// What the person points with here (a Tester's: its `pointing`, by default its `platform`'s): a finger on a phone's or a tablet's system (iOS,
/// Android), a mouse or a trackpad on a desktop's. The one source of how things answer a person's hand: whether
/// anything is hovered (a finger hovers over nothing: Ctx::hovered, a tooltip, a hover card), how a menu is asked for
/// (Ctx::menu_asked), what shows only to a pointer resting on it, how a press, a drag and Enter work. Never what the
/// window's size or the system's size classes decide (the layout: how many panes, how wide, how large the words);
/// never these by them. Read so: what reads it as it is built is built again as it changes (hand.mbt).
pub fn pointing() -> Pointing {
  hand.pointing.get() |> ignore
  match said_pointing.val {
    Some(p) => p
    None =>
      match host_pointing.val {
        Some(p) => p
        None =>
          match @hostapi.pointing() {
            1 => Finger
            0 => Mouse
            _ => platform_pointing(platform())
          }
      }
  }
}

///|
/// What the host last said a pointer's event came from (@hostapi.event_finger), on a machine that has both a touch
/// screen and a mouse (Windows'): the hand of the moment from then on. None: nothing said.
// kept across runs: put back by each Tester (reset_globals)
let host_pointing : Ref[Pointing?] = Ref(None)

///|
/// A pointer's event said to come from a finger (1) or a mouse or a pen (0): pointing() is that from now on; -1,
/// nothing said, leaves it.
fn pointing_said_by_host(by : Int) -> Unit {
  if by < 0 {
    return
  }
  host_pointing.val = Some(if by == 1 { Finger } else { Mouse })
  // (told now, as the event it came with is taken: what reads the hand of the moment (pointing) follows it from this
  // event on, not from the next frame's)
  let now = @signals.untracked(fn() { pointing() })
  if hand.pointing.untracked() != now {
    hand.pointing.set(now)
  }
}

///|
/// What the app was started to be used with (the native input), the same the whole run: where a program plays another
/// system (set_platform), that system's; else what the host can tell at launch (@hostapi.native_pointing: a pointer
/// on an iPad, a mouse on Android, a touch screen and no mouse on Windows; a Tester's `native`), its system's where it
/// cannot. How things answer the hand of the moment is pointing's.
pub fn native_pointing() -> Pointing {
  if said_platform.val >= 0 {
    return platform_pointing(said_platform.val)
  }
  match @hostapi.native_pointing() {
    1 => Finger
    2 => Mouse
    _ => platform_pointing(platform())
  }
}

///|
/// The hand a program says it is pointed at with, over its system's (set_pointing); None: its system's.
// kept across runs: what the program says once as it starts, before any frame
let said_pointing : Ref[Pointing?] = Ref(None)

///|
/// The hand this program is pointed at with from now on, over its system's (None: its system's again): a run on one
/// system made as another's (a phone's screens drawn on a Mac, pointed at as a phone is: sffix's MBUI_POINTING): a
/// program's, said as it starts (a Tester's own is Tester::new's `pointing`).
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
/// is shown otherwise, where or how big. Where a program plays another system (set_platform), that system's; else the
/// host's as it is asked (@hostapi.keyboard: a Mac's and a PC's always, a phone's or a tablet's while one is
/// connected; a Tester's `keyboard`), its system's where it cannot tell.
pub fn keyboard() -> Bool {
  if said_platform.val >= 0 {
    return platform_keyboard(said_platform.val)
  }
  match @hostapi.keyboard() {
    1 => true
    0 => false
    _ => platform_keyboard(platform())
  }
}

///|
/// A system's keyboard where nothing tells otherwise: a desktop's, at hand; a phone's or a tablet's (iOS, Android), not.
fn platform_keyboard(platform : Int) -> Bool {
  !(platform == 1 || platform == 2)
}

///|
/// Whether the system is set to dark (a Tester's `dark`), as the frame has it, followed (host_said.mbt).
pub fn system_dark() -> Bool {
  dark_said.now()
}

///|
/// How much bigger the system's setting makes words (@hostapi.font_scale; a Tester's `set_font_scale`): what Ctx's words
/// are drawn at, times their size; as the frame has it, followed (host_said.mbt).
pub fn font_scale() -> Double {
  words_size_said.now()
}

///|
/// Whether the window's buttons are in the app's top row now (@hostapi.window_inset; a Tester's `window_inset`), as
/// the frame has it, followed (host_said.mbt): what read it is built again as it changes (a Mac's window going full
/// screen and back), a list's row or a part kept as its nodes too.
pub fn window_inset() -> Bool {
  inset_said.now()
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
/// Whether the window is maximized now (@hostapi.window_zoomed; a Tester's as set_window_zoomed made it), as the frame
/// has it, followed (host_said.mbt): what read it is built again as it changes.
pub fn window_zoomed() -> Bool {
  zoomed_said.now()
}

///|
/// How the pointer stands on the window's maximize button the app draws, which only its host sees (0 not on it, 1 on
/// it, 2 pressing it: @hostapi.window_snap_state; a Tester's as set_window_snap made it), as the frame has it, followed
/// (host_said.mbt): what read it is built again as it changes (the button lit and held as the host says, not when
/// something else builds it again).
pub fn window_snap_state() -> Int {
  snap_said.now()
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
  @hostapi.window_opens()
}

///|
/// Another window of the app opened beside this one, for `what` (@hostapi.window_open): whether it was.
pub fn window_open(what : String) -> Bool {
  h_window_open(what)
}

///|
/// The window opened for `what` brought to the front (@hostapi.window_front): whether there is one still open.
pub fn window_front(what : String) -> Bool {
  h_window_front(what)
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
  @hostapi.full_screen()
}

///|
/// How round the system draws the window's corners now (@hostapi.window_corner; a Tester's `window_corner`, none while
/// it fills the screen): the outermost container of all (corners.mbt).
pub fn window_corner() -> Double {
  @hostapi.window_corner() / window_zoom_drawn.val
}

///|
/// How round the system draws the window's corner `k` (0 top left, then round it: @hostapi.window_corner_at; a
/// Tester's `window_corners`, else its `window_corner`), each its own where they differ (an iPhone Duo's outer screen:
/// 8 along its hinge), window_corner the roundest of them.
pub fn window_corner_at(k : Int) -> Double {
  @hostapi.window_corner_at(k) / window_zoom_drawn.val
}

///|
/// The host's environment variable `name`, "" unset (a Tester's `env`).
pub fn env(name : String) -> String {
  h_env(name)
}

///|
fn h_env(name : String) -> String {
  @hostapi.env(name)
}

///|
/// This build's version code, 0 where the app does not update itself (a Tester's `app_version`).
pub fn app_version() -> Int {
  @hostapi.app_version()
}

///|
/// What has said the host's settings are the run's, given before its first frame (an app's replay of a recorded run:
/// its trace's `{"settings":…}`), "" none: a Tester's setter of one of them after that stops, saying where it goes.
// kept across runs: put back by each Tester (Tester::new)
let host_settings_given : Ref[String] = Ref("")

///|
/// The host's settings (dark, the size of words, the window's buttons in its top row, maximized, motion and
/// transparency reduced, something reading the widgets out) are `by`'s from here on, given before the first frame: a
/// setter of them after this stops (`Time is declared`: a run's host's settings are its trace's, not a test's change
/// after it started, whose frame would fall where the frames happen to).
pub fn Tester::host_settings_from(self : Tester, by : String) -> Unit {
  ignore(self)
  host_settings_given.val = by
}

///|
fn host_setting_set(what : String) -> Unit {
  if host_settings_given.val != "" {
    @halt.saying(
      "Tester::\{what} after the run started: the host's settings are \{host_settings_given.val}'s, given before its first frame; say it there",
    )
  }
}

///|
/// The system set to dark or light from the next frame on.
pub fn Tester::set_dark(self : Tester, dark : Bool) -> Unit {
  host_setting_set("set_dark")
  self.fake.dark = dark
  self.fake.wants = true
}

///|
/// The system's size of words (as Android's fontScale), from the next frame on.
pub fn Tester::set_font_scale(self : Tester, scale : Double) -> Unit {
  host_setting_set("set_font_scale")
  self.fake.font_scale = scale
  self.fake.wants = true
}

///|
/// How far its local time is ahead of UTC, in minutes, from the next frame on (a run's, as its trace says it).
pub fn Tester::set_utc_offset(self : Tester, minutes : Int) -> Unit {
  self.fake.utc_offset = minutes
  self.fake.wants = true
}

///|
/// How much lower than centred on the app's top row's first 44 the app last moved the window's buttons, and over how
/// many ms (@hostapi.window_buttons_down).
pub fn Tester::window_buttons_down(self : Tester) -> (Double, Double) {
  self.fake.buttons_down
}

///|
/// The window's buttons in the app's top row, or not (full screen), from the next frame on.
pub fn Tester::set_window_inset(self : Tester, inset : Bool) -> Unit {
  host_setting_set("set_window_inset")
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
  // (what is read of it once read anew: reduced_motion)
  reduce_env.val = -1
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
