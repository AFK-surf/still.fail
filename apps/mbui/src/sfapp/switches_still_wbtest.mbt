// What a switch pressed on a page sets moving, its core answering late, held to a table that only falls (the owner's
// recording of 2026-11-13: 添加账号's 添加到 station switched, the line under its title folding and coming again, all
// under it jumping; the coordinator of the migration: find all of them, then keep them as a check on main, 2026-11-13
// and 14). Every screen of corners_wbtest's, on 小屏, 中屏 and 大屏, over a core answering each call and every
// subscription 400 ms late: each switch found by its role and pressed in turn (a radio not chosen, a choice row not
// chosen, a toggle, an opener's every choice not chosen, a switch, a checkbox, a tab of the page), and the screen
// looked at on each frame till its answers have all come: each run of frames in which a named node moves, sizes
// otherwise, comes or goes is one change. A press seen to change more than once is a row of `switches_known`
// (switches_known_wbtest.mbt) with how many times: one more or fewer than its row, or a press with no row, fails its
// test, saying the line to write. Run on main alone, after a merge, in three parts (mbui-check.yml's `switches`; it
// is too long for a branch's pushes); its tests at a rate are none (a sweep: scripts/test.sh).
//
// Not pressed: what leaves the screen (a press that puts another page or place on top is said and not counted), a
// picker's button and its items where the button says no `expanded`, a filter that is a plain button saying no
// `selected`, and what `switches_left_out` names, each with why.
//
// What the judge leaves out, each by its kind, here in one place (the coordinator of the migration, 2026-11-14), all of
// it still printed beside what is counted:
// - the toasts' region (kit's toasts say `Region`): a notice coming and going over the page is no change of the page's;
// - a tip's layer (`Tooltip`): the hand resting on what it pressed shows it, not an answer;
// - a number running while it is seen, by its cause, not by where it is (switch_running): what counts is the press's
//   own look and what the first telling, since the press, of each thing asked brings; a later telling of what was told
//   already since the press (a transfer's progress) and what the clock rebuilds (a countdown, the next episode at its
//   end: Tester::clock_came) happen while it is seen.

///|
/// How late the made-up core answers in each pass (ms).
let switch_paces : Array[Double] = [400.0]

///|
/// The screens the switches are pressed on.
let switches_screens : Array[Screen] = [daily_small, daily_medium, daily_large]

///|
/// The presses left out of the check by name (screen size, screen: switch), each with why: a press whose Tester stops
/// on a fault of its own cannot be counted. Each goes with the change that mends its fault (the coordinator of the
/// migration, 2026-11-14), never one for what it is counted.
let switches_left_out : Map[String, String] = Map([
  (
    "大屏 settings-station-processes: radio 「平铺」",
    // (the processes' table flat on 大屏: its View::by_room measured AtMost 760 and Exactly 760, then laid out by
    // what it holds at 586, its rows side by side at one and stacked at the other, frame after frame, 36 nodes drawn
    // never placed (the Tester's tester_placed stops); the framework's room path is mended in its own PR, which takes
    // this line out)
    "its table laid out at two widths in turn, nodes drawn never placed: View::by_room's own PR",
  ),
])

///|
/// The ids (a subscription's, a call's) of what the made-up core told the client since this was last emptied, in the
/// order told (switch_heard_of): what a frame drawn after them may show.
// kept across runs: emptied as each press is measured, read as each frame after it is
let switch_heard : Array[Int] = []

///|
/// A message between the client and the made-up core (round_trip_again's `heard`): one told the client kept by its id.
fn switch_heard_of(m : String) -> Unit {
  guard m.has_prefix("in ") else { return }
  let j = @json.parse(m.unsafe_substring(start=3, end=m.length())) catch { _ => return }
  guard j is Object(o) && o.get("id") is Some(Number(n, ..)) else { return }
  switch_heard.push(n.to_int())
}

///|
/// `mode`'s screen on `s` over a core answering each call and every subscription `ms` late, at rest.
fn switch_tester(mode : String, s : Screen, ms : Double) -> @ui.Tester {
  switch_leaks("\{s.name} \{mode}: before its fixture")
  let app = fixture_app(mode)
  switch_leaks("\{s.name} \{mode}: its fixture made")
  let src = round_trip_again(@sffixture.round_trip(app, ms), 0.0, heard=switch_heard_of, late=fn(_, _) { ms })
  switch_leaks("\{s.name} \{mode}: its source made")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  t.motion_unjudged(true)
  t.draw()
  t.run_for(ms * 8.0 + @ui.move_most_ms + 1000.0)
  t.ways_set_out() |> ignore
  t
}

///|
/// The switches on `t`'s screen now, each its kind and name: radios not chosen, choice rows not chosen, switches,
/// checkboxes, tabs not chosen.
fn switches_on(t : @ui.Tester) -> Array[(String, @ui.Role, String)] {
  let out = []
  for n in t.all(Radio, checked=Off) {
    out.push(("radio", n.role, n.label))
  }
  for n in t.all(Button) {
    if n.selected == Some(false) {
      out.push(("choice row", n.role, n.label))
    } else if n.pressed is Some(_) {
      out.push(("toggle", n.role, n.label))
    } else if n.expanded == Some(false) {
      out.push(("opener", n.role, n.label))
    }
  }
  for n in t.all(Switch) {
    out.push(("switch", n.role, n.label))
  }
  for n in t.all(Checkbox) {
    out.push(("checkbox", n.role, n.label))
  }
  for n in t.all(Tab) {
    if n.selected != Some(true) {
      out.push(("tab", n.role, n.label))
    }
  }
  out
}

///|
/// What is on top of `t`'s app: a press that changes it left the screen.
fn switch_top() -> String {
  "\{@sfbase.page_kind(app.nav.top())} \{app.nav.depth()}"
}

///|
/// The screens the switches are pressed on: corners_wbtest's, and those whose switches no corner mode shows (添加账号 with
/// three stations up: #6030).
let switches_modes : Array[String] = corner_modes + ["settings-new-profile-stations"]

