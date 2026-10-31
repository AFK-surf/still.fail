// A bar's tool as a node of the window's tree (tool_node) beside the old one (viewer_tool), each in the same state:
// drawn the same where they are (their instances, in their own terms), read out the same; the node pressed by each
// way in as the host gives it (a click, a finger's tap, Enter and Space with the focus, a screen reader's Activate) at
// its moment, no frame drawn; said unable to be pressed between frames, by none of them; its ring as the keyboard's
// focus comes to it and goes.

///|
/// Enter's and Space's codes as hosts send them (editor.mbt's key_enter; focus.mbt's key_space).
let enter_code : Int = 7

///|
let space_code : Int = 1032

///|
/// The old tool ("… old", an old view's) and the node's ("… new") side by side, each saying what `said` says in the ink
/// `ink` says: how many times each was pressed, in `pressed`. The node's holder taking presses while `held` says; the
/// node there while `there`; a modal layer of the tree's over all of it while `modal`.
fn tools_tester(
  said : @signals.Signal[ToolSaid],
  ink : @signals.Signal[ViewerInk],
  pressed : Map[String, Int],
  held? : @signals.Signal[Bool] = @signals.signal(true),
  there? : @signals.Signal[Bool] = @signals.signal(true),
  modal? : @signals.Signal[Bool] = @signals.signal(false),
  platform? : Int = 0,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform~)
  t.check_looks(false)
  let count = fn(k : String) { pressed[k] = pressed.get(k).unwrap_or(0) + 1 }
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    // (room before them: what goes beside either kept in the window by none of its edges)
    root.box(fn(g) { g.width(Is(Some(60.0))) |> ignore }) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      @ui.old(h, fn(c) {
        let s = said.get()
        if viewer_tool(c, "old", s.icon, s.label + " old", ink.get(), on=s.on, disabled=s.disabled) {
          count("old")
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    // (the layer over all of it the node's tip is drawn in: made last, over the rest)
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    tips_made.val = Some(tips)
    root.box(fn(b) {
      b.width(Is(Some(100.0))).height(Is(Some(100.0))).presses(By(fn() { held.get() })) |> ignore
      b.show(fn() { there.get() }, fn(b) {
      tool_node(
        b,
        fn() {
          let s = said.get()
          { ..s, label: s.label + " new" }
        },
        fn() { ink.get() },
        Is(tool_side / 2.0),
        fn() { count("new") },
        tip=tips,
      )
      |> ignore
      })
    })
    |> ignore
    root.show(fn() { modal.get() }, fn(m) { m.over(Is(true)).modal(Is(true)) |> ignore })
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
    tips_layer.val = layer.val
  })
  t.draw()
  t
}

///|
/// The tips of the last tools_tester made.
let tips_made : Ref[TipLayer?] = Ref(None)

///|
/// The tips' layer of the last tools_tester made.
let tips_layer : Ref[@view.View?] = Ref(None)

///|
/// The number `s` writes, if it is one.
fn number_of(s : String) -> Double? {
  match (try Some(@json.parse(s)) catch { _ => None }) {
    Some(Number(d, ..)) => Some(d)
    _ => None
  }
}

///|
/// Where a band's pieces are in a data instance of the draw list (kind 12, six to one: its numbers' fours 0, 2, 3, 4, 6
/// and 7, ui's shape.mbt seg_slots).
let piece_slots : Array[Int] = [0, 2, 3, 4, 6, 7]

