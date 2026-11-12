// The workspaces' sheet closed as the switch is done, not at the press (sfbase's switch_workspace_to, `closes`): on
// the workspace of real size over a core answering late as a phone's does, every frame from the press on. Before the
// switch the sheet stands where it was open and the screen is the first workspace's; in the frame the switch is done
// it is where it was open still, its closing set off at that moment; from there to its end no frame makes or lays out
// a node (only what the core says is taken). The owner on a phone (0.1.8610): 「现在切 workspace 时收起抽屉不流畅，会卡帧」:
// the sheet closed from the press and the new Home was made in a frame of its fastest part.

///|
/// How long the app is let open over the late core before the sheet is opened: what it opens on answered (the core
/// answers each topic 10 to 40 ms late, the list at most switch_wait_ms and more).
let sd_opening_ms : Double = 2000.0

///|
/// How long the sheet takes to come up, at most, once the switcher is pressed.
let sd_sheet_up_ms : Double = @ui.move_most_ms * 2.0

///|
/// The press on 个人 before another press in the same sheet or on its scrim (a finger's next tap, some 33 ms on).
let sd_next_tap_ms : Double = @ui.frame_period_default * 2.0

///|
/// How late the core answers what the switch does not wait for: 10 to 40 ms, by its name (each topic at a moment of its
/// own).
fn sd_late_other(name : String) -> Double {
  let mut h = 0
  for ch in name {
    h = (h * 31 + ch.to_int()) & 0x7fffffff
  }
  10.0 + (h % 31).to_double()
}

///|
/// The workspace of real size (two workspaces, both holding it; a third, 第三个, where `three`) answered through the
/// app's own client of its core: the chats' list `list_ms` after it is asked, what Home opens on besides at most 15 ms,
/// the rest 10 to 40 ms by name. `again`: each topic late (60 ms) only the first time it is read, at once after it.
fn sd_source(list_ms : Double, three? : Bool = false, again? : Bool = false) -> Source {
  let base = @sfrealsize.RealSizeChanging::new().source(fixture("home"))
  let base = if three {
    {
      ..base,
      topic_read: fn(name, params) {
        let t = (base.topic_read)(name, params)
        guard name == "workspaces" && t.value is Some(Array([Object(o)])) else { return t }
        guard o.get("workspaces") is Some(Array(list)) else { return t }
        let m = o.copy()
        m["workspaces"] = Json::array([..list, { "id": "ws3", "name": "第三个", "stations": 1, "members": 1 }])
        { value: Some(Json::array([Json::object(m)])), error: t.error, version: t.version }
      },
    }
  } else {
    base
  }
  let late = fn(name : String, _ : Map[String, Json]) -> Double {
    match name {
      "chats" => list_ms
      "changelog" | "longJobs" => @cmp.minimum(list_ms, 15.0)
      _ => sd_late_other(name)
    }
  }
  if again {
    { ..round_trip_by(base, fn() { 60.0 }), reads_ahead: fn() { true } }
  } else {
    { ..round_trip_again(base, 0.0, late~), reads_ahead: fn() { true } }
  }
}

///|
/// A run begun, the app over `src` in a window `w` by `h` on `platform`, at rest on ws1.
fn sd_app(src : Source, w : Double, h : Double, platform : Int) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.draw()
  t.run_for(sd_opening_ms)
  t
}

///|
/// The workspace in view.
fn sd_ws(src : Source) -> String {
  @signals.untracked(fn() { workspace_in_view(src).0.map(fn(w) { w.id }).unwrap_or("") })
}

///|
/// The workspaces' sheet opened as a finger does on 小屏 (its switcher pressed), up.
fn sd_open_sheet(t : @ui.Tester) -> Unit raise {
  guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Button && s.label == "星火工作室" })
    is Some(sw) else {
    fail("no switcher")
  }
  let (x, y, w, h) = sw.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(sd_sheet_up_ms)
}