///|
/// A switch's key on a screen: its kind, name and which of those of that kind and name it is.
fn switch_key(sw : (String, @ui.Role, String), seen : Map[String, Int]) -> String {
  let base = "\{sw.0} 「\{sw.2}」"
  let n = seen.get(base).unwrap_or(0)
  seen[base] = n + 1
  if n == 0 {
    base
  } else {
    "\{base} #\{n + 1}"
  }
}

///|
/// The switches on `t`'s screen now, by key (switch_key).
fn switches_keyed(t : @ui.Tester) -> Array[(String, (String, @ui.Role, String))] {
  let seen : Map[String, Int] = Map([])
  switches_on(t).map(fn(sw) { (switch_key(sw, seen), sw) })
}

///|
/// The node of switch `sw` (its `nth` of its role and name), brought into the window where it is out of it (a wheel
/// over the middle of the window towards it, a few times at most): None where it is not there or never comes in.
fn switch_node(t : @ui.Tester, s : Screen, sw : (String, @ui.Role, String), nth : Int) -> @ui.SemNode? {
  let find = fn() {
    let all = t.all(sw.1, label=sw.2).filter(fn(n) { !n.disabled })
    if nth < all.length() {
      Some(all[nth])
    } else {
      None
    }
  }
  for tries = 0; tries < 12; tries = tries + 1 {
    guard find() is Some(n) else { return None }
    let (x, y, w, h) = n.rect
    let cx = x + w / 2.0
    let cy = y + h / 2.0
    if w > 0.0 && h > 0.0 && cx >= 0.0 && cy >= 0.0 && cx <= s.w && cy <= s.h {
      return Some(n)
    }
    if cy >= 0.0 && cy <= s.h && (cx < 0.0 || cx > s.w) {
      // (in the window's height, off it to a side: a strip that scrolls sideways, wheeled where it is)
      let dx = if cx > s.w { @cmp.minimum(cx - s.w / 2.0, s.w * 0.8) } else { @cmp.maximum(cx - s.w / 2.0, -s.w * 0.8) }
      t.wheel_with(s.w / 2.0, @cmp.minimum(@cmp.maximum(cy, 1.0), s.h - 1.0), dx, 0.0, 0)
    } else {
      let dy = if cy > s.h { @cmp.minimum(cy - s.h / 2.0, s.h * 0.8) } else { @cmp.maximum(cy - s.h / 2.0, -s.h * 0.8) }
      t.wheel(s.w / 2.0, s.h / 2.0, dy)
    }
    t.run_for(@ui.move_most_ms)
  }
  None
}

///|
/// How long after a press `ms` late its answers have all come and their changes ended.
fn switch_settle(ms : Double) -> Double {
  ms * 5.0 + @ui.move_most_ms + 500.0
}

///|
/// Where the named nodes of `t`'s screen are now, by role and name, each cut to what holds it (a node its holders cut to
/// nothing, as a row closed to nothing does what is in it, is none). What is in the toasts' region (`Region`) or a tip
/// (`Tooltip`) is none of the page's: left out (the file's head).
fn switch_places(t : @ui.Tester) -> Map[String, (Double, Double, Double, Double)] {
  // (each node's `parent` is where its holder is in this same list)
  let all = t.semantics()
  let out : Map[String, (Double, Double, Double, Double)] = Map([])
  for n in all {
    if n.label == "" || n.hidden || switch_over_page(n) {
      continue
    }
    let (x, y, w, h) = n.rect
    let mut x0 = x
    let mut y0 = y
    let mut x1 = x + w
    let mut y1 = y + h
    let mut up = n.parent
    let mut steps = 0
    let mut over = false
    while steps < 64 {
      steps = steps + 1
      guard up >= 0 && up < all.length() else { break }
      let p = all[up]
      if switch_over_page(p) {
        over = true
        break
      }
      let (px, py, pw, ph) = p.rect
      x0 = @cmp.maximum(x0, px)
      y0 = @cmp.maximum(y0, py)
      x1 = @cmp.minimum(x1, px + pw)
      y1 = @cmp.minimum(y1, py + ph)
      up = p.parent
    }
    if !over && x1 - x0 >= 1.0 && y1 - y0 >= 1.0 {
      out["\{Repr(n.role)} \{n.label}"] = n.rect
    }
  }
  out
}

///|
/// Whether node `n` is what shows over the page and is none of its own: the toasts' region, a tip (the file's head).
fn switch_over_page(n : @ui.SemNode) -> Bool {
  n.role == Region || n.role == Tooltip
}

///|
/// One change a press set going (switch_measure): from when to when after it (ms), whether bones were drawn in it, the
/// first few things it changed, and whether it is a number running while it is seen (switch_running).
struct SwitchChange {
  from : Double
  to : Double
  bones : Bool
  what : Array[String]
  running : Bool
  why : String
}

///|
/// Whether a frame after a press, one that differs from the frame before, shows a number running while it is seen
/// rather than the press's own look or what a first answer brought (the file's head): not the press's frame, nothing
/// told for the first time since the press among what came before it (`first`), and what came a later telling of
/// what was told already (`later`), or the frame drawn as a moment only the clock brings came or the one after such a
/// frame, what that one's build set going (`clock`: Tester::clock_came; a countdown's next second, the next episode at
/// its end).
fn switch_running(pressed : Bool, first : Bool, later : Bool, clock : Bool) -> Bool {
  !pressed && !first && (later || clock)
}

