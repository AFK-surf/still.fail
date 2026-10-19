// Scripted runs over the app's own screen (MBUI_DRIVE, or MBUI_DRIVE_B64 as base64): a script of steps, one a line,
// run frame by frame on any host, finding what to tap by its words on screen and waiting on what should come there,
// for end-to-end runs against a live backend (scripts/e2e-local.sh, e2e/flows). Input goes the way the system sends
// it where the host has that way (@host.drive: on macOS the input method's calls and Cmd+V, on Android the view's
// InputConnection and KEYCODE_PASTE); else straight to the app's handlers.
//
//   # a comment                 wait MS                   timeout MS (for until/gone/field after it; 20000 to start)
//   until TEXT                  words containing TEXT on screen (a text, rich text, a field's placeholder, or
//                               icon:NAME, an @sf icon; img:NAME an image whose source has NAME in it), within the
//                               timeout; else the run fails
//                               (=TEXT: words that are TEXT exactly)
//   untiln N TEXT               N or more of them on screen
//   gone TEXT                   no longer on screen
//   field TEXT                  a field's words contain TEXT (\n a new line)     empty   the focused field is empty
//   clear                       the focused field emptied (all selected, deleted)
//   tap TEXT                    taps the lowest TEXT on screen (in a chat, the newest), once there (within the
//                               timeout) and holding still; tap1 TEXT the highest
//   tapxy X Y                   taps there (negative: from the right, the bottom)
//   hold MS TEXT                pressed on TEXT for MS, then let go (a long press)
//   type TEXT                   committed by the input method      mark TEXT    composed (not yet committed)
//   enter                       backspace                 back       the system's back
//   paste TEXT                  TEXT on the clipboard, then the system's paste
//   pasten N TEXT               TEXT repeated to N characters, pasted
//   wheel DY                    the list under the middle of the window scrolled by DY
//   wheelat DY TEXT             the list under the lowest TEXT scrolled by DY, a mouse wheel's notches (eased in)
//   move X Y                    the pointer moved there, no button down (negative: from the right, the bottom)
//   hover TEXT                  the pointer moved onto the lowest TEXT, once it holds still
//   rightclick TEXT             a secondary click (a context menu's) on the lowest TEXT, once it holds still
//   key NAME                    a key, with what is held before it: esc, tab, enter, space, up, down, left, right,
//                               home, end, pageup, pagedown, backspace, a character; cmd+ (⌘ on macOS, Ctrl
//                               elsewhere), ctrl+, alt+, shift+ (cmd+k, shift+enter, alt+down)
//   resize W H                  the window's content resized to W by H (the host's own window, where it can)
//   drag X Y DX DY [MS]         a finger down at X Y (negative: from the right, the bottom), moved by DX DY over MS
//                               (300 by default), a move a frame, then lifted there
//   dragon DX DY MS TEXT        the same from the lowest TEXT on screen, once it holds still
//   shot NAME                   the window's picture, once settled, as $MBUI_SHOT_DIR/NAME.png (where the host cannot,
//                               "SHOT NAME" is logged and the run waits 1.5 s for whoever takes it: adb's screencap)
//   noticed TEXT                one of the app's notifications (the system's, @host.notice_show) holds TEXT in its
//                               title or words, within the timeout       nonotice TEXT   none does
//   notice TEXT                 that notification, once there, tapped (as the system's shade sends the tap)
//   log TEXT                    DRIVE LOG TEXT on the log (a mark for whoever watches it)
//   exit                        ends the run: DRIVE PASS, exit 0
//   linger MS                   the run passed (DRIVE PASS said now), the app left running MS more for what the last
//                               step set off (a share sheet, a download): a check beside the run looks at it
//   now STEP                    STEP as soon as it is due, the app settled or not (below): what is looked at or done
//                               while something still moves (a tap on what a sheet going down only draws, a shot of
//                               it on its way; after a `wait` into the motion)
// A step that looks at the screen or acts on it (until, untiln, gone, field, empty, clear, tap, tap1, tapxy, hold,
// type, mark, enter, backspace, back, paste, pasten, wheel, wheelat, move, hover, rightclick, key, resize, drag,
// dragon, shot; exit and the script's end too) first waits, within its timeout, for the app to be settled
// (Ctx::settled: the frame just drawn asks for no other, nothing is awaited from the host — an image decoding, a page
// loading — or, where the app says so, from its core, and no timer or wake is set that is not `later`), so that a
// page sliding in, a sheet opening, a list scrolling or a picture coming needs no `wait`; a check holds once it is so
// at a settled frame. One the app never settles for fails, saying why (Ctx::unsettled: what is awaited since when,
// who asked for a frame or a wake); one waiting more than a second says so on the log (DRIVE waiting …). `wait`
// stays a pause in real time, for what is outside the app (a command beside the run, the other device, the station)
// that no `until` can see, or for a point inside a motion (then `now` steps).
// A step that fails logs DRIVE FAIL (its line, what was on screen), takes a shot "fail" and exits 1.