///|
/// What is drawn within `rect` (x, y, w, h) as the draw list says it, each instance in the rect's own terms, its clip
/// left out (the old view's is the window's, a node's its own); a band of a shape (kind 11) with the pieces of its
/// outlines it draws (as shares of the band), read where they are kept (the frame's data instances, kind 12, after all
/// that is drawn), not where in them; a corner as round as it can be one way of saying so: in order.
fn drawn_within(t : @ui.Tester, rect : (Double, Double, Double, Double)) -> Array[String] {
  let (rx, ry, rw, rh) = rect
  let rows : Array[Array[String]] = []
  for line in t.drawlist().split("\n") {
    let f = line.split(" ").map(fn(v) { v.to_string() }).to_array()
    if f.length() >= 21 && f[0] == "i" {
      rows.push(f)
    }
  }
  let data = rows.filter(fn(f) { f[6] == "12" })
  let piece = fn(i : Int) -> String {
    let row = i / 6
    if row >= data.length() {
      return "?"
    }
    let at = 1 + piece_slots[i % 6] * 4
    let d = data[row]
    (0).until(4).map(fn(q) {
      match number_of(d[at + q]) {
        Some(v) => ((v * 1000.0).round() / 1000.0).to_string()
        None => "?"
      }
    }).collect().join(",")
  }
  let out : Array[String] = []
  for f in rows {
    if f[6] == "12" {
      continue
    }
    let (x, y) = match (number_of(f[1]), number_of(f[2])) {
      (Some(x), Some(y)) => (x, y)
      _ => continue
    }
    if x < rx - 0.5 || y < ry - 0.5 || x > rx + rw + 0.5 || y > ry + rh + 0.5 {
      continue
    }
    // (a corner as round as it can be, as said (Full: one far past its half) or as its half: drawn the same)
    let rest = f[3:13].to_array().mapi(fn(k, v) {
      match (k, number_of(f[3]), number_of(f[4]), number_of(v)) {
        (2, Some(w), Some(h), Some(r)) if r >= (if w < h { w } else { h }) / 2.0 => "half"
        _ => v
      }
    }).join(" ")
    let what = match (f[6], number_of(f[13]), number_of(f[14])) {
      ("11", Some(first), Some(n)) =>
        "[" + (0).until(n.to_int()).map(fn(i) { piece(first.to_int() + i) }).collect().join(" ") + "]"
      _ => f[13] + " " + f[14]
    }
    out.push("\{((x - rx) * 100.0).round()} \{((y - ry) * 100.0).round()} \{rest} \{what} \{f[15]} \{f[16]}")
  }
  out
}

///|
/// A night ink, other than the page's (another bar's: the reader's paper at night).
let night_ink : ViewerInk = {
  ground: 0x1C1C1EFFL,
  ink: 0xF2F2F7FFL,
  muted: 0x8E8E93FFL,
  line: 0x3A3A3CFFL,
  hover: 0xFFFFFF1AL,
  chosen: 0xFFFFFF29L,
}

///|
test "a tool as a node beside the old one, in each state and as what it says changes once made (at rest, pointed at, on, on and pointed at, unable; another icon and words; another ink): drawn the same, as big, read out as it is (what can be done to it said, as the old one does not)" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let ink = @signals.signal(page_viewer_ink(), same=fn(a, b) { physical_equal(a, b) })
  let t = tools_tester(said, ink, {})
  let old = t.get(Button, label="复制 old")
  let new = t.get(Button, label="复制 new")
  assert_eq((old.rect.2, old.rect.3), (new.rect.2, new.rect.3), msg="as big")
  let copy = { icon: "copy", label: "复制", on: false, disabled: false }
  let states : Array[(String, ToolSaid, ViewerInk, Bool)] = [
    ("at rest", copy, page_viewer_ink(), false),
    ("pointed at", copy, page_viewer_ink(), true),
    ("on", { ..copy, on: true }, page_viewer_ink(), false),
    ("on, pointed at", { ..copy, on: true }, page_viewer_ink(), true),
    ("unable", { ..copy, disabled: true }, page_viewer_ink(), true),
    ("another icon and words", { icon: "check", label: "已复制", on: false, disabled: false }, page_viewer_ink(), false),
    ("another ink", copy, night_ink, true),
  ]
  for st in states {
    let (name, s, k, over) = st
    said.set(s)
    ink.set(k)
    t.draw()
    let o = t.get(Button, label=s.label + " old")
    let n = t.get(Button, label=s.label + " new")
    // (the pointer over each in turn, or over neither)
    if over {
      t.move(o.rect.0 + 16.0, o.rect.1 + 16.0)
    } else {
      t.leave()
    }
    let old_drawn = drawn_within(t, o.rect)
    if over {
      t.move(n.rect.0 + 16.0, n.rect.1 + 16.0)
    }
    let new_drawn = drawn_within(t, n.rect)
    assert_eq(new_drawn, old_drawn, msg="\{name}: new \{new_drawn} old \{old_drawn}")
    assert_eq((n.role, n.pressed, n.disabled), (o.role, o.pressed, o.disabled), msg="\{name}: read out")
    // (what can be done to it said as it is: the old one says none of it though a screen reader's Activate presses it)
    let can : Array[@ui.Action] = if s.disabled { [] } else { [Activate, Focus] }
    assert_eq(n.actions, can, msg="\{name}: what can be done to it")
  }
}

