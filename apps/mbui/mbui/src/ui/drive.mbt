// Scripted runs over the app's own screen (MBUI_DRIVE, or MBUI_DRIVE_B64 as base64): a script of steps, one a line,
// run frame by frame on any host, finding what to tap by its words on screen and waiting on what should come there,
// for end-to-end runs against a live backend (scripts/e2e-local.sh, e2e/flows). Input goes the way the system sends
// it where the host has that way (@hostapi.drive: on macOS the input method's calls and Cmd+V, on Android the view's
// InputConnection and KEYCODE_PASTE); else straight to the app's handlers.
//
//   # a comment                 wait MS                   timeout MS (for until/gone/field after it; 20000 to start)
//   until TEXT                  words containing TEXT on screen (a text, rich text, a field's placeholder, or
//                               icon:NAME, an @sf icon; img:NAME an image whose source has NAME in it; switch:LABEL
//                               the switch that turns LABEL), within the
//                               timeout; else the run fails
//                               (=TEXT: words that are TEXT exactly)
//   untiln N TEXT               N or more of them on screen
//   gone TEXT                   no longer on screen
//   field TEXT                  a field's words contain TEXT (\n a new line)     empty   the focused field is empty
//   empty now                   the focused field empty in the frame the step before acted in: read at once, not
//                               waited for (words sent: the field given up as they go, not later)
//   said TEXT                   an event the app said (Ctx::say) holding TEXT, within the timeout: a fact of its state
//                               or of what came from outside it (a message sent is in the list, by its row's key),
//                               never a motion's end (no step waits for a motion to be over); the run's
//                               k-th `said` line the k-th such event, counted from the run's start
//   clear                       the focused field emptied (all selected, deleted)
//   tap TEXT                    taps the lowest TEXT on screen (in a chat, the newest), once there (within the
//                               timeout), holding still and not under something else a press would go to (a
//                               composer over a list's last row, a sheet); tap1 TEXT the highest
//   tapxy X Y                   taps there (negative: from the right, the bottom)
//   hold MS TEXT                pressed on TEXT for MS, then let go (a long press)
//   type TEXT                   committed by the input method      mark TEXT    composed (not yet committed)
//   enter                       backspace                 back       the system's back
//   paste TEXT                  TEXT on the clipboard, then the system's paste
//   pasten N TEXT               TEXT repeated to N characters, pasted
//   wheel DY [MODS]             the list under the middle of the window scrolled by DY (with MODS held: cmd, ctrl,
//                               alt, shift joined by +; ⌘ and a wheel over a picture zoom it)
//   wheelat DY TEXT             the list under the lowest TEXT scrolled by DY, a mouse wheel's notches (eased in)
//   wheelxat DX TEXT            what scrolls sideways under the lowest TEXT scrolled by DX, a wheel's (a trackpad's)
//   move X Y                    the pointer moved there, no button down (negative: from the right, the bottom)
//   hover TEXT                  the pointer moved onto the lowest TEXT, where the frame has it
//   rightclick TEXT             a secondary click (a context menu's) on the lowest TEXT, where the frame has it
//   key NAME                    a key, with what is held before it: esc, tab, enter, space, up, down, left, right,
//                               home, end, pageup, pagedown, backspace, a character; cmd+ (⌘ on macOS, Ctrl
//                               elsewhere), ctrl+, alt+, shift+ (cmd+k, shift+enter, alt+down)
//   resize W H                  the window's content resized to W by H (the host's own window, where it can)
//   ime H                       under a Tester (a film's run), the soft keyboard H points over the window's foot, as a
//                               host says it while it moves (Tester::set_ime_inset); a real host's is its own
//   system JSON                 under a Tester (a film's run), the system says JSON on its channel as a host says it
//                               (@hostapi.system_channel: a size class, the hinge and its fold, the bars), taken at
//                               the next frame; a real host's system says its own, and the run fails
//   drag X Y DX DY [MS]         a finger down at X Y (negative: from the right, the bottom), moved by DX DY over MS
//                               (300 by default), a move a frame, then lifted there
//   dragon DX DY MS TEXT        the same from the lowest TEXT on screen, where the frame has it
//   holdon MS DX DY MOVE TEXT   held still on the lowest TEXT (or @X,Y) MS, then dragged DX DY over MOVE ms and held
//                               there MS again before it is lifted (a long press slid on)
//   backswipe DX [MS] [right] [off]  the system's back gesture (Android's predictive back) from the left edge (right:
//                               the right's), DX across over MS (300 by default), a step a frame, then gone through
//                               (off: called off)
//   shot NAME                   the window's picture, as the frame just drawn, as $MBUI_SHOT_DIR/NAME.png (where the host cannot,
//                               "SHOT NAME" is logged and the run waits 1.5 s for whoever takes it: adb's screencap)
//   noticed TEXT                one of the app's notifications (the system's, @hostapi.notice_show) holds TEXT in its
//                               title or words, within the timeout       nonotice TEXT   none does
//   notice TEXT                 that notification, once there, tapped (as the system's shade sends the tap)
//   log TEXT                    DRIVE LOG TEXT on the log (a mark for whoever watches it)
//   picks NAME:SIZE …           what the system's pickers give from then on, under a Tester (film): files so named, of
//                               so many bytes each (none: called off); a host's own pickers are not stood in for
//   exit                        ends the run: DRIVE PASS, exit 0
//   ends                        the app ends by itself, its host quitting it (an update handed to its installer), within
//                               the timeout; else the run fails. What follows it is never reached
//   linger MS                   the run passed (DRIVE PASS said now), the app left running MS more for what the last
//                               step set off (a share sheet, a download): a check beside the run looks at it
//   answered CALL               a call to the core named CALL (drive.read; or a subscription's topic key, its first
//                               value) answered, and a frame drawn after it, within the timeout: the run's k-th
//                               `answered CALL` line its k-th answer, counted from the run's start (one come before
//                               the step that acted ahead of the line is as good), each line an answer of its own
//   decoded SRC                 a picture whose source ends with SRC (e2e-photo.jpg; a PDF's page: "PDF") or
//                               begins with it (a prefix: a gallery's content://media/) decoded, from its address or
//                               from bytes handed over for it (Ctx::image_bytes, add_image)
//   ready VIEW                  a native view ready: by its kind's name (video, audio, web, site), pdf (a PDF's page
//                               drawn), its kind's number (1 video or audio, 2 web, 3 site), #ID its id
//   outside_done NAME           work outside the app (a wait on the host or the core, by its name: "an update
//                               downloading") with NAME in it done since the last step that acted (what it set off),
//                               and a frame drawn after it, within the timeout; NAME naming more than one done, the
//                               run fails. Never a motion: no step waits for one to end
//   hosted                      from here on the app is as the host says it is (shown or not, in front or not), as
//                               out of a run; till then a run keeps it shown and in front, whatever the host says
//                               (a locked screen's window is covered): a run about the app put away (e2e/win's)
//   shown                       the host's word that the app is shown again (after it was not: another app's page
//                               over it gone) since the last step that acted, and a frame drawn after it
//   done X                      the run's runner (still.fail's run.sh: what `log do: X` asked of it) has done X: its
//                               file X come in the directory the run names (MBUI_DONE_DIR, else $MBUI_SHOT_DIR/done),
//                               the host told of it by its system (src/host/done_watch.h: macOS, Android, Windows);
//                               its words "ok" (or none): done; else what went wrong, and the run fails saying it.
//                               Where the host watches no such directory (a Tester's, the web's, iOS's), it fails
//                               at once
//   now STEP                    STEP (as written before steps waited for nothing: kept, the same as STEP)
// No step waits for the app to be settled. What a step looks for comes with a frame (an input's, a message's, the
// host's event's, a motion's), and it is looked for at each; a tap, a hold, a hover or a drag on words goes where the
// frame just drawn has them, that frame, never waiting for them to hold still. What comes later than a frame is waited
// for by name (until, gone, answered, decoded, ready, outside_done, shown, done), within the timeout. Nothing waits for
// the app to be at rest (settled by another name): that is asserted of a run, never waited on (a Tester's
// assert_true(t.at_rest())). The run asks for no frame of its own: what it waits for in time (a timeout, a hold let
// go, a `wait`, a shot another takes) is a wake at that time. `wait` stays a pause in real time, for what is outside
// the app (a command beside the run, the other device, the station) that no `until` can see, and that the runner does
// not say it has done (`done`).
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
  // a drag under way (drag, dragon): where it went down, how far it goes, since when, over how long (0: none)
  mut gx : Double
  mut gy : Double
  mut gdx : Double
  mut gdy : Double
  mut gt0 : Double
  // (`holdon`: how long it stays held where it ends, before it is lifted)
  mut gstay : Double
  mut gms : Double
  // the system's back gesture under way (backswipe): how far across it goes, from which edge (1 the right), whether
  // it is called off at the end, since when, over how long (0: none)
  mut bdx : Double
  mut bedge : Int
  mut boff : Bool
  mut bt0 : Double
  mut bms : Double
  // when a shot the host cannot take was asked for (logged "SHOT NAME": whoever takes it has 1.5 s), -1 before
  mut shot_at : Double
  // answered, decoded, ready: how many waits on outside had ended as the last step that acted did (or the run began:
  // Runtime::outside_ended), and the frame the step saw its own end in (-1: not yet)
  mut mark : Int
  // shown: how often the host had said the app is shown again (`shown`) as the last step that acted did
  mut shown_mark : Int
  // how often the host has said the app is shown again after it was not (app.mbt's on_app_state), and what it said
  // last
  mut shown : Int
  mut said_state : Int
  // what the host says of the app's state taken from `hosted` on (till then the run keeps it shown and in front)
  mut takes_state : Bool
  // the answers come of each call since the run began (`answered CALL`), by its name, counted up to the ended wait
  // `counted` (each frame, and before a step that acts takes its mark: Runtime::outside_ended lets go of what came
  // before), and how many of them the run's `answered` lines have taken
  answers : Map[String, Int]
  mut counted : Int
  answers_taken : Map[String, Int]
  // whether the host watches the runner's directory (`done`), and what the runner said it has done, by name
  watching : Bool
  runner_done : Map[String, String]
  mut seen_frame : Int
  dir : String
  // the app's events (Ctx::say) the run's `said` lines have taken: those before this one
  mut said_taken : Int
}

