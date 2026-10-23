// What an app asks of the host about where it runs (its clock, the system, dark or light, the window's top row, the
// environment, its version), each through the fake host under a Tester: there nothing the app reads comes from the
// machine the test runs on. A Tester sets them (Tester::new's `platform`, `dark`, `window_inset`, `env`,
// `app_version`; Tester::set_dark, set_window_inset, set_env); by default macOS, light, no inset, an empty
// environment, version 0.

///|
/// The host's clock in ms (a Tester's: its frames'). Inside a view, Ctx::now is this frame's.
pub fn now() -> Double {
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
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser (a Tester's `platform`).
pub fn platform() -> Int {
  h_platform()
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
/// Whether the desktop's window fills the screen now (@hostapi.full_screen; a Tester's as Ctx::set_full_screen last
/// made it).
pub fn full_screen() -> Bool {
  match fake.val {
    Some(f) => f.full
    None => @hostapi.full_screen()
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