///|
test "a tool as a node pressed at each way in's moment, no frame drawn: a click, a finger's tap, Enter and Space with the focus, a screen reader's Activate; said unable to be pressed between frames, by none of them, its id read out before asked late" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), pressed)
  let n = t.get(Button, label="复制 new")
  let (cx, cy) = (n.rect.0 + n.rect.2 / 2.0, n.rect.1 + n.rect.3 / 2.0)
  let presses = fn() { pressed.get("new").unwrap_or(0) }
  // (each as the host gives it, at its moment; looked at before any frame is drawn)
  t.touch(0, cx, cy)
  t.touch(2, cx, cy)
  assert_eq(presses(), 1, msg="a click")
  t.touch_raw(0, 1, cx, cy, t.time())
  t.touch_raw(2, 1, cx, cy, t.time())
  assert_eq(presses(), 2, msg="a finger's tap")
  // (the focus to it by Tab: the one stop there is, the old one taking none)
  t.key_told(@ui.key_tab, 0, t.time())
  t.key_told(enter_code, 0, t.time())
  assert_eq(presses(), 3, msg="Enter")
  t.key_told(space_code, 0, t.time())
  assert_eq(presses(), 4, msg="Space")
  t.ctx().ask_action(n.id, Activate)
  assert_eq(presses(), 5, msg="a screen reader's Activate")
  // (unable, said so with no frame drawn: each way in, at once, none presses it)
  said.set({ icon: "copy", label: "复制", on: false, disabled: true })
  t.key_told(enter_code, 0, t.time())
  t.key_told(space_code, 0, t.time())
  t.ctx().ask_action(n.id, Activate)
  t.touch(0, cx, cy)
  t.touch(2, cx, cy)
  t.touch_raw(0, 1, cx, cy, t.time())
  t.touch_raw(2, 1, cx, cy, t.time())
  assert_eq(presses(), 5, msg="unable: pressed by none")
}

///|
test "a tool as a node ringed as the keyboard's focus comes to it, as a kit control is (the theme's focus line, its gap out from its edge, in its corner as far out); gone as the focus goes (a press beside it); the old one taking no focus at all" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {})
  let n = t.get(Button, label="复制 new")
  let th = t.ctx().theme()
  let out = th.focus_gap + th.focus_w
  let around = (n.rect.0 - out, n.rect.1 - out, n.rect.2 + 2.0 * out, n.rect.3 + 2.0 * out)
  let unringed = drawn_within(t, around)
  t.tab()
  assert_eq(t.ctx().focused_id(), n.id, msg="Tab to it: the one stop")
  let ringed = drawn_within(t, around)
  let ring = ringed.filter(fn(l) { !unringed.contains(l) })
  assert_eq(ring.length(), 1, msg="one ring: \{ring}")
  let f = ring[0].split(" ").map(fn(v) { v.to_string() }).to_array()
  assert_eq((f[0], f[1], f[2], f[3]), ("0", "0", (n.rect.2 + 2.0 * out).to_string(), (n.rect.3 + 2.0 * out).to_string()), msg="\{ring[0]}")
  // (a press on nothing that takes one: the focus let go)
  t.tap(300.0, 150.0)
  let after = drawn_within(t, around)
  assert_eq(after, unringed, msg="the focus gone: no ring: \{after.filter(fn(l) { !unringed.contains(l) })}; focus \{t.ctx().focused_id()}, the node \{n.id}, read out \{t.semantics().map(fn(s) { (s.id, s.label, s.actions) })}")
}