///|
/// Where `words` are drawn in what is presented (the sheet, the popover): their top left.
fn sd_in_sheet(t : @ui.Tester, words : String) -> (Double, Double) raise {
  guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog }) is Some(d) else {
    fail("nothing presented")
  }
  let (sx, sy, sw, sh) = d.rect
  guard t.words().iter().find_first(fn(w) { w.0 == words && w.1 >= sx && w.1 <= sx + sw && w.2 >= sy && w.2 <= sy + sh })
    is Some(w) else {
    fail("no \{words} in what is presented")
  }
  (w.1, w.2)
}

///|
/// One frame drawn: its moment after the press, where the words the sheet is followed by are drawn and how opaque
/// (None: not drawn), the workspace in view, and the window's tree's nodes made and laid out in it.
#derive(Debug, Eq)
struct SdFrame {
  at : Double
  place : (Double, Double)?
  ws : String
  made : Int
  laid : Int
}

///|
/// Every frame from the press `press` (done now) to `upto` after it, each as it is drawn (`follow`: the words the
/// presented is followed by), the press's own first; then the display's frames on.
fn sd_frames(t : @ui.Tester, src : Source, follow : String, upto : Double, press : () -> Unit, between? : (Double, () -> Unit)) -> Array[SdFrame] {
  let start = t.time()
  let out : Array[SdFrame] = []
  t.tree_frames_from_now()
  t.each_frame(
    Some(fn() {
      let f = t.tree_frames()
      let (made, laid) = match f.last() {
        Some(x) => (x.made, x.laid)
        None => (0, 0)
      }
      let place = t.words().iter().find_first(fn(w) { w.0 == follow }).map(fn(w) { (w.2, w.5) })
      out.push({ at: t.time() - start, place, ws: sd_ws(src), made, laid })
    }),
  )
  press()
  let mut done_between = false
  while t.time() - start < upto - 1.0e-6 {
    match between {
      Some((at, f)) if !done_between && t.time() - start >= at - 1.0e-6 => {
        done_between = true
        f()
      }
      _ => ()
    }
    t.run_for(@ui.frame_period_default)
  }
  t.each_frame(None)
  out
}

///|
/// What is wrong with `frames` as a switch to `to` from a sheet open at `open`: before the switch the sheet as open and
/// ws1 in view; in the switch's frame the sheet as open still; it goes after; and, where `still` (all it opens on
/// answered by the switch), no frame from the next to the sheet's end makes or lays out a node.
fn sd_faults(name : String, frames : Array[SdFrame], open : (Double, Double), to : String, still : Bool) -> Array[String] {
  let faults : Array[String] = []
  guard frames.search_by(fn(f) { f.ws == to }) is Some(i) else { return ["\{name}: not switched \{Repr(frames)}"] }
  let at_open = fn(f : SdFrame) {
    match f.place {
      Some((y, a)) => (y - open.0).abs() < 0.01 && (a - open.1).abs() < 0.01
      None => false
    }
  }
  let before = frames[:i].to_owned().filter(fn(f) { !at_open(f) || f.ws != "ws1" })
  if before.length() > 0 {
    faults.push("\{name}: before the switch (frame \{i} at \{frames[i].at}) \{Repr(before)}")
  }
  if !at_open(frames[i]) {
    faults.push("\{name}: the switch's frame \{Repr(frames[i])}, the sheet not where it was open")
  }
  if frames.last().unwrap().place is Some(_) {
    faults.push("\{name}: the sheet still there at the end \{Repr(frames.last())}")
  }
  if still {
    let busy = frames[i + 1:].to_owned().filter(fn(f) { f.place is Some(_) && (f.made > 0 || f.laid > 0) })
    if busy.length() > 0 {
      faults.push("\{name}: the closing's frames made or laid out \{Repr(busy)}")
    }
  }
  faults
}