///|
/// What `t`'s screen does from the press `press` makes (at `from`) till it has had time to settle, `ms` late: each
/// frame at 60, the moments it differs from the frame before by a named node moved, sized otherwise, come or gone
/// (`skip`'s, the pressed control's own and what it opened, not counted); frames in a row that differ are one change,
/// a way's: running (switch_running) where every frame of it is. Stops where what is on top is no longer `top`.
fn switch_measure(
  t : @ui.Tester,
  press : () -> Unit,
  skip : Map[String, Bool],
  top : String,
  ms : Double,
) -> (Double, Array[SwitchChange]) {
  let from = t.time()
  let mut last = switch_places(t)
  // (what was told since the press, by id: a later telling of one of them is no first answer)
  let told : Map[Int, Bool] = Map([])
  switch_heard.clear()
  t.clock_came(from) |> ignore
  press()
  let changes : Array[SwitchChange] = []
  let mut run_from = -1.0
  let mut run_to = 0.0
  let mut run_bones = false
  let mut run_what : Array[String] = []
  let mut run_running = true
  let mut run_why = ""
  let mut first = true
  // (whether the frame before was drawn as a moment only the clock brings came)
  let mut clock_before = false
  while t.time() < from + switch_settle(ms) {
    let pressed = first
    if first {
      first = false
    } else {
      t.frame_at(t.time() + 1000.0 / 60.0)
    }
    let mut first_told = false
    let mut later = false
    for id in switch_heard {
      if told.contains(id) {
        later = true
      } else {
        told[id] = true
        first_told = true
      }
    }
    switch_heard.clear()
    let came = t.clock_came(t.time())
    let clock = came || clock_before
    clock_before = came
    if switch_top() != top {
      break
    }
    let here = switch_places(t)
    let what = []
    for k, r in here {
      if skip.contains(k) {
        continue
      }
      match last.get(k) {
        Some(was) =>
          if (r.0 - was.0).abs() > 1.0 || (r.1 - was.1).abs() > 1.0 || (r.2 - was.2).abs() > 1.0 ||
            (r.3 - was.3).abs() > 1.0 {
            what.push("\{k} \{Repr(was)} -> \{Repr(r)}")
          }
        None => what.push("\{k} came \{Repr(r)}")
      }
    }
    for k, r in last {
      if !skip.contains(k) && !here.contains(k) {
        what.push("\{k} gone \{Repr(r)}")
      }
    }
    let now = t.time() - from
    if what.length() > 0 {
      if run_from < 0.0 {
        run_from = now
        run_bones = false
        run_what = []
        run_running = true
        run_why = (if pressed { "the press" } else if first_told { "a first answer" } else if later { "a later telling" } else if clock { "the clock" } else { "" }) +
          " / built: " + t.built_why()
      }
      run_to = now
      run_bones = run_bones || t.bones_drawn() > 0
      run_running = run_running && switch_running(pressed, first_told, later, clock)
      for x in what {
        if run_what.length() < 6 {
          run_what.push(x)
        }
      }
    } else if run_from >= 0.0 {
      changes.push({ from: run_from, to: run_to, bones: run_bones, what: run_what, running: run_running, why: run_why })
      run_from = -1.0
    }
    last = here
  }
  if run_from >= 0.0 {
    changes.push({ from: run_from, to: run_to, bones: run_bones, what: run_what, running: run_running, why: run_why })
  }
  (from, changes)
}

///|
/// What a press measured (switch_measure) printed: the ways that set out after it (a toast's own coming and going left
/// out), its changes counted and those running, when, and where it changed more than once what each changed; and its
/// row (`row`, the press's screen size, screen and switch) where it changed more than once, kept in `found` with how
/// many times.
fn switch_said(
  t : @ui.Tester,
  at : String,
  row : String,
  from : Double,
  changes : Array[SwitchChange],
  found : Map[String, Int],
) -> Unit {
  let ways = t.ways_set_out().filter(fn(w) { w.at > from + 0.5 && !w.made.contains("kit/toast_node.mbt") })
  let counted = changes.filter(fn(c) { !c.running }).length()
  let running = changes.length() - counted
  let said = changes.map(fn(c) {
    "+\{c.from.round()}" +
    (if c.to > c.from { "..\{c.to.round()}" } else { "" }) +
    (if c.bones { " bones" } else { "" }) +
    (if c.running { " running" } else { "" })
  })
  println("SWITCHES_PRESSED \{at}: \{ways.length()} ways, \{counted} changes, \{running} running \{said.join(" ")}")
  for w in ways {
    println("SWITCHES_WAY \{at}: \{w.kind} +\{(w.at - from).round()} ms \{w.made} \{w.part}")
  }
  if changes.length() > 1 {
    for c in changes {
      println("SWITCHES_CAUSE \{at}: +\{c.from.round()} \{c.why}")
      for x in c.what {
        println("SWITCHES_CHANGE \{at}: +\{c.from.round()}\{if c.running { " running" } else { "" }} \{x}")
      }
    }
  }
  // (the table's line, what is left out as running beside what is counted: seen, not hidden)
  if counted > 1 || running > 0 {
    println("SWITCHES_ROW \{row}\t\{counted}\t\{running}")
  }
  if counted > 1 {
    found[row] = counted
  }
}

///|
/// The choices not chosen that what is open on `t`'s screen shows now (a menu's or a pick's radios), by name.
fn switch_choices(t : @ui.Tester) -> Array[String] {
  t.semantics().filter(fn(n) { !n.hidden && n.role == MenuItemRadio && n.check == Some(Off) && n.label != "" }).map(fn(n) {
    n.label
  })
}