///|
test "a tool as a node's tip: shown as the pointer rests on it tip_delay_ms, not before; drawn as the old one's is, beside it as that is beside its own; gone as the pointer leaves" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {})
  let o = t.get(Button, label="复制 old")
  let n = t.get(Button, label="复制 new")
  let tip_of = fn(label : String) { t.semantics().filter(fn(s) { s.role == Tooltip && s.label == label }) }
  // (the old one's, rested on long enough)
  t.move(o.rect.0 + 16.0, o.rect.1 + 16.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(tip_of("复制 old").length(), 1, msg="the old one's shown")
  let old_tip = tip_of("复制 old")[0]
  let old_drawn = drawn_within(t, old_tip.rect)
  t.leave()
  t.run_for(tip_settled_ms)
  // (the node's: not yet a moment before its time, shown at it)
  t.move(n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.run_for(tip_delay_ms - tip_short_ms)
  assert_eq(tip_of("复制 new").length(), 0, msg="not yet")
  t.run_for(tip_short_ms + tip_settled_ms)
  assert_eq(tip_of("复制 new").length(), 1, msg="shown")
  let new_tip = tip_of("复制 new")[0]
  // (beside its button as the old one is beside its own)
  assert_eq(
    (new_tip.rect.0 - n.rect.0, new_tip.rect.1 - n.rect.1, new_tip.rect.2, new_tip.rect.3),
    (old_tip.rect.0 - o.rect.0, old_tip.rect.1 - o.rect.1, old_tip.rect.2, old_tip.rect.3),
    msg="where, how big: new \{new_tip.rect} by \{n.rect}; old \{old_tip.rect} by \{o.rect}",
  )
  let new_drawn = drawn_within(t, new_tip.rect)
  assert_eq(new_drawn, old_drawn, msg="drawn: new \{new_drawn} old \{old_drawn}")
  t.leave()
  t.run_for(tip_settled_ms)
  assert_eq(tip_of("复制 new").length(), 0, msg="gone as the pointer left")
}

///|
test "a tool as a node's tip: shown at once as the keyboard's focus shows on it; shut by a press till the hand leaves; gone as it takes no press" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {})
  let n = t.get(Button, label="复制 new")
  let shown = fn() { t.semantics().any(fn(s) { s.role == Tooltip && s.label == "复制 new" }) }
  t.tab()
  assert_true(shown(), msg="the focus on it: at once")
  // (a press on it: shut, though the pointer rests on it)
  t.tap(n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_false(shown(), msg="shut by a press")
  t.leave()
  t.run_for(tip_settled_ms)
  t.move(n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_true(shown(), msg="left and rested on again: shown")
  said.set({ icon: "copy", label: "复制", on: false, disabled: true })
  t.run_for(tip_settled_ms)
  assert_false(shown(), msg="taking no press: gone")
}

///|
/// A while past a tip's coming or going (its fade over), and a moment short of its time.
let tip_settled_ms : Double = 200.0

///|
let tip_short_ms : Double = 20.0

///|
test "a tool as a node's tip, the pointer resting on it pressed and let go there: shut, past its time too; its holder said to take no press or a modal layer coming over it while it waits, never shown past its time; shown, gone at that cause" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let shown = fn(t : @ui.Tester) { t.semantics().any(fn(s) { s.role == Tooltip && s.label == "复制 new" && !s.hidden }) }
  // (pressed and let go where it rests, as the host gives a mouse's: shut past its time)
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {})
  let n = t.get(Button, label="复制 new")
  let (cx, cy) = (n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.move(cx, cy)
  t.touch(0, cx, cy)
  t.touch(2, cx, cy)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_false(shown(t), msg="pressed and let go, resting there: shut")
  for case in ["holder", "modal"] {
    let held = @signals.signal(true)
    let modal = @signals.signal(false)
    let t = tools_tester(said, @signals.signal(page_viewer_ink()), {}, held~, modal~)
    let n = t.get(Button, label="复制 new")
    t.move(n.rect.0 + 16.0, n.rect.1 + 16.0)
    t.run_for(tip_short_ms)
    if case == "holder" {
      held.set(false)
    } else {
      modal.set(true)
    }
    // (no frame drawn between that and its time, past it: never shown, not even for a frame)
    let went = tips_made.val.unwrap().went_at
    t.advance(tip_delay_ms + tip_settled_ms)
    t.frames_owed()
    assert_false(shown(t), msg="\{case}: while it waited: never shown")
    assert_eq(tips_made.val.unwrap().went_at, went, msg="\{case}: never come, never gone")
    // (back, rested on anew: shown; then the same cause: gone at once)
    if case == "holder" {
      held.set(true)
    } else {
      modal.set(false)
    }
    t.leave()
    t.move(n.rect.0 + 16.0, n.rect.1 + 16.0)
    t.run_for(tip_delay_ms + tip_settled_ms)
    assert_true(shown(t), msg="\{case}: rested on anew: shown")
    if case == "holder" {
      held.set(false)
    } else {
      modal.set(true)
    }
    t.run_for(tip_settled_ms)
    assert_false(shown(t), msg="\{case}: shown, then: gone")
  }
}