///|
priv struct Driver {
  steps : Array[String]
  mut at : Int
  mut since : Double
  mut timeout : Double
  mut release_at : Double
  mut rx : Double
  mut ry : Double
  // where a tap's target was last frame: it is tapped once it holds still (not while a list or a page still moves it)
  mut seen_x : Double
  mut seen_y : Double
  // a drag under way (drag, dragon): where it went down, how far it goes, since when, over how long (0: none)
  mut gx : Double
  mut gy : Double
  mut gdx : Double
  mut gdy : Double
  mut gt0 : Double
  mut gms : Double
  // when a shot the host cannot take was asked for (logged "SHOT NAME": whoever takes it has 1.5 s), -1 before
  mut shot_at : Double
  // frames in a row the app was settled at; whether this step's waiting for it was told (on the log, after a second)
  mut calm : Int
  /// whether steps first wait for the app to be settled (a host's run: MBUI_DRIVE_SETTLED=1; under the Tester, yes)
  settles : Bool
  mut told : Bool
  dir : String
}

///|
let driver : Ref[Driver?] = { val: None }

///|
/// Reads the script from the environment, once, as the window opens.
fn drive_init() -> Unit {
  let script = @host.env_text("MBUI_DRIVE")
  if script != "" {
    // (on a host only when asked for, for now: an app with what moves for ever where a flow looks, a placeholder's
    // breath, never settles there; the frames' reasons the framework is to know first)
    drive_start(script, @host.env("MBUI_SHOT_DIR"), settles=@host.env("MBUI_DRIVE_SETTLED") == "1")
  }
}

///|
fn drive_start(script : String, dir : String, settles? : Bool = true) -> Unit {
  let steps = script.split("\n").map(fn(l) { l.trim(chars=" \t\r").to_string() }).to_array()
  driver.val = Some({
    steps,
    at: 0,
    since: -1.0,
    timeout: 20000.0,
    release_at: -1.0,
    rx: 0.0,
    ry: 0.0,
    seen_x: -1.0,
    seen_y: -1.0,
    gx: 0.0,
    gy: 0.0,
    gdx: 0.0,
    gdy: 0.0,
    gt0: 0.0,
    gms: 0.0,
    shot_at: -1.0,
    calm: 0,
    settles,
    told: false,
    dir,
  })
  h_log("DRIVE start: \{steps.length()} lines")
}

///|
/// The words on screen a step looks for: text, rich text, a field's placeholder; `icon:NAME` an @sf icon. Only what
/// is laid out inside the window counts; what is only drawn (Ctx::draw_only) does not.
fn on_screen(c : Ctx, what : String) -> Array[(Double, Double)] {
  let found = []
  let icon = if what.has_prefix("icon:") {
    Some("/icon/" + what.unsafe_substring(start=5, end=what.length()) + "/")
  } else if what.has_prefix("img:") {
    // an image by its source (a chat's file: its key ends with the file's name)
    Some(what.unsafe_substring(start=4, end=what.length()))
  } else {
    None
  }
  let exact = if what.has_prefix("=") && what.length() > 1 {
    Some(what.unsafe_substring(start=1, end=what.length()))
  } else {
    None
  }
  for i in 0..<c.count {
    let n = c.nodes[i]
    let hit = match icon {
      Some(k) => n.kind == kind_image && n.text.contains(k)
      None =>
        (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) &&
        (match exact {
          Some(e) => n.text == e
          None => n.text.contains(what)
        })
    }
    if hit && n.fw > 0.0 && n.fh > 0.0 && !c.in_draw_only(i) {
      // where it is laid out: where it is tapped (a look moves only what is drawn: draw.mbt); in rich text, the
      // middle of the words looked for (a link in a paragraph, a word in a long line of code)
      let (x, y) = match (n.rl, exact) {
        (Some(rl), None) =>
          match n.text.find(what) {
            Some(k) =>
              match rl.rects(k, k + what.length()).get(0) {
                Some(r) => (n.x + n.pad_l + r.0 + r.2 / 2.0, n.y + n.pad_t + r.1 + r.3 / 2.0)
                None => (n.x + n.fw / 2.0, n.y + n.fh / 2.0)
              }
            None => (n.x + n.fw / 2.0, n.y + n.fh / 2.0)
          }
        _ => (n.x + n.fw / 2.0, n.y + n.fh / 2.0)
      }
      if x >= 0.0 && x <= c.width && y >= 0.0 && y <= c.height {
        found.push((x, y))
      }
    }
  }
  found
}