///|
let driver : Ref[Driver?] = { val: None }

///|
/// What the app said happened (Ctx::say), in order, while a run is driven (`said`).
let app_said : Array[String] = []

///|
/// Says that `what` is so (a fact of the app's state, or of what came from outside it: a message sent is in the list,
/// by its row's key; never a motion's end): an event a driven run waits for by name (`said`), logged as SAID; nothing
/// when no run is driven.
pub fn Ctx::say(self : Ctx, what : String) -> Unit {
  ignore(self)
  if driver.val is Some(_) {
    app_said.push(what)
    h_log("SAID \{what}")
  }
}

///|
/// Reads the script from the environment, once, as the window opens.
fn drive_init() -> Unit {
  let script = @hostapi.env_text("MBUI_DRIVE")
  if script != "" {
    let dir = @hostapi.env("MBUI_SHOT_DIR")
    let done_dir = match @hostapi.env("MBUI_DONE_DIR") {
      "" => if dir == "" { "" } else { dir + "/done" }
      d => d
    }
    drive_start(script, dir, done_dir~)
  }
}

///|
/// The moments of a script's line a run's tracer is told of (@ui.trace_steps).
pub(all) enum StepMoment {
  /// the line begun, before anything of it is done (a tap still waiting for its words to be on screen)
  Began
  /// its input handed to the app as the host sends it (the press, the words typed, the key): the frame it goes in
  Acted
} derive(Eq, Show)