///|
test "a tool as a node made and let go again and again, its tip shown each time: nothing of them left in the tips' layer" {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let there = @signals.signal(true)
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {}, there~)
  let layer_kids = fn() { tips_layer.val.unwrap().kids().length() }
  for _ in 0..<3 {
    let n = t.get(Button, label="复制 new")
    t.move(n.rect.0 + 16.0, n.rect.1 + 16.0)
    t.run_for(tip_delay_ms + tip_settled_ms)
    assert_eq(layer_kids(), 1, msg="its tip's holder")
    there.set(false)
    t.run_for(tip_settled_ms)
    assert_eq(layer_kids(), 0, msg="let go: its tip's holder gone with it")
    there.set(true)
    t.leave()
    t.draw()
  }
}

///|
/// A focusable node "A" and, made after it, its tip in a layer `layer` gives (as the tips' layer is asked): the tester,
/// A, what attaches its tip (to call once A has the focus), and A's tip's words.
fn tipped_tester(layer_on : Ref[Bool]) -> (@ui.Tester, Ref[@view.View?], Ref[() -> Unit]) {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0)
  t.check_looks(false)
  let a : Ref[@view.View?] = Ref(None)
  let attach : Ref[() -> Unit] = Ref(fn() {  })
  @ui.set_view_app(fn(root) {
    root.box(fn(g) { g.width(Is(Some(60.0))) |> ignore }) |> ignore
    let node = root.box(fn(v) {
      v.width(Is(Some(32.0))).height(Is(Some(32.0))).focusable(Is(true)).says(Is(Some(@view.said(Button, label="A")))) |> ignore
    })
    a.val = Some(node)
    let layer = root.box(fn(l) { l.over(Is(true)) |> ignore })
    let tips = TipLayer::new(fn() { if layer_on.val { Some(layer) } else { None } })
    attach.val = fn() { tip_node(tips, node, fn() { "A's tip" }) |> ignore }
  })
  t.draw()
  (t, a, attach)
}

///|
test "a tip put on a control that has the keyboard's focus already: shown at once; its layer not there as it is first shown: none, then shown the next time it is, the layer there" {
  let shown = fn(t : @ui.Tester) { t.semantics().any(fn(s) { s.role == Tooltip && s.label == "A's tip" && !s.hidden }) }
  let layer_on = Ref(true)
  let (t, _a, attach) = tipped_tester(layer_on)
  t.tab()
  (attach.val)()
  t.frames_owed()
  assert_true(shown(t), msg="the focus on it already: shown at once")
  // (no layer as it is first shown: none; the layer there, the next time it is)
  let layer_on = Ref(false)
  let (t, _a, attach) = tipped_tester(layer_on)
  (attach.val)()
  t.tab()
  assert_false(shown(t), msg="no layer: none")
  layer_on.val = true
  t.tap(300.0, 150.0)
  t.tab()
  assert_true(shown(t), msg="the layer there: shown the next time")
}