///|
/// Each switch on `mode`'s screen on `s`, `ms` late, pressed in turn, found anew after each press (a screen opened
/// again where a press took away one not pressed yet); what opens a menu or a pick pressed in two steps, it and then
/// each choice it shows not chosen; what each press set going printed and, where it changed more than once, kept in
/// `found` (switch_said). What `switches_left_out` names is said and not pressed.
fn switches_walk(mode : String, s : Screen, ms : Double, found : Map[String, Int]) -> Unit {
  let pressed : Map[String, Bool] = Map([])
  for opened = 0; opened < 6; opened = opened + 1 {
    let t = switch_tester(mode, s, ms)
    switch_leaks("\{s.name} \{mode}, core \{ms} ms: opened")
    let top = switch_top()
    let mut again = false
    while true {
      let now = switches_keyed(t)
      let next = now.iter().find_first(fn(k) { !pressed.contains(k.0) })
      guard next is Some((key, sw)) else { break }
      pressed[key] = true
      let at = "\{s.name} \{mode}, core \{ms} ms: \{key}"
      let row = "\{s.name} \{mode}: \{key}"
      if sw.2 == "" {
        println("SWITCHES_UNNAMED \{at}")
        continue
      }
      if switches_left_out.get(row) is Some(why) {
        println("SWITCHES_LEFT_OUT \{at}: \{why}")
        continue
      }
      let nth = now.filter(fn(k) { k.1.0 == sw.0 && k.1.2 == sw.2 }).search_by(fn(k) { k.0 == key }).unwrap_or(0)
      guard switch_node(t, s, sw, nth) is Some(node) else {
        println("SWITCHES_UNREACHED \{at}")
        continue
      }
      let own = "\{Repr(sw.1)} \{sw.2}"
      println("SWITCHES_TRY \{at}")
      if sw.0 == "opener" {
        // (opened, its choices read, shut again; then each: opened again, the choice pressed, measured from there)
        let (x, y, w, h) = node.rect
        let shut = switch_places(t)
        t.tap(x + w / 2.0, y + h / 2.0)
        t.run_for(@ui.move_most_ms)
        let choices = switch_choices(t)
        let menu : Map[String, Bool] = Map([(own, true)])
        for k, _ in switch_places(t) {
          if !shut.contains(k) {
            menu[k] = true
          }
        }
        t.key(@ui.key_escape)
        t.run_for(@ui.move_most_ms)
        if choices.length() == 0 {
          println("SWITCHES_NO_CHOICES \{at}")
        }
        for choice in choices {
          let at2 = "\{at} › 「\{choice}」"
          let row2 = "\{row} › 「\{choice}」"
          if switches_left_out.get(row2) is Some(why) {
            println("SWITCHES_LEFT_OUT \{at2}: \{why}")
            continue
          }
          guard switch_node(t, s, sw, nth) is Some(o) else {
            println("SWITCHES_UNREACHED \{at2}")
            continue
          }
          let (x, y, w, h) = o.rect
          println("SWITCHES_TRY \{at2}")
          t.tap(x + w / 2.0, y + h / 2.0)
          t.run_for(@ui.move_most_ms)
          let item = t.semantics().iter().find_first(fn(n) { !n.hidden && n.role == MenuItemRadio && n.label == choice })
          guard item is Some(it) else {
            println("SWITCHES_UNREACHED \{at2}")
            t.key(@ui.key_escape)
            t.run_for(@ui.move_most_ms)
            continue
          }
          let (ix, iy, iw, ih) = it.rect
          t.ways_set_out() |> ignore
          let (from, changes) = switch_measure(t, fn() { t.tap(ix + iw / 2.0, iy + ih / 2.0) }, menu, top, ms)
          if switch_top() != top {
            println("SWITCHES_LEFT \{at2}")
            again = true
            break
          }
          switch_leaks(at2)
          switch_said(t, at2, row2, from, changes, found)
        }
        if again {
          break
        }
      } else {
        let (x, y, w, h) = node.rect
        t.ways_set_out() |> ignore
        let (from, changes) = switch_measure(t, fn() { t.tap(x + w / 2.0, y + h / 2.0) }, Map([(own, true)]), top, ms)
        switch_leaks(at)
        if switch_top() != top {
          println("SWITCHES_LEFT \{at}")
          again = true
          break
        }
        switch_said(t, at, row, from, changes, found)
      }
      // (a switch there before not pressed and gone now: this screen opened again for the rest)
      let after = switches_keyed(t).map(fn(k) { k.0 })
      if now.iter().any(fn(k) { !pressed.contains(k.0) && !after.contains(k.0) }) {
        again = true
        break
      }
    }
    switch_leaks("\{s.name} \{mode}, core \{ms} ms: its end")
    if !again {
      return
    }
  }
  switch_leaks("\{s.name} \{mode}, core \{ms} ms: opened six times")
}

///|
/// What `found` (each press of the screens `walked` names that changed more than once, by its row, with how many
/// times) says against `switches_known`: each line to write there, none where they agree. A row whose screen this run
/// did not walk is another test's.
fn switches_against_known(walked : Array[String], found : Map[String, Int]) -> Array[String] {
  let out = []
  for row, n in found {
    match switches_known.get(row) {
      None => out.push("\{row}: changes \{n} times, and has no row in switches_known (a press changes once: mend it)")
      Some(k) if n > k => out.push("\{row}: changes \{n} times, more than its row's \{k} (a press changes once: mend it)")
      Some(k) if n < k => out.push("\{row}: changes \{n} times, its row says \{k}: write (\"\{row}\", \{n}) there")
      Some(_) => ()
    }
  }
  for row, k in switches_known {
    if walked.iter().any(fn(w) { row.has_prefix(w) }) && !found.contains(row) {
      out.push("\{row}: changes once at most now, its row says \{k}: take its row out of switches_known")
    }
  }
  out.sort()
  out
}

///|
/// Each switch of every screen in `part` of `parts` of switches_modes (every `parts`-th from `part`: a test each, so a
/// screen whose Tester stops on a fault of its own stops that part alone), on each screen size, at each pace, held to switches_known.
fn switches_part(part : Int, parts : Int) -> Unit raise {
  let found : Map[String, Int] = Map([])
  let walked = []
  for i, mode in switches_modes {
    if i % parts != part {
      continue
    }
    for s in switches_screens {
      walked.push("\{s.name} \{mode}: ")
      for ms in switch_paces {
        switches_walk(mode, s, ms, found)
      }
    }
  }
  let said = switches_against_known(walked, found)
  if said.length() > 0 {
    fail("switches still against switches_known:\n" + said.join("\n"))
  }
}

///|
test "switches still: screen 1" {
  switches_part(0, 320)
}

///|
test "switches still: screen 2" {
  switches_part(1, 320)
}

///|
test "switches still: screen 3" {
  switches_part(2, 320)
}

///|
test "switches still: screen 4" {
  switches_part(3, 320)
}

///|
test "switches still: screen 5" {
  switches_part(4, 320)
}

///|
test "switches still: screen 6" {
  switches_part(5, 320)
}

///|
test "switches still: screen 7" {
  switches_part(6, 320)
}