///|
test "a workspace picked in the sheet on 小屏 at real size, the list answered 15, 25, 40, 100 ms late and past switch_wait_ms: the sheet open till the switch, set off closing in its frame, no node made or laid out as it goes" {
  let faults : Array[String] = []
  for list_ms in [15.0, 25.0, 40.0, 100.0, 600.0] {
    new_run()
    let src = sd_source(list_ms)
    let t = sd_app(src, 390.0, 844.0, 2)
    sd_open_sheet(t)
    let title = @sf.t("android-misc.workspace.sheet.title")
    let open = match t.words().iter().find_first(fn(w) { w.0 == title }) {
      Some(w) => (w.2, w.5)
      None => fail("no title")
    }
    let (x, y) = sd_in_sheet(t, "个人")
    let upto = @cmp.maximum(list_ms, @sfbase.switch_wait_ms) + @ui.move_most_ms * 2.0
    let frames = sd_frames(t, src, title, upto, fn() { t.tap(x + 4.0, y + 4.0) })
    // (past switch_wait_ms the list comes as the sheet goes: its rows made then, as when nothing waited)
    for f in sd_faults("list \{list_ms}", frames, open, "ws2", list_ms <= @sfbase.switch_wait_ms) {
      faults.push(f)
    }
  }
  assert_eq(faults, [])
}

///|
test "a workspace picked in the sheet, all it opens on answered already: switched and the sheet set off closing in the press's frame" {
  new_run()
  let src = sd_source(0.0, again=true)
  let t = sd_app(src, 390.0, 844.0, 2)
  let tree = @ui.view_tree().unwrap()
  let away = @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0
  tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
  t.run_for(away)
  tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws1") })
  t.run_for(away)
  sd_open_sheet(t)
  let title = @sf.t("android-misc.workspace.sheet.title")
  let open = match t.words().iter().find_first(fn(w) { w.0 == title }) {
    Some(w) => (w.2, w.5)
    None => fail("no title")
  }
  let (x, y) = sd_in_sheet(t, "个人")
  let frames = sd_frames(t, src, title, @ui.move_most_ms * 2.0, fn() { t.tap(x + 4.0, y + 4.0) })
  // (the press's own frame: switched, the sheet where it was open, going from it: the first frame at a later moment
  // not)
  assert_eq((frames[0].ws, frames[0].place == Some(open)), ("ws2", true))
  guard frames.search_by(fn(f) { f.at > frames[0].at }) is Some(next) else { fail("no frame after the press's") }
  assert_true(frames[next].place != Some(open), msg=Repr(frames[:next + 1]).to_string())
  assert_eq(sd_faults("answered", frames, open, "ws2", true), [])
}

///|
test "the sheet closed by hand while the switch waits: the switch done still, the sheet not opened or closed again" {
  new_run()
  let src = sd_source(100.0)
  let t = sd_app(src, 390.0, 844.0, 2)
  sd_open_sheet(t)
  let title = @sf.t("android-misc.workspace.sheet.title")
  let (x, y) = sd_in_sheet(t, "个人")
  let frames = sd_frames(t, src, title, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0, fn() { t.tap(x + 4.0, y + 4.0) }, between=(
    sd_next_tap_ms,
    fn() { t.tap(195.0, 60.0) },
  ))
  guard frames.search_by(fn(f) { f.ws == "ws2" }) is Some(_) else { fail("not switched") }
  // (from the scrim's press on the sheet only goes down, gone at the end)
  let mut was = 0.0
  let back : Array[SdFrame] = []
  for f in frames {
    match f.place {
      Some((y, _)) => {
        if y < was - 0.01 {
          back.push(f)
        }
        was = y
      }
      None => was = @double.infinity
    }
  }
  assert_eq(back, [])
  assert_true(frames.last().unwrap().place is None)
}

///|
test "another workspace picked in the sheet while the switch to the first waits: one switch, to it, the sheet open till then" {
  new_run()
  let src = sd_source(150.0, three=true)
  let t = sd_app(src, 390.0, 844.0, 2)
  sd_open_sheet(t)
  let title = @sf.t("android-misc.workspace.sheet.title")
  let open = match t.words().iter().find_first(fn(w) { w.0 == title }) {
    Some(w) => (w.2, w.5)
    None => fail("no title")
  }
  let (x, y) = sd_in_sheet(t, "个人")
  let (x3, y3) = sd_in_sheet(t, "第三个")
  let frames = sd_frames(t, src, title, sd_next_tap_ms + @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0, fn() {
    t.tap(x + 4.0, y + 4.0)
  }, between=(sd_next_tap_ms, fn() { t.tap(x3 + 4.0, y3 + 4.0) }))
  assert_eq(frames.filter(fn(f) { f.ws == "ws2" }), [])
  // (the second row's ripple goes on over the closing, drawn bigger as it goes, laid out once: sf's ripple_disc)
  assert_eq(sd_faults("third", frames, open, "ws3", true), [])
}