///|
/// Who is told each line of a script as it begins and as it acts (@ui.trace_steps): a run's record of it.
// kept across runs: the app's own, set once as it starts
let steps_tracer : Ref[((String, StepMoment) -> Unit)?] = Ref::new(None)

///|
/// Each line of a scripted run's script (MBUI_DRIVE) given to `step` as written (`tap 发消息`, `until …`): as it
/// begins (Began), before anything of it is done, and, a line that acts, again as its input is handed over (Acted),
/// in the frame its words are on screen: what a run keeps beside its other messages (its own clock added), for a
/// replay to know when each step came and when its input did.
pub fn trace_steps(step : (String, StepMoment) -> Unit) -> Unit {
  steps_tracer.val = Some(step)
}

///|
fn tell_step(line : String, moment : StepMoment) -> Unit {
  match steps_tracer.val {
    Some(told) => told(line, moment)
    None => ()
  }
}

///|
/// What the host posted of the runner (done_watch.h: {"done": X, "said": WORDS}) kept in `done`, by X.
fn runner_said(done : Map[String, String], j : String) -> Unit {
  match (try Some(@json.parse(j)) catch { _ => None }) {
    Some(Object(o)) =>
      match (o.get("done"), o.get("said")) {
        (Some(String(x)), Some(String(said))) => {
          h_log("DRIVE runner done \{x}: \{said.trim(chars=" \n\r\t")}")
          done[x] = said
        }
        _ => ()
      }
    _ => ()
  }
}

///|
fn drive_start(script : String, dir : String, done_dir? : String = "") -> Unit {
  let steps = script.split("\n").map(fn(l) { l.trim(chars=" \t\r").to_string() }).to_array()
  // what the runner has done, as the host posts it (done_watch.h: {"done": X, "said": WORDS}), the frame its post
  // wakes taking it
  let runner_done : Map[String, String] = {}
  let watching = done_dir != "" && h_drive(9, done_dir)
  if watching {
    on_message("runner", fn(j, _) { runner_said(runner_done, j) })
  }
  driver.val = Some({
    steps,
    at: 0,
    since: -1.0,
    timeout: 20000.0,
    release_at: -1.0,
    rx: 0.0,
    ry: 0.0,
    gx: 0.0,
    gy: 0.0,
    gdx: 0.0,
    gdy: 0.0,
    gt0: 0.0,
    gstay: 0.0,
    gms: 0.0,
    bdx: 0.0,
    bedge: 0,
    boff: false,
    bt0: 0.0,
    bms: 0.0,
    shot_at: -1.0,
    mark: runtime().outside_ended(),
    shown_mark: 0,
    shown: 0,
    said_state: 3,
    takes_state: false,
    answers: {},
    counted: runtime().outside_ended(),
    answers_taken: {},
    watching,
    runner_done,
    seen_frame: -1,
    dir,
    said_taken: 0,
  })
  let watched = if watching { " (the runner's directory \{done_dir} watched)" } else { "" }
  h_log("DRIVE start: \{steps.length()} lines" + watched)
}

///|
/// The words on screen a step looks for: text, rich text, a field's placeholder; `icon:NAME` an @sf icon. Only what
/// is laid out inside the window counts; what is only drawn (Ctx::draw_only) does not.
fn on_screen(c : Ctx, what : String) -> Array[(Double, Double)] {
  on_screen_nodes(c, what).map(fn(p) { (p.0, p.1) }) + tree_on_screen(c, what).map(fn(p) { (p.0, p.1) })
}

///|
/// What of the window's tree shows `what` (its words, `=WORDS` exactly, `icon:NAME` what it draws is called so:
/// View::drawn_as; or is called `what`, its label whole: View::says), the middle of each where it is drawn, in the
/// window, as it is made, however faded this frame (made transparent, coming in), as on_screen_nodes finds an old
/// view's laid out; not on its way out (View::leaving: drawn only, as an old layer leaving is, Ctx::overlay's inert);
/// whether it takes a press or not, whatever lies over it (reachable says which of it a finger
/// reaches). What is seen is the glyphs' to say (Tester::glyphs_seen), not this.
fn tree_on_screen(c : Ctx, what : String) -> Array[(Double, Double, @view.NodeId)] {
  guard view_app.val is Some(tree) else { return [] }
  // (each: where, which, and whether by its words, not its label alone)
  let hits : Array[(Double, Double, @view.NodeId, Bool)] = []
  for d in tree.drawn() {
    // (or by what it is called, its label whole, as an old view's box is: as Compose's test finds a node by its
    // contentDescription, on_screen_nodes)
    let label = tree.said_label(d.id)
    let by_words = !what.has_prefix("icon:") && d.words != "" &&
      (if what.has_prefix("=") { d.words == what.unsafe_substring(start=1, end=what.length()) } else { d.words.contains(what) })
    let hit = if what.has_prefix("icon:") {
      tree.drawn_name(d.id).contains("/icon/" + what.unsafe_substring(start=5, end=what.length()) + "/")
    } else if what.has_prefix("=") && what.length() > 1 {
      let exact = what.unsafe_substring(start=1, end=what.length())
      d.words == exact || (label != "" && label == exact)
    } else if what.contains(":") {
      false
    } else {
      (d.words != "" && d.words.contains(what)) || (label != "" && label == what)
    }
    let (x, y) = (d.x + d.w / 2.0, d.y + d.h / 2.0)
    if hit && !tree.leaving(d.id) && d.w > 0.0 && d.h > 0.0 && x >= 0.0 && x <= c.width && y >= 0.0 && y <= c.height {
      hits.push((x, y, d.id, by_words))
    }
  }
  // (one called so that holds words found: those words, once, as an old view's row read out by its words is found by
  // its text alone)
  hits
  .filter(fn(h) { h.3 || !hits.iter().any(fn(w) { w.3 && w.2 != h.2 && tree.holds(h.2, w.2) }) })
  .map(fn(h) { (h.0, h.1, h.2) })
}