///|
test "switches still: screen 8" {
  switches_part(7, 320)
}

///|
test "switches still: screen 9" {
  switches_part(8, 320)
}

///|
test "switches still: screen 10" {
  switches_part(9, 320)
}

///|
test "switches still: screen 11" {
  switches_part(10, 320)
}

///|
test "switches still: screen 12" {
  switches_part(11, 320)
}

///|
test "switches still: screen 13" {
  switches_part(12, 320)
}

///|
test "switches still: screen 14" {
  switches_part(13, 320)
}

///|
test "switches still: screen 15" {
  switches_part(14, 320)
}

///|
test "switches still: screen 16" {
  switches_part(15, 320)
}

///|
test "switches still: screen 17" {
  switches_part(16, 320)
}

///|
test "switches still: screen 18" {
  switches_part(17, 320)
}

///|
test "switches still: screen 19" {
  switches_part(18, 320)
}

///|
test "switches still: screen 20" {
  switches_part(19, 320)
}

///|
test "switches still: screen 21" {
  switches_part(20, 320)
}

///|
test "switches still: screen 22" {
  switches_part(21, 320)
}

///|
test "switches still: screen 23" {
  switches_part(22, 320)
}

///|
test "switches still: screen 24" {
  switches_part(23, 320)
}

///|
test "switches still: screen 25" {
  switches_part(24, 320)
}

///|
test "switches still: screen 26" {
  switches_part(25, 320)
}

///|
test "switches still: screen 27" {
  switches_part(26, 320)
}

///|
test "switches still: screen 28" {
  switches_part(27, 320)
}

///|
test "switches still: screen 29" {
  switches_part(28, 320)
}

///|
test "switches still: screen 30" {
  switches_part(29, 320)
}

///|
test "switches still: screen 31" {
  switches_part(30, 320)
}

///|
test "switches still: screen 32" {
  switches_part(31, 320)
}

///|
test "switches still: screen 33" {
  switches_part(32, 320)
}

///|
test "switches still: screen 34" {
  switches_part(33, 320)
}

///|
test "switches still: screen 35" {
  switches_part(34, 320)
}

///|
test "switches still: screen 36" {
  switches_part(35, 320)
}

///|
test "switches still: screen 37" {
  switches_part(36, 320)
}

///|
test "switches still: screen 38" {
  switches_part(37, 320)
}

///|
test "switches still: screen 39" {
  switches_part(38, 320)
}

///|
test "switches still: screen 40" {
  switches_part(39, 320)
}

///|
test "switches still: screen 41" {
  switches_part(40, 320)
}

///|
test "switches still: screen 42" {
  switches_part(41, 320)
}

///|
test "switches still: screen 43" {
  switches_part(42, 320)
}

///|
test "switches still: screen 44" {
  switches_part(43, 320)
}

///|
test "switches still: screen 45" {
  switches_part(44, 320)
}

///|
test "switches still: screen 46" {
  switches_part(45, 320)
}

///|
test "switches still: screen 47" {
  switches_part(46, 320)
}

///|
test "switches still: screen 48" {
  switches_part(47, 320)
}

///|
test "switches still: screen 49" {
  switches_part(48, 320)
}

///|
test "switches still: screen 50" {
  switches_part(49, 320)
}

///|
test "switches still: screen 51" {
  switches_part(50, 320)
}

///|
test "switches still: screen 52" {
  switches_part(51, 320)
}

///|
test "switches still: screen 53" {
  switches_part(52, 320)
}

///|
test "switches still: screen 54" {
  switches_part(53, 320)
}

///|
test "switches still: screen 55" {
  switches_part(54, 320)
}

///|
test "switches still: screen 56" {
  switches_part(55, 320)
}

///|
test "switches still: screen 57" {
  switches_part(56, 320)
}

///|
test "switches still: screen 58" {
  switches_part(57, 320)
}

///|
test "switches still: screen 59" {
  switches_part(58, 320)
}

///|
test "switches still: screen 60" {
  switches_part(59, 320)
}

///|
test "switches still: screen 61" {
  switches_part(60, 320)
}

///|
test "switches still: screen 62" {
  switches_part(61, 320)
}

///|
test "switches still: screen 63" {
  switches_part(62, 320)
}

///|
test "switches still: screen 64" {
  switches_part(63, 320)
}

///|
test "switches still: screen 65" {
  switches_part(64, 320)
}

///|
test "switches still: screen 66" {
  switches_part(65, 320)
}

///|
test "switches still: screen 67" {
  switches_part(66, 320)
}

///|
test "switches still: screen 68" {
  switches_part(67, 320)
}

///|
test "switches still: screen 69" {
  switches_part(68, 320)
}

///|
test "switches still: screen 70" {
  switches_part(69, 320)
}

///|
test "switches still: screen 71" {
  switches_part(70, 320)
}

///|
test "switches still: screen 72" {
  switches_part(71, 320)
}

///|
test "switches still: screen 73" {
  switches_part(72, 320)
}

///|
test "switches still: screen 74" {
  switches_part(73, 320)
}

///|
test "switches still: screen 75" {
  switches_part(74, 320)
}

///|
test "switches still: screen 76" {
  switches_part(75, 320)
}

///|
test "switches still: screen 77" {
  switches_part(76, 320)
}

///|
test "switches still: screen 78" {
  switches_part(77, 320)
}

///|
test "switches still: screen 79" {
  switches_part(78, 320)
}

///|
test "switches still: screen 80" {
  switches_part(79, 320)
}

///|
test "switches still: screen 81" {
  switches_part(80, 320)
}

///|
test "switches still: screen 82" {
  switches_part(81, 320)
}

///|
test "switches still: screen 83" {
  switches_part(82, 320)
}

///|
test "switches still: screen 84" {
  switches_part(83, 320)
}

///|
test "switches still: screen 85" {
  switches_part(84, 320)
}

///|
test "switches still: screen 86" {
  switches_part(85, 320)
}

///|
test "switches still: screen 87" {
  switches_part(86, 320)
}