///|
test "a workspace picked in the popover on 大屏 at real size over the late core: the popover as it was till the switch, set off closing in its frame" {
  new_run()
  let src = sd_source(25.0)
  let t = sd_app(src, 1280.0, 800.0, 0)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.open_workspaces(src, At(32.0, 16.0, 150.0, 38.0), compact=true) })
  t.run_for(sd_sheet_up_ms)
  let (x, y) = sd_in_sheet(t, "个人")
  // (followed by its foot's 新建 workspace, words of its own: the workspace's name is the wide frame's too once in view)
  let foot = @sf.t("android-misc.workspace.new")
  let open = match t.words().iter().find_first(fn(w) { w.0 == foot }) {
    Some(w) => (w.2, w.5)
    None => fail("no \{foot}")
  }
  let frames = sd_frames(t, src, foot, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0, fn() { t.tap(x + 4.0, y + 4.0) })
  // (its rows' words drawn while it goes, faded: as open till the switch and in its frame; nodes made after it are the
  // wide frame's own, not held here)
  let faults = sd_faults("大屏", frames, open, "ws2", false).filter(fn(f) { !f.contains("still there at the end") })
  assert_eq(faults, [])
}

///|
/// What the presented sheet (or popover) shows now, as a screen reader is told it (read out or, closing, not): each of
/// what it holds (its role and name), where it is down the sheet, top to bottom; None where nothing is presented.
fn sd_sheet_seen(t : @ui.Tester) -> Array[(String, String, Double)]? {
  let all = t.semantics()
  guard all.search_by(fn(s) { s.role == @ui.Role::Dialog }) is Some(di) else { return None }
  let d = all[di]
  // (its own: those whose holders lead to it, each's `parent` its holder's place among them all)
  let within = fn(i : Int) {
    let mut p = all[i].parent
    while p >= 0 {
      if p == di {
        return true
      }
      p = all[p].parent
    }
    false
  }
  let held = []
  for i, s in all {
    if i != di && within(i) {
      // (where it is down the sheet, a share of how tall the sheet is drawn, to a thousandth: a popover closing is drawn
      // smaller as it goes, what it holds with it)
      held.push((Repr(s.role).to_string(), s.label, ((s.rect.1 - d.rect.1) / d.rect.3 * 1000.0).round() / 1000.0))
    }
  }
  held.sort_by(fn(a, b) { if a.2 == b.2 { a.1.compare(b.1) } else { a.2.compare(b.2) } })
  Some(held)
}

///|
/// Every frame from the press `press` (done now) till what is presented is gone: what it shows (sd_sheet_seen), each
/// with the workspace in view then.
fn sd_sheet_frames(
  t : @ui.Tester,
  src : Source,
  upto : Double,
  press : () -> Unit,
) -> Array[(String, Array[(String, String, Double)]?)] {
  let start = t.time()
  let out = []
  t.each_frame(Some(fn() { out.push((sd_ws(src), sd_sheet_seen(t))) }))
  press()
  while t.time() - start < upto - 1.0e-6 {
    t.run_for(@ui.frame_period_default)
  }
  t.each_frame(None)
  out
}