///|
/// How opaque the tip of "复制 new" is drawn now: its ground's alpha, and its words' most (0 where none is drawn).
fn tip_alphas(t : @ui.Tester) -> (Double, Double) {
  let tips = t.semantics().filter(fn(s) { s.role == Tooltip && s.label == "复制 new" })
  guard tips is [tip, ..] else { return (0.0, 0.0) }
  let (rx, ry, rw, rh) = tip.rect
  let mut ground = 0.0
  let mut words = 0.0
  for line in t.drawlist().split("\n") {
    let f = line.split(" ").map(fn(v) { v.to_string() }).to_array()
    if f.length() < 21 || f[0] != "i" {
      continue
    }
    let (x, y, a) = match (number_of(f[1]), number_of(f[2]), number_of(f[12])) {
      (Some(x), Some(y), Some(a)) => (x, y, a)
      _ => continue
    }
    if x < rx - 0.5 || y < ry - 0.5 || x > rx + rw + 0.5 || y > ry + rh + 0.5 {
      continue
    }
    if f[6] == "0" && x == rx && y == ry {
      ground = a
    } else if f[6] == "1" && a > words {
      words = a
    }
  }
  (ground, words)
}

///|
/// A tip rested on and shown, then: left at 40 into its coming in, rested on again 40 after (within the skip: at once).
/// How opaque it is drawn (tip_alphas) at each of `looks` (from its showing), frames drawn all along (`dense`) or none
/// but at those moments; and at each turn, just before it and just after.
fn tip_turns(dense : Bool, looks : Array[Double]) -> Array[(Double, Double)] raise {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {})
  let n = t.get(Button, label="复制 new")
  let (cx, cy) = (n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.move(cx, cy)
  t.run_for(tip_delay_ms)
  let start = t.time()
  let out : Array[(Double, Double)] = []
  let to = fn(at : Double) {
    let ms = start + at - t.time()
    if ms > 0.0 {
      if dense {
        t.run_for(ms)
      } else {
        t.advance(ms)
        t.frames_owed()
        t.draw()
      }
    }
  }
  for at in looks {
    to(at)
    out.push(tip_alphas(t))
    // (the turns: left at 40, back at 80, each looked at as it happens)
    if at == tip_short_ms * 2.0 {
      t.touch(1, 380.0, 190.0)
      t.draw()
      out.push(tip_alphas(t))
    } else if at == tip_short_ms * 4.0 {
      t.touch(1, cx, cy)
      t.draw()
      out.push(tip_alphas(t))
    }
  }
  out
}

///|
test "a tip coming in and going as kit's does: its ground the first half of the way, its words the second (none while its ground is not whole); turned back and forth, from where it was each time; frames or none between, the same" {
  let looks = [tip_short_ms / 4.0, tip_short_ms * 2.0, tip_short_ms * 3.0, tip_short_ms * 4.0, tip_short_ms * 5.0, tip_settled_ms * 2.0]
  let dense = tip_turns(true, looks)
  assert_eq(tip_turns(false, looks), dense, msg="frames or none, the same")
  // (5 in: its ground part of the way, its words none)
  let (g5, w5) = dense[0]
  assert_true(g5 > 0.0 && g5 < 1.0 && w5 == 0.0, msg="5 in: \{dense[0]}")
  // (left at 40: as it was the moment before, then going from there)
  assert_eq(dense[2], dense[1], msg="left at 40: from where it was")
  // (going: its words first, as its ground stays)
  assert_true(dense[3].1 < dense[2].1 && dense[3].0 == dense[2].0, msg="going: its words less at 60 \{dense}")
  // (back at 80: from where it was going, no jump)
  assert_eq(dense[5], dense[4], msg="back at 80: from where it was")
  // (whole at last, its words too)
  assert_true(dense[7].0 == 1.0 && dense[7].1 > 0.0, msg="whole at 400: \{dense}")
}