///|
test "switches still: screen 88" {
  switches_part(87, 320)
}

///|
test "switches still: screen 89" {
  switches_part(88, 320)
}

///|
test "switches still: screen 90" {
  switches_part(89, 320)
}

///|
test "switches still: screen 91" {
  switches_part(90, 320)
}

///|
test "switches still: screen 92" {
  switches_part(91, 320)
}

///|
test "switches still: screen 93" {
  switches_part(92, 320)
}

///|
test "switches still: screen 94" {
  switches_part(93, 320)
}

///|
test "switches still: screen 95" {
  switches_part(94, 320)
}

///|
test "switches still: screen 96" {
  switches_part(95, 320)
}

///|
test "switches still: screen 97" {
  switches_part(96, 320)
}

///|
test "switches still: screen 98" {
  switches_part(97, 320)
}

///|
test "switches still: screen 99" {
  switches_part(98, 320)
}

///|
test "switches still: screen 100" {
  switches_part(99, 320)
}

///|
test "switches still: screen 101" {
  switches_part(100, 320)
}

///|
test "switches still: screen 102" {
  switches_part(101, 320)
}

///|
test "switches still: screen 103" {
  switches_part(102, 320)
}

///|
test "switches still: screen 104" {
  switches_part(103, 320)
}

///|
test "switches still: screen 105" {
  switches_part(104, 320)
}

///|
test "switches still: screen 106" {
  switches_part(105, 320)
}

///|
test "switches still: screen 107" {
  switches_part(106, 320)
}

///|
test "switches still: screen 108" {
  switches_part(107, 320)
}

///|
test "switches still: screen 109" {
  switches_part(108, 320)
}

///|
test "switches still: screen 110" {
  switches_part(109, 320)
}

///|
test "switches still: screen 111" {
  switches_part(110, 320)
}

///|
test "switches still: screen 112" {
  switches_part(111, 320)
}

///|
test "switches still: screen 113" {
  switches_part(112, 320)
}

///|
test "switches still: screen 114" {
  switches_part(113, 320)
}

///|
test "switches still: screen 115" {
  switches_part(114, 320)
}

///|
test "switches still: screen 116" {
  switches_part(115, 320)
}

///|
test "switches still: screen 117" {
  switches_part(116, 320)
}

///|
test "switches still: screen 118" {
  switches_part(117, 320)
}

///|
test "switches still: screen 119" {
  switches_part(118, 320)
}

///|
test "switches still: screen 120" {
  switches_part(119, 320)
}

///|
test "switches still: screen 121" {
  switches_part(120, 320)
}

///|
test "switches still: screen 122" {
  switches_part(121, 320)
}

///|
test "switches still: screen 123" {
  switches_part(122, 320)
}

///|
test "switches still: screen 124" {
  switches_part(123, 320)
}

///|
test "switches still: screen 125" {
  switches_part(124, 320)
}

///|
test "switches still: screen 126" {
  switches_part(125, 320)
}

///|
test "switches still: screen 127" {
  switches_part(126, 320)
}

///|
test "switches still: screen 128" {
  switches_part(127, 320)
}

///|
test "switches still: screen 129" {
  switches_part(128, 320)
}

///|
test "switches still: screen 130" {
  switches_part(129, 320)
}

///|
test "switches still: screen 131" {
  switches_part(130, 320)
}

///|
test "switches still: screen 132" {
  switches_part(131, 320)
}

///|
test "switches still: screen 133" {
  switches_part(132, 320)
}

///|
test "switches still: screen 134" {
  switches_part(133, 320)
}

///|
test "switches still: screen 135" {
  switches_part(134, 320)
}

///|
test "switches still: screen 136" {
  switches_part(135, 320)
}

///|
test "switches still: screen 137" {
  switches_part(136, 320)
}

///|
test "switches still: screen 138" {
  switches_part(137, 320)
}

///|
test "switches still: screen 139" {
  switches_part(138, 320)
}

///|
test "switches still: screen 140" {
  switches_part(139, 320)
}

///|
test "switches still: screen 141" {
  switches_part(140, 320)
}

///|
test "switches still: screen 142" {
  switches_part(141, 320)
}

///|
test "switches still: screen 143" {
  switches_part(142, 320)
}

///|
test "switches still: screen 144" {
  switches_part(143, 320)
}

///|
test "switches still: screen 145" {
  switches_part(144, 320)
}

///|
test "switches still: screen 146" {
  switches_part(145, 320)
}

///|
test "switches still: screen 147" {
  switches_part(146, 320)
}

///|
test "switches still: screen 148" {
  switches_part(147, 320)
}

///|
test "switches still: screen 149" {
  switches_part(148, 320)
}

///|
test "switches still: screen 150" {
  switches_part(149, 320)
}

///|
test "switches still: screen 151" {
  switches_part(150, 320)
}

///|
test "switches still: screen 152" {
  switches_part(151, 320)
}

///|
test "switches still: screen 153" {
  switches_part(152, 320)
}

///|
test "switches still: screen 154" {
  switches_part(153, 320)
}

///|
test "switches still: screen 155" {
  switches_part(154, 320)
}

///|
test "switches still: screen 156" {
  switches_part(155, 320)
}

///|
test "switches still: screen 157" {
  switches_part(156, 320)
}

///|
test "switches still: screen 158" {
  switches_part(157, 320)
}

///|
test "switches still: screen 159" {
  switches_part(158, 320)
}

///|
test "switches still: screen 160" {
  switches_part(159, 320)
}

///|
test "switches still: screen 161" {
  switches_part(160, 320)
}

///|
test "switches still: screen 162" {
  switches_part(161, 320)
}

///|
test "switches still: screen 163" {
  switches_part(162, 320)
}

///|
test "switches still: screen 164" {
  switches_part(163, 320)
}

///|
test "switches still: screen 165" {
  switches_part(164, 320)
}

///|
test "switches still: screen 166" {
  switches_part(165, 320)
}

///|
test "switches still: screen 167" {
  switches_part(166, 320)
}

///|
test "switches still: screen 168" {
  switches_part(167, 320)
}