///|
/// What is wrong with `frames` (a switch to `to` pressed in what is presented, which showed `at_press` then): any frame
/// it shows anything but that till it is gone; it never gone, or the switch never done while it showed.
fn sd_sheet_faults(
  name : String,
  frames : Array[(String, Array[(String, String, Double)]?)],
  at_press : Array[(String, String, Double)],
  to : String,
) -> Array[String] {
  let faults : Array[String] = []
  let mut switched_shown = false
  for i, f in frames {
    match f.1 {
      Some(seen) => {
        if f.0 == to {
          switched_shown = true
        }
        if seen != at_press {
          faults.push("\{name}: frame \{i} (\{f.0}) shows \{Repr(seen)}, at the press \{Repr(at_press)}")
        }
      }
      None => ()
    }
  }
  if !switched_shown {
    faults.push("\{name}: no frame of the switch done with it still shown")
  }
  match frames.last() {
    Some((_, Some(_))) => faults.push("\{name}: still shown at the end")
    _ => ()
  }
  faults
}

///|
test "a workspace picked in the sheet on 小屏 at real size: from the press till the sheet is gone it shows what it showed at the press, its rows, their order and the one in use; opened again, the new one is in use" {
  let faults : Array[String] = []
  for list_ms in [0.0, 25.0, 100.0, 600.0] {
    new_run()
    let src = if list_ms == 0.0 { sd_source(0.0, again=true) } else { sd_source(list_ms) }
    let t = sd_app(src, 390.0, 844.0, 2)
    if list_ms == 0.0 {
      // (everything it opens on read once already: switched in the press's own frame)
      let tree = @ui.view_tree().unwrap()
      let away = @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0
      tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
      t.run_for(away)
      tree.event(t.time(), fn() { @sfpages.switch_workspace(src, "ws1") })
      t.run_for(away)
    }
    sd_open_sheet(t)
    guard sd_sheet_seen(t) is Some(at_press) && at_press.iter().any(fn(h) { h.1 == "个人" }) else {
      fail("no sheet naming 个人: \{Repr(sd_sheet_seen(t))}")
    }
    let (x, y) = sd_in_sheet(t, "个人")
    let upto = @cmp.maximum(list_ms, @sfbase.switch_wait_ms) + @ui.move_most_ms * 2.0
    let frames = sd_sheet_frames(t, src, upto, fn() { t.tap(x + 4.0, y + 4.0) })
    for f in sd_sheet_faults("list \{list_ms}", frames, at_press, "ws2") {
      faults.push(f)
    }
    // (opened again: the one in use the new one, first, on its card, at once)
    guard t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Button && s.label == "个人" }) is Some(sw) else {
      faults.push("list \{list_ms}: no switcher saying 个人")
      continue
    }
    let (sx, sy, sw_, sh) = sw.rect
    t.tap(sx + sw_ / 2.0, sy + sh / 2.0)
    t.run_for(sd_sheet_up_ms)
    match sd_sheet_seen(t) {
      Some(held) =>
        match held.iter().find_first(fn(h) { h.1 == "个人" || h.1 == "星火工作室" }) {
          Some(h) if h.1 == "个人" => ()
          _ => faults.push("list \{list_ms}: opened again, it shows \{Repr(held)}")
        }
      None => faults.push("list \{list_ms}: not opened again")
    }
  }
  assert_eq(faults, [])
}

///|
test "a workspace picked in the popover on 大屏 at real size: from the press till it is gone it shows what it showed at the press" {
  new_run()
  let src = sd_source(25.0)
  let t = sd_app(src, 1280.0, 800.0, 0)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.open_workspaces(src, At(32.0, 16.0, 150.0, 38.0), compact=true) })
  t.run_for(sd_sheet_up_ms)
  guard sd_sheet_seen(t) is Some(at_press) && at_press.iter().any(fn(h) { h.1 == "个人" }) else {
    fail("no popover naming 个人: \{Repr(sd_sheet_seen(t))}")
  }
  let (x, y) = sd_in_sheet(t, "个人")
  let frames = sd_sheet_frames(t, src, @sfbase.switch_wait_ms + @ui.move_most_ms * 2.0, fn() { t.tap(x + 4.0, y + 4.0) })
  // (its rows' words drawn while it goes, faded, as switch_drawer's 大屏 test finds: not held to be gone at the end)
  assert_eq(sd_sheet_faults("大屏", frames, at_press, "ws2").filter(fn(f) { !f.contains("still shown at the end") }), [])
}