///|
/// Where the tip of tool `which` ("old" or "new", tools_tester's) is drawn and how big, as its ground is drawn (the
/// biggest box drawn under its tool, beside it), in its tool's terms: at each turn of the hand on it and away (shown
/// whole; half way gone; back on it a moment; whole again; most of the way gone).
fn tip_drawn_turns(which : String) -> Array[String] raise {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {})
  let b = t.get(Button, label="复制 " + which)
  let (bx, by, bw, bh) = b.rect
  let (cx, cy) = (bx + bw / 2.0, by + bh / 2.0)
  let look = fn(what : String) -> String {
    let mut best = ""
    let mut most = 0.0
    for line in t.drawlist().split("\n") {
      let f = line.split(" ").map(fn(v) { v.to_string() }).to_array()
      if f.length() < 21 || f[0] != "i" || f[6] != "0" {
        continue
      }
      match (number_of(f[1]), number_of(f[2]), number_of(f[3]), number_of(f[4])) {
        (Some(x), Some(y), Some(w), Some(h)) if y >= by + bh && y < by + bh + 60.0 && x > bx - 80.0 && x < bx + bw + 80.0 && w * h > most => {
          most = w * h
          let r = fn(v : Double) { ((v * 100.0).round() / 100.0).to_string() }
          best = "\{what}: \{r(x - bx)} \{r(y - by)} \{r(w)} \{r(h)}"
        }
        _ => ()
      }
    }
    if best == "" {
      "\{what}: none"
    } else {
      best
    }
  }
  let out = []
  t.move(cx, cy)
  t.run_for(tip_delay_ms + 400.0)
  out.push(look("whole"))
  t.move(380.0, 190.0)
  t.run_for(@kit.pop_out_ms / 2.0)
  out.push(look("half way gone"))
  t.move(cx, cy)
  t.run_for(a_moment_ms)
  out.push(look("back on it a moment"))
  t.run_for(tip_settled_ms)
  out.push(look("whole again"))
  t.move(380.0, 190.0)
  t.run_for(@kit.pop_out_ms * 0.75)
  out.push(look("most of the way gone"))
  out
}

///|
test "a tip going as kit's goes, drawn smaller as it fades about its edge toward its tool (pop_out), whole as it comes back from wherever it was turned: where and how big it is drawn at each turn, as the old one's" {
  let old = tip_drawn_turns("old")
  let new = tip_drawn_turns("new")
  assert_eq(new, old, msg="new \{new} old \{old}")
  // (going, smaller than whole: the scale itself, not only the fade)
  assert_true(new[1] != new[0], msg="half way gone as big as whole: \{new}")
}

///|
/// A finger held on tool "复制 new" long_press_ms and let go there, frames drawn only as asked (none but the ones after
/// each event); then `after`: whether its tip was read out shown as it was held, just after it was let go, `wait` after
/// that, and how many times it was pressed.
fn finger_held_tip(wait : Double, then_press : Bool) -> (Bool, Bool, Bool, Int) raise {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  // (a touch screen's app: the hand a finger's)
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), pressed, platform=1)
  let shown = fn() { t.semantics().any(fn(s) { s.role == Tooltip && s.label == "复制 new" && !s.hidden }) }
  let n = t.get(Button, label="复制 new")
  let (cx, cy) = (n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.touch(0, cx, cy)
  t.run_for(@ui.long_press_ms + 50.0)
  let held = shown()
  t.touch(2, cx, cy)
  t.run_for(a_moment_ms)
  let lifted = shown()
  if then_press {
    // (a press elsewhere, on nothing)
    t.touch(0, 380.0, 190.0)
    t.touch(2, 380.0, 190.0)
  }
  t.run_for(wait)
  (held, lifted, shown(), pressed.get("new").unwrap_or(0))
}

///|
test "a tool as a node's tip held open by a finger, as kit's tooltip: shown once held long_press_ms, the press then no tap; on a while after it is let go, gone tooltip_lifted_ms after, or at the next press wherever it lands" {
  let (held, lifted, later, pressed) = finger_held_tip(@kit.tooltip_lifted_ms / 2.0, false)
  assert_eq((held, lifted, later, pressed), (true, true, true, 0), msg="held, let go, half its while after: still: \{(held, lifted, later, pressed)}")
  let (_, _, gone, _) = finger_held_tip(@kit.tooltip_lifted_ms + @kit.pop_out_ms * 2.0, false)
  assert_true(!gone, msg="its while over: gone")
  let (_, _, pressed_off, _) = finger_held_tip(@kit.pop_out_ms * 2.0, true)
  assert_true(!pressed_off, msg="the next press, elsewhere: gone")
}