///|
/// Those of them a finger reaches: what the press there goes to (the last frame's hit targets) is the words' own
/// (theirs, or what holds them), or nothing; not words under what lies over them (a composer over a list's last row,
/// a sheet, a scrim): a step waits for them to come out from under it, as someone would.
fn reachable(c : Ctx, what : String) -> Array[(Double, Double)] {
  let at = []
  for p in on_screen_nodes(c, what) {
    match reach_point(c, p.2, p.0, p.1, p.3) {
      Some(q) => at.push(q)
      None => ()
    }
  }
  // (of the window's tree: where what a press there goes to is it, or holds it, as the tree finds it then)
  match view_app.val {
    Some(tree) =>
      for p in tree_on_screen(c, what) {
        match view_presses_at(p.0, p.1) {
          Some(id) if tree.holds(id, p.2) => at.push((p.0, p.1))
          _ => ()
        }
      }
    None => ()
  }
  at
}

///|
/// Where a finger reaches node `i`'s words, (x, y) their middle, `box` where they are (x0, y0, x1, y1: in a paragraph
/// the words' own, not the paragraph's): there, else the point of them in sight nearest it that a press goes to them
/// at (part of them out from under what lies over the rest: a link half under a composer), the same each run (on a
/// grid of reach_step, the nearest first, then the higher, then the one further left). None: no point of them in
/// sight is theirs to press.
fn reach_point(
  c : Ctx,
  i : Int,
  x : Double,
  y : Double,
  box : (Double, Double, Double, Double),
) -> (Double, Double)? {
  if !under_another(c, i, x, y) {
    return Some((x, y))
  }
  let n = c.nodes[i]
  // what of them is in sight: their box, cut by what clips it and by the window
  let mut x0 = dmax(box.0, 0.0)
  let mut y0 = dmax(box.1, 0.0)
  let mut x1 = dmin(box.2, c.width)
  let mut y1 = dmin(box.3, c.height)
  let mut j = n.parent
  let mut up = 0
  while j >= 0 && j < c.count && up < c.count {
    let a = c.nodes[j]
    if a.clip {
      x0 = dmax(x0, a.x)
      y0 = dmax(y0, a.y)
      x1 = dmin(x1, a.x + a.fw)
      y1 = dmin(y1, a.y + a.fh)
    }
    j = a.parent
    up += 1
  }
  let mut best : (Double, Double)? = None
  let mut best_d = @double.infinity
  let mut py = y0 + reach_step / 2.0
  while py < y1 {
    let mut px = x0 + reach_step / 2.0
    while px < x1 {
      let d = (px - x) * (px - x) + (py - y) * (py - y)
      if d < best_d && !under_another(c, i, px, py) {
        best = Some((px, py))
        best_d = d
      }
      px = px + reach_step
    }
    py = py + reach_step
  }
  best
}

///|
/// How far apart the points of words in sight are tried for one a finger reaches (reach_point), in points.
let reach_step : Double = 4.0

///|
/// Whether (x, y), where node `i` is, is another's to press: the hit target there neither the node (a paragraph's
/// links its own) nor what holds it.
fn under_another(c : Ctx, i : Int, x : Double, y : Double) -> Bool {
  // (a press there taken by a node of the window's tree: it, or what it is pressed through, is that node's; else what
  // the tree takes there lies over it)
  match view_presses_at(x, y) {
    Some(n) => {
      let mut j = i
      let mut up = 0
      while j >= 0 && j < c.count && up < c.count {
        if c.nodes[j].press_node is Some(m) && m == n {
          return false
        }
        j = c.nodes[j].parent
        up += 1
      }
      return true
    }
    None => ()
  }
  let top = hit_in(c.hit_ids, c.hit_rects, x, y)
  if top == 0 {
    return false
  }
  if c.nodes[i].rich is Some(r) {
    for k, run in r.runs {
      if run.link != "" && link_id(r.base, r.runs, k) == top {
        return false
      }
    }
  }
  let mut j = i
  let mut up = 0
  while j >= 0 && j < c.count && up < c.count {
    // (it, what holds it, or what takes the presses on either: Ctx::presses_to)
    if c.nodes[j].id == top || (c.nodes[j].press_owner is Some((a, _)) && a == top) {
      return false
    }
    j = c.nodes[j].parent
    up += 1
  }
  true
}

///|
/// The words a field holds, as it shows them (a secret one's masked): what `field:WORDS` looks for (a field's own text
/// node is its placeholder).
fn field_words_of(c : Ctx, n : Node) -> String {
  match c.editors.get(n.id) {
    Some(st) => st.shown()
    None => ""
  }
}