///|
/// What is on screen, in words, for a failure's report.
fn screen_words(c : Ctx) -> String {
  let words = []
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_rich) && n.text != "" {
      let y = n.y + n.fh / 2.0
      if y >= 0.0 && y <= c.height {
        words.push(n.text)
      }
    }
  }
  let all = words.join(" | ")
  if all.length() > 1500 {
    all.unsafe_substring(start=0, end=1500) + "…"
  } else {
    all
  }
}

///|
/// The focused field's words ("" when none is focused).
fn field_words(c : Ctx) -> String {
  match c.editors.get(c.focus) {
    Some(st) => st.display()
    None => ""
  }
}

///|
/// Whether a field (focused or not: a draft put back) holds `words`.
fn fields_hold(c : Ctx, words : String) -> Bool {
  for _, st in c.editors {
    if st.display().contains(words) {
      return true
    }
  }
  false
}

///|
/// The host's way of sending a step's input (@host.drive); a test's fake host has none.
fn h_drive(kind : Int, text : String) -> Bool {
  match fake.val {
    Some(_) => false
    None => @host.drive(kind, text)
  }
}

///|
/// The run over: the app ends with its verdict (a test's fake host notes it).
fn drive_end(code : Int) -> Unit {
  h_log(if code == 0 { "DRIVE PASS" } else { "DRIVE END \{code}" })
  driver.val = None
  match fake.val {
    Some(f) => f.logs.push("EXIT \{code}")
    None => @host.exit(code)
  }
}

///|
fn drive_shot(d : Driver, name : String) -> Bool {
  let path = (if d.dir == "" { "." } else { d.dir }) + "/" + name + ".png"
  if h_drive(4, path) {
    true
  } else {
    h_log("SHOT " + name)
    false
  }
}

///|
fn drive_fail(c : Ctx, d : Driver, why : String) -> Unit {
  let line = if d.at < d.steps.length() { d.steps[d.at] } else { "(the script's end)" }
  h_log("DRIVE FAIL line \{d.at + 1}: \{line}: \{why}")
  h_log("DRIVE FAIL on screen: " + screen_words(c))
  let f = field_words(c)
  if f != "" {
    h_log("DRIVE FAIL in the field: " + f)
  }
  drive_shot(d, "fail") |> ignore
  drive_end(1)
}