///|
/// Tool "复制 new" pressed 1 in from its right edge (`platform`: 0 a mouse's, 1 a touch screen's), moved `out` points
/// right, let go there; held `hold` ms first: how many times it was pressed.
fn let_go_beside(platform : Int, out : Double, hold? : Double = 0.0) -> Int raise {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), pressed, platform~)
  let n = t.get(Button, label="复制 new")
  let (x, y) = (n.rect.0 + n.rect.2 - 1.0, n.rect.1 + 16.0)
  t.touch(0, x, y)
  if hold > 0.0 {
    t.run_for(hold)
  }
  t.touch(1, x + out, y)
  t.touch(2, x + out, y)
  t.draw()
  pressed.get("new").unwrap_or(0)
}

///|
test "a tool as a node pressed only as it is let go on it: from inside its edge moved out a little and let go, no press, by a mouse or a finger; let go where it went down, a press; a mouse held past long_press_ms, a press let go on it, none moved off it" {
  for p in [0, 1] {
    assert_eq(let_go_beside(p, 3.0), 0, msg="platform \{p}: let go beside it")
    assert_eq(let_go_beside(p, 0.0), 1, msg="platform \{p}: let go on it")
  }
  assert_eq(let_go_beside(0, 10.0, hold=@ui.long_press_ms + 50.0), 0, msg="a mouse held, let go off it")
  assert_eq(let_go_beside(0, 0.0, hold=@ui.long_press_ms + 50.0), 1, msg="a mouse held, let go on it")
}

///|
/// A finger held on tool "复制 new" long_press_ms, its tip shown, then `then` done (to the tester, what it says, how
/// it is said): whether the tip shows pop_out_ms twice after that, and again `again` later (after `after`).
fn held_then(then : (@ui.Tester, @signals.Signal[ToolSaid], Double, Double) -> Unit, after : (@ui.Tester, @signals.Signal[ToolSaid]) -> Unit) -> (Bool, Bool, Bool) raise {
  let said = @signals.signal({ icon: "copy", label: "复制", on: false, disabled: false }, same=fn(a, b) { a == b })
  let t = tools_tester(said, @signals.signal(page_viewer_ink()), {}, platform=1)
  let shown = fn() { t.semantics().any(fn(s) { s.role == Tooltip && s.label == "复制 new" && !s.hidden }) }
  let n = t.get(Button, label="复制 new")
  let (cx, cy) = (n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.touch(0, cx, cy)
  t.run_for(@ui.long_press_ms + 50.0)
  let held = shown()
  then(t, said, cx, cy)
  t.run_for(@kit.pop_out_ms * 2.0)
  let gone = !shown()
  after(t, said)
  t.run_for(@kit.pop_out_ms * 2.0)
  (held, gone, !shown())
}

///|
test "a tool as a node's tip a finger held open: called off by the system, gone then, none of it kept; the tool taken from the hand (unable), gone, not shown again as it can be pressed again; Escape, gone" {
  let off = held_then(fn(t, _, x, y) { t.touch(3, x, y) }, fn(_, _) {  })
  assert_eq(off, (true, true, true), msg="called off: \{off}")
  let unable = held_then(
    fn(_, s, _, _) { s.set({ icon: "copy", label: "复制", on: false, disabled: true }) },
    fn(t, s) {
      s.set({ icon: "copy", label: "复制", on: false, disabled: false })
      t.draw()
    },
  )
  assert_eq(unable, (true, true, true), msg="unable, then able again: \{unable}")
  let escaped = held_then(fn(t, _, x, y) {
    t.touch(2, x, y)
    t.run_for(a_moment_ms)
    t.key(@ui.key_escape)
  }, fn(_, _) {  })
  assert_eq(escaped, (true, true, true), msg="let go, Escape: \{escaped}")
}

///|
/// A moment after an input (a finger let go, the pointer back on a tool): less than any of the motions it sets off.
let a_moment_ms : Double = 50.0