///|
/// The words looked for on screen with their node: (x, y, node, where they are: x0 y0 x1 y1).
fn on_screen_nodes(
  c : Ctx,
  what : String,
) -> Array[(Double, Double, Int, (Double, Double, Double, Double))] {
  let found = []
  // a switch by what it turns (its label in the semantics tree, whole): the switch alone takes the press, not the
  // words beside it (sf's switch rows)
  if what.has_prefix("switch:") {
    let label = what.unsafe_substring(start=7, end=what.length())
    for sem in c.sems {
      if sem.role is Switch && sem.label == label && !sem.hidden && sem.node >= 0 && sem.node < c.count {
        let n = c.nodes[sem.node]
        let x = n.x + n.fw / 2.0
        let y = n.y + n.fh / 2.0
        if n.fw > 0.0 && n.fh > 0.0 && !c.in_draw_only(sem.node) && x >= 0.0 && x <= c.width && y >= 0.0 && y <= c.height {
          found.push((x, y, sem.node, (n.x, n.y, n.x + n.fw, n.y + n.fh)))
        }
      }
    }
    return found
  }
  let icon = if what.has_prefix("icon:") {
    Some("/icon/" + what.unsafe_substring(start=5, end=what.length()) + "/")
  } else if what.has_prefix("img:") {
    // an image by its source (a chat's file: its key ends with the file's name)
    Some(what.unsafe_substring(start=4, end=what.length()))
  } else {
    None
  }
  let field = if what.has_prefix("field:") && what.length() > 6 {
    Some(what.unsafe_substring(start=6, end=what.length()))
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
      Some(k) => (n.kind == kind_image || n.shapes.length() > 0) && n.text.contains(k)
      None =>
        // a box by what it is called (its label, whole), as Compose's test finds a node by its contentDescription
        (n.kind == kind_box && n.label != "" && field is None && n.label == exact.unwrap_or(what)) ||
        (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) &&
        (match field {
          // a field by the words in it (`field:WORDS`), not its placeholder
          Some(w) => n.kind == kind_editor && field_words_of(c, n).contains(w)
          None =>
            match exact {
              Some(e) => n.text == e
              None => n.text.contains(what)
            }
        })
    }
    // (not what a page's bones are made of: not there yet, bones.mbt)
    if hit && n.bones == 0L && n.fw > 0.0 && n.fh > 0.0 && !c.in_draw_only(i) {
      // where it is laid out: where it is tapped (a look moves only what is drawn: draw.mbt); in rich text, the
      // middle of the words looked for (a link in a paragraph, a word in a long line of code), and their box
      let whole = (n.x, n.y, n.x + n.fw, n.y + n.fh)
      let (x0, y0, x1, y1) = match (n.rl, exact) {
        (Some(rl), None) =>
          match n.text.find(what) {
            Some(k) =>
              match rl.rects(k, k + what.length()).get(0) {
                Some(r) => {
                  let rx = n.x + n.pad_l + r.0
                  let ry = n.y + n.pad_t + r.1
                  (rx, ry, rx + r.2, ry + r.3)
                }
                None => whole
              }
            None => whole
          }
        _ => whole
      }
      let x = (x0 + x1) / 2.0
      let y = (y0 + y1) / 2.0
      if x >= 0.0 && x <= c.width && y >= 0.0 && y <= c.height {
        found.push((x, y, i, (x0, y0, x1, y1)))
      }
    }
  }
  found
}