///|
/// A step's number: digits, a sign, a fraction (0 for anything else).
fn number(s : String) -> Double {
  let mut v = 0.0
  let mut neg = false
  let mut scale = 0.0
  for ch in s {
    if ch == '-' {
      neg = true
    } else if ch == '.' {
      scale = 1.0
    } else if ch >= '0' && ch <= '9' {
      let digit = (ch.to_int() - '0'.to_int()).to_double()
      if scale > 0.0 {
        scale = scale / 10.0
        v = v + digit * scale
      } else {
        v = v * 10.0 + digit
      }
    }
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// The lowest of the places found (a list builds its rows in no order on screen: the newest is the lowest).
fn lowest(at : Array[(Double, Double)]) -> (Double, Double) {
  let mut best = at[0]
  for p in at {
    if p.1 > best.1 {
      best = p
    }
  }
  best
}

///|
/// The highest of the places found.
fn topmost(at : Array[(Double, Double)]) -> (Double, Double) {
  let mut best = at[0]
  for p in at {
    if p.1 < best.1 {
      best = p
    }
  }
  best
}

///|
/// Whether what is to be tapped is where it was last frame (else noted, for the next).
fn Driver::still(self : Driver, x : Double, y : Double) -> Bool {
  let same = (x - self.seen_x).abs() < 0.5 && (y - self.seen_y).abs() < 0.5
  self.seen_x = x
  self.seen_y = y
  same
}

///|
fn press(x : Double, y : Double, up : Bool) -> Unit {
  on_pointer(0, x, y, 0)
  if up {
    on_pointer(2, x, y, 0)
  }
}

///|
/// The steps that look at the screen or act on it: each first waits for the app to be settled (unless `now`).
fn settles_first(cmd : String) -> Bool {
  match cmd {
    "until" | "untiln" | "gone" | "field" | "empty" | "clear" | "tap" | "tap1" | "tapxy" | "hold" | "type"
    | "mark" | "enter" | "backspace" | "back" | "paste" | "pasten" | "wheel" | "wheelat" | "move" | "hover"
    | "rightclick" | "key" | "resize" | "drag" | "dragon" | "shot" | "exit" => true
    _ => false
  }
}

///|
/// The words a step looks for on screen, if it looks for some (for a failure's report).
fn target_of(cmd : String, arg : String) -> String? {
  let after_first = fn() {
    match arg.find(" ") {
      Some(i) => arg.unsafe_substring(start=i + 1, end=arg.length())
      None => arg
    }
  }
  match cmd {
    "until" | "gone" | "tap" | "tap1" | "hover" | "rightclick" => Some(arg)
    "untiln" | "wheelat" => Some(after_first())
    "hold" =>
      match arg.find(" ") {
        Some(i) if number(arg.unsafe_substring(start=0, end=i)) > 0.0 => Some(after_first())
        _ => Some(arg)
      }
    "dragon" => {
      let words = arg.split(" ").map(fn(v) { v.to_string() }).to_array()
      if words.length() >= 4 {
        Some(words[3:].to_owned().join(" "))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Runs the script's steps due this frame (after it was drawn): steps that only look run on at once; one that acts
/// ends the frame's turn, so the app sees it before the next.
fn drive_frame(c : Ctx) -> Unit {
  guard driver.val is Some(d) else { return }
  // settled as the app left this frame, before the run asks for the next (it does, every frame, while it goes on);
  // two frames running: the one that took the last step's input, then one built after it
  let settled_now = c.settled()
  d.calm = if settled_now { d.calm + 1 } else { 0 }
  let calm = !d.settles || d.calm >= 2
  // why not, as the app left it (before the run's own ask for a frame)
  let why_not = if settled_now { "" } else { c.unsettled() }
  c.request_frame()
  let now = h_now()
  if d.release_at >= 0.0 {
    if now < d.release_at {
      return
    }
    on_pointer(2, d.rx, d.ry, 0)
    d.calm = 0
    d.release_at = -1.0
    d.at = d.at + 1
    d.since = -1.0
    d.seen_x = -1.0
    d.seen_y = -1.0
    return
  }
  if d.gms > 0.0 {
    // a drag on its way: a move this frame, lifted once all the way
    let f = dmin((now - d.gt0) / d.gms, 1.0)
    let x = d.gx + d.gdx * f
    let y = d.gy + d.gdy * f
    on_pointer(1, x, y, 0)
    if f >= 1.0 {
      on_pointer(2, x, y, 0)
      d.calm = 0
      d.gms = 0.0
      d.at = d.at + 1
      d.since = -1.0
      d.seen_x = -1.0
      d.seen_y = -1.0
    }
    return
  }
  while d.at < d.steps.length() {
    let line = d.steps[d.at]
    if d.since < 0.0 {
      d.since = now
    }
    let waited = now - d.since
    // `now STEP`: the step as it is due, settled or not
    let (at_once, line) = if line.has_prefix("now ") {
      (true, line.unsafe_substring(start=4, end=line.length()).trim(chars=" ").to_string())
    } else {
      (false, line)
    }
    let (cmd, arg) = match line.find(" ") {
      Some(i) =>
        (
          line.unsafe_substring(start=0, end=i),
          line.unsafe_substring(start=i + 1, end=line.length()),
        )
      None => (line, "")
    }
    let next = fn() {
      d.at = d.at + 1
      d.since = -1.0
      d.seen_x = -1.0
      d.seen_y = -1.0
      d.shot_at = -1.0
      d.told = false
    }
    // a step that acted: what it set off is seen settled only from the frame after the one that took it (a press
    // changes what that frame built after the part pressed; its picture may not show it yet)
    let acted = fn() {
      next()
      d.calm = 0
    }
    if !at_once && !calm && settles_first(cmd) && d.shot_at < 0.0 {
      if waited > d.timeout {
        let seen = match target_of(cmd, arg) {
          Some(w) =>
            if on_screen(c, w).length() > 0 {
              " (\{w} is on screen)"
            } else {
              " (\{w} is not on screen)"
            }
          None => ""
        }
        let why = if why_not == "" { "settled only now" } else { why_not }
        drive_fail(c, d, "the app did not settle in \{d.timeout.to_int()} ms\{seen}: " + why)
      } else if waited > 1000.0 && !d.told && why_not != "" {
        // (said once a step, for whoever reads the log: what a slow step waits on)
        d.told = true
        h_log("DRIVE waiting for the app to settle (line \{d.at + 1}): " + why_not)
      }
      return
    }
    match cmd {
      "" => next()
      _ if cmd.has_prefix("#") => next()
      "wait" =>
        if waited >= number(arg) {
          next()
        } else {
          return
        }
      "timeout" => {
        d.timeout = number(arg)
        next()
      }
      "until" | "untiln" | "gone" | "field" | "empty" => {
        let ok = match cmd {
          "until" => on_screen(c, arg).length() > 0
          "untiln" =>
            match arg.find(" ") {
              Some(i) =>
                on_screen(c, arg.unsafe_substring(start=i + 1, end=arg.length())).length() >=
                number(arg.unsafe_substring(start=0, end=i)).to_int()
              None => false
            }
          "gone" => on_screen(c, arg).length() == 0
          "field" => fields_hold(c, arg.replace_all(old="\\n", new="\n"))
          _ => field_words(c) == ""
        }
        if ok {
          h_log("DRIVE ok \{line} (\{waited.to_int()} ms)")
          next()
        } else if waited > d.timeout {
          drive_fail(c, d, "not so after \{d.timeout.to_int()} ms")
          return
        } else {
          return
        }
      }
      "notice" | "noticed" | "nonotice" => {
        // the host's notifications (@host.drive 6: tapped, 7: looked for)
        let ok = match cmd {
          "notice" => h_drive(6, arg)
          "noticed" => h_drive(7, arg)
          _ => !h_drive(7, arg)
        }
        if ok {
          h_log("DRIVE ok \{line} (\{waited.to_int()} ms)")
          if cmd == "notice" { acted() } else { next() }
          return
        } else if waited > d.timeout {
          drive_fail(c, d, "no such notification after \{d.timeout.to_int()} ms")
          return
        } else {
          return
        }
      }
      "tap" | "tap1" => {
        let at = on_screen(c, arg)
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, "not on screen after \{d.timeout.to_int()} ms")
          }
          return
        }
        let (x, y) = if cmd == "tap1" { topmost(at) } else { lowest(at) }
        if !d.still(x, y) {
          return
        }
        h_log("DRIVE \{cmd} \{arg} at \{x.to_int()},\{y.to_int()}")
        press(x, y, true)
        acted()
        return
      }
      "tapxy" => {
        let xy = arg.split(" ").map(fn(v) { number(v.to_string()) }).to_array()
        let x = if xy[0] < 0.0 { c.width + xy[0] } else { xy[0] }
        let y = if xy[1] < 0.0 { c.height + xy[1] } else { xy[1] }
        press(x, y, true)
        acted()
        return
      }
      "hold" => {
        let (ms, what) = match arg.find(" ") {
          Some(i) =>
            (
              number(arg.unsafe_substring(start=0, end=i)),
              arg.unsafe_substring(start=i + 1, end=arg.length()),
            )
          None => (600.0, arg)
        }
        let at = on_screen(c, what)
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, "not on screen after \{d.timeout.to_int()} ms")
          }
          return
        }
        let (x, y) = lowest(at)
        if !d.still(x, y) {
          return
        }
        press(x, y, false)
        d.rx = x
        d.ry = y
        d.release_at = now + ms
        return
      }
      "drag" | "dragon" => {
        let words = arg.split(" ").map(fn(v) { v.to_string() }).to_array()
        let (x, y, rest) = if cmd == "drag" {
          if words.length() < 4 {
            drive_fail(c, d, "drag X Y DX DY [MS]")
            return
          }
          let x = number(words[0])
          let y = number(words[1])
          (
            if x < 0.0 { c.width + x } else { x },
            if y < 0.0 { c.height + y } else { y },
            words[2:].to_owned(),
          )
        } else {
          if words.length() < 4 {
            drive_fail(c, d, "dragon DX DY MS TEXT")
            return
          }
          let what = words[3:].to_owned().join(" ")
          let at = on_screen(c, what)
          if at.length() == 0 {
            if waited > d.timeout {
              drive_fail(c, d, "not on screen after \{d.timeout.to_int()} ms")
            }
            return
          }
          let (x, y) = lowest(at)
          if !d.still(x, y) {
            return
          }
          (x, y, words[0:3].to_owned())
        }
        d.gx = x
        d.gy = y
        d.gdx = number(rest[0])
        d.gdy = if rest.length() > 1 { number(rest[1]) } else { 0.0 }
        d.gms = if rest.length() > 2 { dmax(number(rest[2]), 16.0) } else { 300.0 }
        d.gt0 = now
        h_log("DRIVE \{cmd} \{arg} from \{x.to_int()},\{y.to_int()}")
        on_pointer(0, x, y, 0)
        return
      }
      "type" => {
        if !h_drive(0, arg) {
          on_text(0, arg, 0, 0)
        }
        acted()
        return
      }
      "mark" => {
        if !h_drive(1, arg) {
          on_text(1, arg, arg.length(), 0)
        }
        acted()
        return
      }
      "enter" => {
        if !h_drive(2, "") {
          on_key(key_enter, 0)
        }
        acted()
        return
      }
      "clear" => {
        on_key(key_select_all, 0)
        if !h_drive(5, "") {
          on_key(key_backspace, 0)
        }
        acted()
        return
      }
      "backspace" => {
        if !h_drive(5, "") {
          on_key(key_backspace, 0)
        }
        acted()
        return
      }
      "back" => {
        on_back(2, 0.0, 0.0, 0)
        acted()
        return
      }
      "paste" | "pasten" => {
        let words = if cmd == "paste" {
          arg
        } else {
          match arg.find(" ") {
            Some(i) => {
              let n = number(arg.unsafe_substring(start=0, end=i)).to_int()
              let unit = arg.unsafe_substring(start=i + 1, end=arg.length())
              let sb = StringBuilder()
              let mut len = 0
              while len < n && unit.length() > 0 {
                sb.write_string(unit)
                len = len + unit.length()
              }
              sb.to_string()
            }
            None => arg
          }
        }
        h_clipboard_set(words)
        if !h_drive(3, "") {
          on_text(0, words, 0, 0)
        }
        acted()
        return
      }
      "wheel" => {
        on_wheel(c.width / 2.0, c.height / 2.0, 0.0, number(arg), 0)
        acted()
        return
      }
      "move" => {
        let xy = arg.split(" ").map(fn(v) { number(v.to_string()) }).to_array()
        if xy.length() < 2 {
          drive_fail(c, d, "move X Y")
          return
        }
        let x = if xy[0] < 0.0 { c.width + xy[0] } else { xy[0] }
        let y = if xy[1] < 0.0 { c.height + xy[1] } else { xy[1] }
        on_pointer(1, x, y, 0)
        acted()
        return
      }
      "hover" | "rightclick" | "wheelat" => {
        let (dy, what) = if cmd == "wheelat" {
          match arg.find(" ") {
            Some(i) =>
              (
                number(arg.unsafe_substring(start=0, end=i)),
                arg.unsafe_substring(start=i + 1, end=arg.length()),
              )
            None => {
              drive_fail(c, d, "wheelat DY TEXT")
              return
            }
          }
        } else {
          (0.0, arg)
        }
        let at = on_screen(c, what)
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, "not on screen after \{d.timeout.to_int()} ms")
          }
          return
        }
        let (x, y) = lowest(at)
        if !d.still(x, y) {
          return
        }
        h_log("DRIVE \{cmd} \{what} at \{x.to_int()},\{y.to_int()}")
        match cmd {
          "hover" => on_pointer(1, x, y, 0)
          "rightclick" => {
            on_pointer(0, x, y, 2)
            on_pointer(2, x, y, 2)
          }
          _ => on_wheel(x, y, 0.0, dy, 4)
        }
        acted()
        return
      }
      "key" =>
        match key_named(arg) {
          Some((code, mods)) => {
            h_log("DRIVE key \{arg} (\{code} \{mods})")
            on_key(code, mods)
            acted()
            return
          }
          None => {
            drive_fail(c, d, "no such key")
            return
          }
        }
      "resize" => {
        let wh = arg.split(" ").map(fn(v) { number(v.to_string()) }).to_array()
        if wh.length() < 2 {
          drive_fail(c, d, "resize W H")
          return
        }
        if !h_drive(8, "\{wh[0].to_int()}x\{wh[1].to_int()}") {
          match fake.val {
            Some(_) => tester_size.val = Some((wh[0], wh[1]))
            None => h_log("DRIVE resize: the host cannot")
          }
        }
        acted()
        return
      }
      "shot" =>
        if d.shot_at < 0.0 {
          if drive_shot(d, arg) {
            next()
          } else {
            d.shot_at = now
            return
          }
        } else if now - d.shot_at >= 1500.0 {
          next()
        } else {
          return
        }
      "log" => {
        h_log("DRIVE LOG " + arg)
        next()
      }
      "exit" => {
        drive_end(0)
        return
      }
      "linger" => {
        h_log("DRIVE PASS")
        d.steps.clear()
        d.steps.push("wait " + arg)
        d.steps.push("quit")
        d.at = 0
        d.since = -1.0
        return
      }
      "quit" => {
        driver.val = None
        match fake.val {
          Some(f) => f.logs.push("EXIT 0")
          None => @host.exit(0)
        }
        return
      }
      _ => {
        drive_fail(c, d, "no such step")
        return
      }
    }
  }
  // the script's end, as `exit`: once settled (what the last steps set off is done, a call to the core answered), so
  // the app does not end under it
  if d.since < 0.0 {
    d.since = now
  }
  if !calm {
    if now - d.since > d.timeout {
      let why = if why_not == "" { "settled only now" } else { why_not }
      drive_fail(c, d, "the app did not settle in \{d.timeout.to_int()} ms: " + why)
    }
    return
  }
  drive_end(0)
}

