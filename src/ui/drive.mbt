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
//   drag X Y DX DY [MS]         a finger down at X Y (negative: from the right, the bottom), moved by DX DY over MS
//                               (300 by default), a move a frame, then lifted there
//   dragon DX DY MS TEXT        the same from the lowest TEXT on screen, once it holds still
//   shot NAME                   the window's picture as $MBUI_SHOT_DIR/NAME.png (where the host cannot, "SHOT NAME"
//                               is logged and the run waits 1.5 s for whoever takes it: adb's screencap)
//   log TEXT                    DRIVE LOG TEXT on the log (a mark for whoever watches it)
//   exit                        ends the run: DRIVE PASS, exit 0
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
  dir : String
}

///|
let driver : Ref[Driver?] = { val: None }

///|
/// Reads the script from the environment, once, as the window opens.
fn drive_init() -> Unit {
  let script = @host.env_text("MBUI_DRIVE")
  if script != "" {
    drive_start(script, @host.env("MBUI_SHOT_DIR"))
  }
}

///|
fn drive_start(script : String, dir : String) -> Unit {
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
      // where it is laid out: where it is tapped (a look moves only what is drawn: draw.mbt)
      let x = n.x + n.fw / 2.0
      let y = n.y + n.fh / 2.0
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
  h_log("DRIVE FAIL line \{d.at + 1}: \{d.steps[d.at]}: \{why}")
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
/// Runs the script's steps due this frame (after it was drawn): steps that only look run on at once; one that acts
/// ends the frame's turn, so the app sees it before the next.
fn drive_frame(c : Ctx) -> Unit {
  guard driver.val is Some(d) else { return }
  c.wants_frame = true
  let now = h_now()
  if d.release_at >= 0.0 {
    if now < d.release_at {
      return
    }
    on_pointer(2, d.rx, d.ry, 0)
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
        next()
        return
      }
      "tapxy" => {
        let xy = arg.split(" ").map(fn(v) { number(v.to_string()) }).to_array()
        let x = if xy[0] < 0.0 { c.width + xy[0] } else { xy[0] }
        let y = if xy[1] < 0.0 { c.height + xy[1] } else { xy[1] }
        press(x, y, true)
        next()
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
        next()
        return
      }
      "mark" => {
        if !h_drive(1, arg) {
          on_text(1, arg, arg.length(), 0)
        }
        next()
        return
      }
      "enter" => {
        if !h_drive(2, "") {
          on_key(key_enter, 0)
        }
        next()
        return
      }
      "clear" => {
        on_key(key_select_all, 0)
        if !h_drive(5, "") {
          on_key(key_backspace, 0)
        }
        next()
        return
      }
      "backspace" => {
        if !h_drive(5, "") {
          on_key(key_backspace, 0)
        }
        next()
        return
      }
      "back" => {
        on_back(2, 0.0, 0.0, 0)
        next()
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
        next()
        return
      }
      "wheel" => {
        on_wheel(c.width / 2.0, c.height / 2.0, 0.0, number(arg), 0)
        next()
        return
      }
      "shot" =>
        if waited == 0.0 {
          if drive_shot(d, arg) {
            next()
          } else {
            return
          }
        } else if waited >= 1500.0 {
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
      _ => {
        drive_fail(c, d, "no such step")
        return
      }
    }
  }
  drive_end(0)
}

///|
/// Runs `script` (as MBUI_DRIVE would) over the tester's view, a frame each 16 ms, until it ends (or `max` frames):
/// what it logged.
pub fn Tester::drive(self : Tester, script : String, max? : Int = 3000) -> Array[String] {
  self.fake.logs.clear()
  drive_start(script, "")
  let mut n = 0
  while driver.val is Some(_) && n < max {
    self.frame()
    n = n + 1
  }
  self.fake.logs.copy()
}