///|
/// Why a step that presses on `what` found nothing to press, after `ms`: not on screen, or only under something else.
fn not_reachable(c : Ctx, what : String, ms : Double) -> String {
  if on_screen(c, what).length() == 0 {
    "not on screen after \{ms.to_int()} ms"
  } else {
    "on screen but under something else to press (what lies over it: a composer, a sheet, a scrim) after " +
    "\{ms.to_int()} ms: " +
    on_screen_nodes(c, what).map(fn(p) { over_it(c, p.0, p.1) }).join("; ")
  }
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
/// The host's way of sending a step's input (@hostapi.drive); a test's fake host has none.
fn h_drive(kind : Int, text : String) -> Bool {
  match fake.val {
    Some(_) => false
    None => @hostapi.drive(kind, text)
  }
}

///|
/// The run over: the app ends with its verdict (a test's fake host notes it).
fn drive_end(code : Int) -> Unit {
  h_log(if code == 0 { "DRIVE PASS" } else { "DRIVE END \{code}" })
  driver.val = None
  match fake.val {
    Some(f) => f.logs.push("EXIT \{code}")
    None => @hostapi.exit(code)
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
fn press(x : Double, y : Double, up : Bool) -> Unit {
  on_pointer(0, x, y, 0)
  if up {
    on_pointer(2, x, y, 0)
  }
}

///|
/// Runs the script's steps due this frame (after it was drawn): steps that only look run on at once; one that acts
/// ends the frame's turn, so the app sees it before the next (its input's frames). The run asks for no frame of its
/// own: what it waits for on screen comes with a frame (an input's, a message's, a motion's, the host's event); what
/// it waits for in time (a step's timeout, a hold let go, a pause, a shot taken by another) is a wake at that time.
fn drive_frame(c : Ctx) -> Unit {
  drive_steps(c)
  guard driver.val is Some(d) else { return }
  let now = h_now()
  let mut at = @double.infinity
  let soon = fn(t : Double) { if t < at { at = t } }
  if d.release_at >= 0.0 {
    soon(d.release_at)
  }
  if d.shot_at >= 0.0 {
    soon(d.shot_at + shot_taker_ms)
  }
  if d.since >= 0.0 && d.at < d.steps.length() {
    let line = d.steps[d.at]
    if line.has_prefix("wait ") {
      // (a pause ends at its own time, never timed out: one longer than the timeout woke at no moment past it)
      soon(d.since + number(line.unsafe_substring(start=5, end=line.length())))
    } else {
      soon(d.since + d.timeout)
    }
    // what it saw end wants a frame drawn after it
    if d.seen_frame >= 0 {
      soon(now)
    }
  }
  if at < @double.infinity {
    c.wake_at_time(dmax(at, now), later=true)
  }
}

///|
/// How long a shot the host cannot take itself is left for whoever takes it (adb's screencap: "SHOT NAME").
let shot_taker_ms : Double = 1500.0

///|
fn drive_steps(c : Ctx) -> Unit {
  guard driver.val is Some(d) else { return }
  let now = h_now()
  if d.release_at >= 0.0 {
    if now < d.release_at {
      return
    }
    on_pointer(2, d.rx, d.ry, 0)
    d.release_at = -1.0
    d.at = d.at + 1
    d.since = -1.0
    return
  }
  if d.bms > 0.0 {
    // the system's back gesture on its way: a step this frame, gone through (or called off) once all the way
    let f = dmin((now - d.bt0) / d.bms, 1.0)
    let x = if d.bedge == 1 { c.width - d.bdx * f } else { d.bdx * f }
    on_back(1, x, f, d.bedge)
    if f >= 1.0 {
      on_back(if d.boff { 3 } else { 2 }, x, f, d.bedge)
      d.bms = 0.0
      d.at = d.at + 1
      d.since = -1.0
    }
    return
  }
  if d.gms > 0.0 {
    // a drag on its way: a move this frame, lifted once all the way (`holdon`'s held still till it sets out)
    if now < d.gt0 {
      return
    }
    let f = dmin((now - d.gt0) / d.gms, 1.0)
    let x = d.gx + d.gdx * f
    let y = d.gy + d.gdy * f
    on_pointer(1, x, y, 0)
    if f >= 1.0 && now >= d.gt0 + d.gms + d.gstay {
      d.gstay = 0.0
      on_pointer(2, x, y, 0)
      d.gms = 0.0
      d.at = d.at + 1
      d.since = -1.0
    }
    return
  }
  while d.at < d.steps.length() {
    let line = d.steps[d.at]
    if d.since < 0.0 {
      d.since = now
      d.seen_frame = -1
      tell_step(line, Began)
    }
    let waited = now - d.since
    // (`now STEP`: STEP)
    let line = if line.has_prefix("now ") {
      line.unsafe_substring(start=4, end=line.length()).trim(chars=" ").to_string()
    } else {
      line
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
      d.shot_at = -1.0
    }
    // a step that acted: its input's frames come next; what it set off from outside is counted from here
    let raw = d.steps[d.at]
    let acted = fn() {
      tell_step(raw, Acted)
      next()
      d.count_answers()
      d.mark = runtime().outside_ended()
      d.shown_mark = d.shown
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
      "empty" if arg == "now" =>
        if field_words(c) == "" {
          h_log("DRIVE ok \{line}")
          next()
        } else {
          drive_fail(c, d, "the focused field holds \"\{field_words(c)}\"")
          return
        }
      "said" => {
        let mut k = d.said_taken
        while k < app_said.length() && !app_said[k].contains(arg) {
          k = k + 1
        }
        if k < app_said.length() {
          d.said_taken = k + 1
          h_log("DRIVE ok \{line} (\{waited.to_int()} ms): \{app_said[k]}")
          next()
        } else if waited > d.timeout {
          let last = if app_said.is_empty() { "none" } else { app_said[app_said.length() - 1] }
          drive_fail(c, d, "not said after \{d.timeout.to_int()} ms (the last: \{last})")
          return
        } else {
          return
        }
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
      "outside_done" | "shown" => {
        // what it names done outside (or the app shown again) since the last step that acted, and a frame drawn after
        // the one that saw it
        let come = if cmd == "shown" {
          d.shown > d.shown_mark
        } else {
          let named = []
          for w in runtime().outside_ended_since(d.mark) {
            if w.contains(arg) {
              named.push(w)
            }
          }
          // (one thing named: more than one done, the name does not say which the run means)
          if named.length() > 1 {
            drive_fail(c, d, "\{arg} names more than one thing done outside: \{named.join("; ")}")
            return
          }
          named.length() == 1
        }
        if d.seen_frame < 0 && come {
          d.seen_frame = c.frame_no
        }
        if d.seen_frame >= 0 && c.frame_no > d.seen_frame {
          h_log("DRIVE ok \{line} (\{waited.to_int()} ms)")
          next()
        } else if waited > d.timeout {
          drive_fail(c, d, "not so after \{d.timeout.to_int()} ms (awaiting \{runtime().awaiting()} from outside)")
          return
        } else {
          return
        }
      }
      "answered" | "decoded" | "ready" => {
        // what it names ended since the step began (an answer: one no earlier line took), and a frame drawn after the
        // one that saw it
        let taken = if cmd == "answered" { d.answers_taken.get(arg).unwrap_or(0) } else { 0 }
        let come = if cmd == "answered" {
          d.count_answers()
          d.answers.get(arg).unwrap_or(0) > taken
        } else {
          runtime().outside_ended_since(d.mark).iter().any(fn(w) { outside_named(cmd, arg, w) })
        }
        if d.seen_frame < 0 && come {
          d.seen_frame = c.frame_no
        }
        if d.seen_frame >= 0 && c.frame_no > d.seen_frame {
          h_log("DRIVE ok \{line} (\{waited.to_int()} ms)")
          if cmd == "answered" {
            d.answers_taken[arg] = taken + 1
          }
          next()
        } else if waited > d.timeout {
          drive_fail(c, d, "not so after \{d.timeout.to_int()} ms (awaiting \{runtime().awaiting()} from outside)")
          return
        } else {
          return
        }
      }
      "done" => {
        if !d.watching {
          drive_fail(
            c,
            d,
            "the host watches no directory of the runner's (MBUI_DONE_DIR or MBUI_SHOT_DIR unset, or the host has " +
            "none: a Tester's, the web's, iOS's)",
          )
          return
        }
        match d.runner_done.get(arg) {
          Some(said) =>
            match said.trim(chars=" \n\r\t").to_string() {
              "" | "ok" => {
                h_log("DRIVE ok \{line} (\{waited.to_int()} ms)")
                next()
              }
              why => {
                drive_fail(c, d, "the runner did not do it: \{why}")
                return
              }
            }
          None =>
            if waited > d.timeout {
              drive_fail(c, d, "not done after \{d.timeout.to_int()} ms (the runner said nothing of it)")
              return
            } else {
              return
            }
        }
      }
      "notice" | "noticed" | "nonotice" => {
        // the host's notifications (@hostapi.drive 6: tapped, 7: looked for)
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
        let at = reachable(c, arg)
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, not_reachable(c, arg, d.timeout))
          }
          return
        }
        let (x, y) = if cmd == "tap1" { topmost(at) } else { lowest(at) }
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
        let at = reachable(c, what)
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, not_reachable(c, what, d.timeout))
          }
          return
        }
        let (x, y) = lowest(at)
        tell_step(d.steps[d.at], Acted)
        press(x, y, false)
        d.rx = x
        d.ry = y
        d.release_at = now + ms
        return
      }
      "holdon" => {
        // `holdon MS DX DY MOVE TEXT`: held still on TEXT MS, then dragged DX DY over MOVE ms (a long press slid on)
        let words = arg.split(" ").map(fn(v) { v.to_string() }).to_array()
        if words.length() < 5 {
          drive_fail(c, d, "holdon MS DX DY MOVE TEXT")
          return
        }
        let what = words[4:].to_owned().join(" ")
        // (`@X,Y`: there, words in a field being none of what is on screen to find)
        let at = if what.has_prefix("@") {
          match what.find(",") {
            Some(i) => {
              let x = number(what.unsafe_substring(start=1, end=i))
              [(x, number(what.unsafe_substring(start=i + 1, end=what.length())))]
            }
            None => []
          }
        } else {
          reachable(c, what)
        }
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, not_reachable(c, what, d.timeout))
          }
          return
        }
        let (x, y) = lowest(at)
        d.gx = x
        d.gy = y
        d.gdx = number(words[1])
        d.gdy = number(words[2])
        d.gms = dmax(number(words[3]), 16.0)
        d.gt0 = now + number(words[0])
        d.gstay = number(words[0])
        h_log("DRIVE holdon \{arg} from \{x.to_int()},\{y.to_int()}")
        tell_step(d.steps[d.at], Acted)
        on_pointer(0, x, y, 0)
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
          let at = reachable(c, what)
          if at.length() == 0 {
            if waited > d.timeout {
              drive_fail(c, d, not_reachable(c, what, d.timeout))
            }
            return
          }
          let (x, y) = lowest(at)
          (x, y, words[0:3].to_owned())
        }
        d.gx = x
        d.gy = y
        d.gdx = number(rest[0])
        d.gdy = if rest.length() > 1 { number(rest[1]) } else { 0.0 }
        d.gms = if rest.length() > 2 { dmax(number(rest[2]), 16.0) } else { 300.0 }
        d.gt0 = now
        h_log("DRIVE \{cmd} \{arg} from \{x.to_int()},\{y.to_int()}")
        tell_step(d.steps[d.at], Acted)
        on_pointer(0, x, y, 0)
        return
      }
      "backswipe" => {
        let words = arg.split(" ").map(fn(v) { v.to_string() }).to_array()
        d.bdx = number(words[0])
        d.bms = 300.0
        d.bedge = 0
        d.boff = false
        for w in words[1:] {
          match w {
            "right" => d.bedge = 1
            "off" => d.boff = true
            _ => d.bms = dmax(number(w), 16.0)
          }
        }
        d.bt0 = now
        h_log("DRIVE backswipe \{arg}")
        tell_step(d.steps[d.at], Acted)
        on_back(0, if d.bedge == 1 { c.width } else { 0.0 }, 0.0, d.bedge)
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
          on_text(text_paste, words, 0, 0)
        }
        acted()
        return
      }
      "wheel" => {
        // (DY, then what is held with it: cmd, ctrl, alt, shift joined by +, as a key's are said)
        let (dy, held) = match arg.find(" ") {
          Some(i) => (arg.view(end_offset=i).to_string(), arg.view(start_offset=i + 1).to_string())
          None => (arg, "")
        }
        let mut mods = 0
        for m in held.split("+") {
          match m.to_string() {
            "cmd" => mods = mods | wheel_mod_cmd
            "ctrl" => mods = mods | wheel_mod_ctrl
            "alt" | "option" => mods = mods | wheel_mod_alt
            "shift" => mods = mods | wheel_mod_shift
            "" => ()
            other => {
              drive_fail(c, d, "wheel DY [cmd+ctrl+alt+shift]: \{other}")
              return
            }
          }
        }
        on_wheel(c.width / 2.0, c.height / 2.0, 0.0, number(dy), mods * 16)
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
      "hover" | "rightclick" | "wheelat" | "wheelxat" => {
        let (dy, what) = if cmd == "wheelat" || cmd == "wheelxat" {
          match arg.find(" ") {
            Some(i) =>
              (
                number(arg.unsafe_substring(start=0, end=i)),
                arg.unsafe_substring(start=i + 1, end=arg.length()),
              )
            None => {
              drive_fail(c, d, cmd + " D TEXT")
              return
            }
          }
        } else {
          (0.0, arg)
        }
        // (a wheel goes to the list under the words, whatever lies over them; a hover or a click is the finger's)
        let at = if cmd == "wheelat" || cmd == "wheelxat" { on_screen(c, what) } else { reachable(c, what) }
        if at.length() == 0 {
          if waited > d.timeout {
            drive_fail(c, d, not_reachable(c, what, d.timeout))
          }
          return
        }
        let (x, y) = lowest(at)
        h_log("DRIVE \{cmd} \{what} at \{x.to_int()},\{y.to_int()}")
        match cmd {
          "hover" => on_pointer(1, x, y, 0)
          "rightclick" => {
            on_pointer(0, x, y, 2)
            on_pointer(2, x, y, 2)
          }
          "wheelxat" => on_wheel(x, y, dy, 0.0, 4)
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
      "system" => {
        match fake.val {
          Some(f) => fake_post(f, @hostapi.system_channel, arg, None)
          None => {
            drive_fail(c, d, "system: only a Tester's system says what a script tells it")
            return
          }
        }
        acted()
        return
      }
      "ime" => {
        match fake.val {
          Some(f) => {
            f.dev.ime_inset = number(arg)
            f.wants = true
          }
          None => {
            drive_fail(c, d, "ime: only a Tester's keyboard moves as a script tells it")
            return
          }
        }
        acted()
        return
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
        } else if now - d.shot_at >= shot_taker_ms {
          next()
        } else {
          return
        }
      // the app's state as the host says it from here on (what it said last at once): a run about the app put away
      "hosted" => {
        d.takes_state = true
        h_log("DRIVE ok hosted: the host's word on the app taken (\{d.said_state})")
        app_state_taken(d.said_state)
        next()
      }
      "log" => {
        h_log("DRIVE LOG " + arg)
        next()
      }
      "picks" => {
        match fake.val {
          Some(f) => {
            f.picks.clear()
            for part in arg.split(" ") {
              match part.rev_find(":") {
                Some(i) => {
                  let mut n = 0
                  for ch in part[i + 1:] {
                    n = n * 10 + (ch.to_int() - 48)
                  }
                  let bytes = Bytes::make(n, b'x')
                  f.picks.push({ name: part[:i].to_string(), bytes, held: 0, size: n.to_double(), src: "" })
                }
                None => ()
              }
            }
          }
          None => h_log("DRIVE picks: no Tester here, the host's own pickers answer")
        }
        next()
      }
      // what the frame shows squeezed (squeeze.mbt), a line each
      "squeeze" => {
        for f in c.squeeze_faults() {
          h_log("DRIVE SQUEEZE " + f)
        }
        next()
      }
      // what the frame shows breaking the corner rule (corners.mbt), a line each
      "corners" => {
        for f in c.with_tree_nodes(fn() { c.corner_faults() }) {
          h_log("DRIVE CORNER " + f)
        }
        next()
      }
      // what the frame shows too faint on what it lies on (contrast.mbt), a line each: a frame drawn with whose each
      // thing drawn is kept, then said
      "contrast" =>
        if inst_owners.on {
          inst_owners.on = false
          // (drawn as before from the next frame on, built whole: frame_watch.mbt)
          test_stepped()
          for f in c.contrast_faults_drawn(contrast_mark_least) {
            h_log("DRIVE CONTRAST " + f)
          }
          next()
        } else {
          inst_owners.on = true
          inst_owners_clear()
          c.owe_next()
          return
        }
      "exit" => {
        drive_end(0)
        return
      }
      "ends" => {
        // (the host ends the app, the run with it; nothing here moves on)
        if waited > d.timeout {
          drive_fail(c, d, "the app did not end by itself within \{d.timeout.to_int()} ms")
        }
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
          None => @hostapi.exit(0)
        }
        return
      }
      _ => {
        drive_fail(c, d, "no such step")
        return
      }
    }
  }
  // the script's end, as `exit`
  drive_end(0)
}