///|
/// Runs `script` (as MBUI_DRIVE would) over the tester's view, a frame each 16 ms, until it ends (or `max` frames):
/// what it logged. `settles` false: its steps wait for nothing settling, as a host's do (MBUI_DRIVE_SETTLED unset): a
/// run seen again as it was recorded there.
pub fn Tester::drive(
  self : Tester,
  script : String,
  max? : Int = 3000,
  settles? : Bool = true,
) -> Array[String] {
  self.fake.logs.clear()
  drive_start(script, "", settles~)
  let mut n = 0
  while driver.val is Some(_) && n < max {
    self.frame()
    n = n + 1
  }
  self.fake.logs.copy()
}

///|
/// A size a scripted run asked of the window, for the tester's next frame (a host's window resizes itself).
let tester_size : Ref[(Double, Double)?] = Ref::new(None)

///|
/// A key as a script names it (drive's `key`): its code and modifiers.
fn key_named(name : String) -> (Int, Int)? {
  let parts = name.split("+").map(fn(v) { v.to_string() }).to_array()
  let mut mods = 0
  for i in 0..<(parts.length() - 1) {
    match parts[i] {
      "cmd" => mods = mods | (if h_platform() == 0 { mod_cmd } else { mod_ctrl })
      "ctrl" => mods = mods | mod_ctrl
      "alt" | "option" => mods = mods | mod_alt
      "shift" => mods = mods | mod_shift_key
      "meta" => mods = mods | mod_cmd
      _ => return None
    }
  }
  let last = if parts.length() > 0 { parts[parts.length() - 1] } else { "" }
  let code = match last {
    "esc" | "escape" => key_escape
    "tab" => key_tab
    "enter" | "return" => key_enter
    "space" => key_of_char(' ')
    "up" => key_up
    "down" => key_down
    "left" => key_left
    "right" => key_right
    "home" => key_home
    "end" => key_end
    "pageup" => key_page_up
    "pagedown" => key_page_down
    "backspace" => key_backspace
    "delete" => key_delete
    s if s.length() == 1 => {
      let mut code = -1
      for ch in s {
        code = key_of_char(ch)
      }
      code
    }
    _ => return None
  }
  Some((code, mods))
}