///|
test "switches still: screen 169" {
  switches_part(168, 320)
}

///|
test "switches still: screen 170" {
  switches_part(169, 320)
}

///|
test "switches still: screen 171" {
  switches_part(170, 320)
}

///|
test "switches still: screen 172" {
  switches_part(171, 320)
}

///|
test "switches still: screen 173" {
  switches_part(172, 320)
}

///|
test "switches still: screen 174" {
  switches_part(173, 320)
}

///|
test "switches still: screen 175" {
  switches_part(174, 320)
}

///|
test "switches still: screen 176" {
  switches_part(175, 320)
}

///|
test "switches still: screen 177" {
  switches_part(176, 320)
}

///|
test "switches still: screen 178" {
  switches_part(177, 320)
}

///|
test "switches still: screen 179" {
  switches_part(178, 320)
}

///|
test "switches still: screen 180" {
  switches_part(179, 320)
}

///|
test "switches still: screen 181" {
  switches_part(180, 320)
}

///|
test "switches still: screen 182" {
  switches_part(181, 320)
}

///|
test "switches still: screen 183" {
  switches_part(182, 320)
}

///|
test "switches still: screen 184" {
  switches_part(183, 320)
}

///|
test "switches still: screen 185" {
  switches_part(184, 320)
}

///|
test "switches still: screen 186" {
  switches_part(185, 320)
}

///|
test "switches still: screen 187" {
  switches_part(186, 320)
}

///|
test "switches still: screen 188" {
  switches_part(187, 320)
}

///|
test "switches still: screen 189" {
  switches_part(188, 320)
}

///|
test "switches still: screen 190" {
  switches_part(189, 320)
}

///|
test "switches still: screen 191" {
  switches_part(190, 320)
}

///|
test "switches still: screen 192" {
  switches_part(191, 320)
}

///|
test "switches still: screen 193" {
  switches_part(192, 320)
}

///|
test "switches still: screen 194" {
  switches_part(193, 320)
}

///|
test "switches still: screen 195" {
  switches_part(194, 320)
}

///|
test "switches still: screen 196" {
  switches_part(195, 320)
}

///|
test "switches still: screen 197" {
  switches_part(196, 320)
}

///|
test "switches still: screen 198" {
  switches_part(197, 320)
}

///|
test "switches still: screen 199" {
  switches_part(198, 320)
}

///|
test "switches still: screen 200" {
  switches_part(199, 320)
}

///|
test "switches still: screen 201" {
  switches_part(200, 320)
}

///|
test "switches still: screen 202" {
  switches_part(201, 320)
}

///|
test "switches still: screen 203" {
  switches_part(202, 320)
}

///|
test "switches still: screen 204" {
  switches_part(203, 320)
}

///|
test "switches still: screen 205" {
  switches_part(204, 320)
}

///|
test "switches still: screen 206" {
  switches_part(205, 320)
}

///|
test "switches still: screen 207" {
  switches_part(206, 320)
}

///|
test "switches still: screen 208" {
  switches_part(207, 320)
}

///|
test "switches still: screen 209" {
  switches_part(208, 320)
}

///|
test "switches still: screen 210" {
  switches_part(209, 320)
}

///|
test "switches still: screen 211" {
  switches_part(210, 320)
}

///|
test "switches still: screen 212" {
  switches_part(211, 320)
}

///|
test "switches still: screen 213" {
  switches_part(212, 320)
}

///|
test "switches still: screen 214" {
  switches_part(213, 320)
}

///|
test "switches still: screen 215" {
  switches_part(214, 320)
}

///|
test "switches still: screen 216" {
  switches_part(215, 320)
}

///|
test "switches still: screen 217" {
  switches_part(216, 320)
}

///|
test "switches still: screen 218" {
  switches_part(217, 320)
}

///|
test "switches still: screen 219" {
  switches_part(218, 320)
}

///|
test "switches still: screen 220" {
  switches_part(219, 320)
}

///|
test "switches still: screen 221" {
  switches_part(220, 320)
}

///|
test "switches still: screen 222" {
  switches_part(221, 320)
}

///|
test "switches still: screen 223" {
  switches_part(222, 320)
}

///|
test "switches still: screen 224" {
  switches_part(223, 320)
}

///|
test "switches still: screen 225" {
  switches_part(224, 320)
}

///|
test "switches still: screen 226" {
  switches_part(225, 320)
}

///|
test "switches still: screen 227" {
  switches_part(226, 320)
}

///|
test "switches still: screen 228" {
  switches_part(227, 320)
}

///|
test "switches still: screen 229" {
  switches_part(228, 320)
}

///|
test "switches still: screen 230" {
  switches_part(229, 320)
}

///|
test "switches still: screen 231" {
  switches_part(230, 320)
}

///|
test "switches still: screen 232" {
  switches_part(231, 320)
}

///|
test "switches still: screen 233" {
  switches_part(232, 320)
}

///|
test "switches still: screen 234" {
  switches_part(233, 320)
}

///|
test "switches still: screen 235" {
  switches_part(234, 320)
}

///|
test "switches still: screen 236" {
  switches_part(235, 320)
}

///|
test "switches still: screen 237" {
  switches_part(236, 320)
}

///|
test "switches still: screen 238" {
  switches_part(237, 320)
}

///|
test "switches still: screen 239" {
  switches_part(238, 320)
}

///|
test "switches still: screen 240" {
  switches_part(239, 320)
}

///|
test "switches still: screen 241" {
  switches_part(240, 320)
}

///|
test "switches still: screen 242" {
  switches_part(241, 320)
}

///|
test "switches still: screen 243" {
  switches_part(242, 320)
}

///|
test "switches still: screen 244" {
  switches_part(243, 320)
}

///|
test "switches still: screen 245" {
  switches_part(244, 320)
}

///|
test "switches still: screen 246" {
  switches_part(245, 320)
}

///|
test "switches still: screen 247" {
  switches_part(246, 320)
}

///|
test "switches still: screen 248" {
  switches_part(247, 320)
}

///|
test "switches still: screen 249" {
  switches_part(248, 320)
}