///|
/// Runs `script` (as MBUI_DRIVE would) over the tester's view, a frame at each of the display's frames, until it ends
/// (or `max` frames), `each` told after each: what it logged.
pub fn Tester::drive(
  self : Tester,
  script : String,
  max? : Int = 3000,
  each? : (Tester) -> Unit,
) -> Array[String] {
  self.fake.logs.clear()
  drive_start(script, "")
  let mut n = 0
  while driver.val is Some(_) && n < max {
    self.frame()
    if each is Some(f) {
      f(self)
    }
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
      "cmd" => mods = mods | (if h_keys() == 0 { mod_cmd } else { mod_ctrl })
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

///|
/// The core's answers ended since they were last counted, counted by their call's name ("core: NAME (call N)", a
/// subscription's "core: KEY").
fn Driver::count_answers(self : Driver) -> Unit {
  let come = runtime().outside_ended_since(self.counted)
  for w in come {
    if w.has_prefix("core: ") {
      let rest = w.unsafe_substring(start=6, end=w.length())
      let name = match rest.find(" (call ") {
        Some(i) => rest.unsafe_substring(start=0, end=i)
        None => rest
      }
      self.answers[name] = self.answers.get(name).unwrap_or(0) + 1
    }
  }
  self.counted = self.counted + come.length()
}

///|
/// Whether `what` (a wait on outside, as Runtime::outside_ended_since says it) is what the step `cmd` (answered,
/// decoded, ready) names by `arg`.
fn outside_named(cmd : String, arg : String, what : String) -> Bool {
  match cmd {
    // "core: NAME (call N)", a subscription's "core: KEY"
    "answered" => what.has_prefix("core: " + arg + " (call ") || what == "core: " + arg
    // "image N SRC", "image N (B bytes) SRC" (bytes handed over for SRC), "image N (PDF D, page P)"
    "decoded" =>
      what.has_prefix("image ") &&
      (what.has_suffix(arg) || what.contains(" " + arg) || (arg == "PDF" && what.contains("(PDF ")))
    _ =>
      if arg == "pdf" {
        what.has_prefix("image ") && what.contains("(PDF ")
      } else if arg.has_prefix("#") {
        what.has_prefix("view " + arg.unsafe_substring(start=1, end=arg.length()) + " (")
      } else if arg.length() > 0 && arg.iter().all(fn(ch) { ch >= '0' && ch <= '9' }) {
        what.has_prefix("view ") && what.contains("(kind " + arg + ",")
      } else {
        what.has_prefix("view ") && what.has_suffix(", " + arg + ")")
      }
  }
}

///|
/// What a press at (x, y) goes to, for a failure's report: the hit target there, what kind it is, where it is laid out
/// and the first words in it (or nothing there).
fn over_it(c : Ctx, x : Double, y : Double) -> String {
  let top = hit_in(c.hit_ids, c.hit_rects, x, y)
  if top == 0 {
    return "nothing at \{x.to_int()},\{y.to_int()}"
  }
  let what = if drags.contains(top) { "a drag area" } else { "a box taking presses" }
  for k in 0..<c.count {
    let n = c.nodes[k]
    if n.id == top {
      let words = first_words(c, k)
      return "at \{x.to_int()},\{y.to_int()} \{what} \{n.x.to_int()},\{n.y.to_int()} \{n.fw.to_int()}x\{n.fh.to_int()}" +
        (if words == "" { "" } else { " holding \"" + words + "\"" })
    }
  }
  "at \{x.to_int()},\{y.to_int()} \{what} not built this frame"
}

///|
/// The first words under node `i` (itself, then its children in order), "" when none.
fn first_words(c : Ctx, i : Int) -> String {
  let n = c.nodes[i]
  if (n.kind == kind_text || n.kind == kind_rich) && n.text != "" {
    return n.text
  }
  let mut k = n.first
  while k >= 0 {
    let w = first_words(c, k)
    if w != "" {
      return w
    }
    k = c.nodes[k].next
  }
  ""
}