///|
test "switches still: screen 250" {
  switches_part(249, 320)
}

///|
test "switches still: screen 251" {
  switches_part(250, 320)
}

///|
test "switches still: screen 252" {
  switches_part(251, 320)
}

///|
test "switches still: screen 253" {
  switches_part(252, 320)
}

///|
test "switches still: screen 254" {
  switches_part(253, 320)
}

///|
test "switches still: screen 255" {
  switches_part(254, 320)
}

///|
test "switches still: screen 256" {
  switches_part(255, 320)
}

///|
test "switches still: screen 257" {
  switches_part(256, 320)
}

///|
test "switches still: screen 258" {
  switches_part(257, 320)
}

///|
test "switches still: screen 259" {
  switches_part(258, 320)
}

///|
test "switches still: screen 260" {
  switches_part(259, 320)
}

///|
test "switches still: screen 261" {
  switches_part(260, 320)
}

///|
test "switches still: screen 262" {
  switches_part(261, 320)
}

///|
test "switches still: screen 263" {
  switches_part(262, 320)
}

///|
test "switches still: screen 264" {
  switches_part(263, 320)
}

///|
test "switches still: screen 265" {
  switches_part(264, 320)
}

///|
test "switches still: screen 266" {
  switches_part(265, 320)
}

///|
test "switches still: screen 267" {
  switches_part(266, 320)
}

///|
test "switches still: screen 268" {
  switches_part(267, 320)
}

///|
test "switches still: screen 269" {
  switches_part(268, 320)
}

///|
test "switches still: screen 270" {
  switches_part(269, 320)
}

///|
test "switches still: screen 271" {
  switches_part(270, 320)
}

///|
test "switches still: screen 272" {
  switches_part(271, 320)
}

///|
test "switches still: screen 273" {
  switches_part(272, 320)
}

///|
test "switches still: screen 274" {
  switches_part(273, 320)
}

///|
test "switches still: screen 275" {
  switches_part(274, 320)
}

///|
test "switches still: screen 276" {
  switches_part(275, 320)
}

///|
test "switches still: screen 277" {
  switches_part(276, 320)
}

///|
test "switches still: screen 278" {
  switches_part(277, 320)
}

///|
test "switches still: screen 279" {
  switches_part(278, 320)
}

///|
test "switches still: screen 280" {
  switches_part(279, 320)
}

///|
test "switches still: screen 281" {
  switches_part(280, 320)
}

///|
test "switches still: screen 282" {
  switches_part(281, 320)
}

///|
test "switches still: screen 283" {
  switches_part(282, 320)
}

///|
test "switches still: screen 284" {
  switches_part(283, 320)
}

///|
test "switches still: screen 285" {
  switches_part(284, 320)
}

///|
test "switches still: screen 286" {
  switches_part(285, 320)
}

///|
test "switches still: screen 287" {
  switches_part(286, 320)
}

///|
test "switches still: screen 288" {
  switches_part(287, 320)
}

///|
test "switches still: screen 289" {
  switches_part(288, 320)
}

///|
test "switches still: screen 290" {
  switches_part(289, 320)
}

///|
test "switches still: screen 291" {
  switches_part(290, 320)
}

///|
test "switches still: screen 292" {
  switches_part(291, 320)
}

///|
test "switches still: screen 293" {
  switches_part(292, 320)
}

///|
test "switches still: screen 294" {
  switches_part(293, 320)
}

///|
test "switches still: screen 295" {
  switches_part(294, 320)
}

///|
test "switches still: screen 296" {
  switches_part(295, 320)
}

///|
test "switches still: screen 297" {
  switches_part(296, 320)
}

///|
test "switches still: screen 298" {
  switches_part(297, 320)
}

///|
test "switches still: screen 299" {
  switches_part(298, 320)
}

///|
test "switches still: screen 300" {
  switches_part(299, 320)
}

///|
test "switches still: screen 301" {
  switches_part(300, 320)
}

///|
test "switches still: screen 302" {
  switches_part(301, 320)
}

///|
test "switches still: screen 303" {
  switches_part(302, 320)
}

///|
test "switches still: screen 304" {
  switches_part(303, 320)
}

///|
test "switches still: screen 305" {
  switches_part(304, 320)
}

///|
test "switches still: screen 306" {
  switches_part(305, 320)
}

///|
test "switches still: screen 307" {
  switches_part(306, 320)
}

///|
test "switches still: screen 308" {
  switches_part(307, 320)
}

///|
test "switches still: screen 309" {
  switches_part(308, 320)
}

///|
test "switches still: screen 310" {
  switches_part(309, 320)
}

///|
test "switches still: screen 311" {
  switches_part(310, 320)
}

///|
test "switches still: screen 312" {
  switches_part(311, 320)
}

///|
test "switches still: screen 313" {
  switches_part(312, 320)
}

///|
test "switches still: screen 314" {
  switches_part(313, 320)
}

///|
test "switches still: screen 315" {
  switches_part(314, 320)
}

///|
test "switches still: screen 316" {
  switches_part(315, 320)
}

///|
test "switches still: screen 317" {
  switches_part(316, 320)
}

///|
test "switches still: screen 318" {
  switches_part(317, 320)
}

///|
test "switches still: screen 319" {
  switches_part(318, 320)
}

///|
test "switches still: screen 320" {
  switches_part(319, 320)
}


///|
/// What a press, a screen's opening or a screen's end left the signals' graph in the middle of (leaked_state's own
/// checks): said and stopped at once where it was, so the sweep says which press it was.
fn switch_leaks(at : String) -> Unit {
  let left = []
  if @signals.batch_depth() > 0 {
    left.push("a change begun and never ended (batch)")
  }
  if @signals.active_sub() is Some(_) {
    left.push("a reader left reading")
  }
  if @view.answer_marks_left() {
    left.push("an answer's marks left set")
  }
  if left.length() > 0 {
    println("SWITCHES_LEAK \{at}: \{left.join(", ")}")
    @halt.saying("switches still: \{at} left \{left.join(", ")}")
  }
}
