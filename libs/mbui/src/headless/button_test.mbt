// The headless button (@headless.button), under a look of the tests' own: found a button by its name, pressed by the
// pointer, by Enter and Space, by a screen reader's ask, once each; disabled, none of these and the focus let go; what
// its look reads of it, by the hand of the moment; its press asked by what its look adds (a gesture, a reaction) taken
// as the hand's is. No look is held here but the tests' own; each window is made by `window` (window_test.mbt), which
// holds that the button's own file draws and lays out nothing.

///|
/// A part with a look, as a library of looks writes one over the button: its caller's place handed on (`made_for`).
#callsite(autofill(loc))
fn looked(parent : @view.View, loc~ : SourceLoc) -> @view.View {
  @headless.button(parent, fn() { "带外观的" }, fn(_) {  }, fn(v, _) { v.width(Is(Some(120.0))).height(Is(Some(40.0))).ground(Is(c_rest)) |> ignore }, made_for=loc)
}

///|
/// A place of this file's: where a test asks for a part.
#callsite(autofill(loc))
fn looked_at(loc~ : SourceLoc) -> SourceLoc {
  loc
}

///|
test "a button's node is made at the line that says it; a part with a look over it, at the look's line, for the line that asked for the part; of what is said of it, the button's own file says what it is read out as, and nothing else the tree keeps a place of" {
  let asked : Ref[SourceLoc?] = Ref(None)
  let made : Array[@view.View] = []
  let t = window(fn(root) {
    made.push(@headless.button(root, fn() { "直接的" }, fn(_) {  }, fn(v, _) { v.width(Is(Some(120.0))).height(Is(Some(40.0))).ground(Is(c_rest)) |> ignore }))
    asked.val = Some(looked_at())
    made.push(looked(root, loc=asked.val.unwrap()))
  })
  let tree = @ui.view_tree().unwrap()
  let here = "mbui/src/headless/button_test.mbt:"
  let (direct, part) = (tree.source_of(made[0].id()), tree.source_of(made[1].id()))
  // (what `window` holds sees the button's own file: were its place another's, it would hold nothing)
  let own = made.map(fn(v) { said_here(tree, v) })
  assert_eq(
    (direct.0.has_prefix(here), direct.1, part.0.has_prefix(here), part.1, own),
    (true, direct.0, true, @view.source_place(asked.val.unwrap()), [["Says"], ["Says"]]),
  )
  assert_true(t.query(Button, label="直接的") is Some(_))
}

///|
/// The grounds the tests' look draws, one a state: what a test reads the state its look was told by.
let c_rest : Int64 = 0x101010FFL

///|
let c_hovered : Int64 = 0x202020FFL

///|
let c_pressed : Int64 = 0x303030FFL

///|
let c_focus : Int64 = 0x404040FFL

///|
let c_disabled : Int64 = 0x606060FFL

///|
/// What a case keeps: its window, how often its button was pressed and the node each press was given, the node the
/// button is, what its look was handed to read of it, what its caller says of it (its name, whether it is disabled),
/// a value its caller's press reads (`touched`), and what keeps the hand from a node besides, each as a test says it: whether what holds it takes presses, the
/// bones it is in (0: none), whether a modal layer is over it, whether it is there (not: leaving, `leave_ms` long).
struct Case {
  t : @ui.Tester
  pressed : Ref[Int]
  given : Array[@view.NodeId]
  node : Ref[@view.NodeId?]
  state : Ref[@headless.Button?]
  name : @signals.Signal[String]
  off : @signals.Signal[Bool]
  touched : @signals.Signal[Int]
  holder : @signals.Signal[Bool]
  bones : @signals.Signal[Int64]
  modal : @signals.Signal[Bool]
  there : @signals.Signal[Bool]
}

///|
/// How long what holds a case's button leaves for: longer than a hold takes, so that it is still leaving as one is due.
let leave_ms : Double = 2.0 * @ui.long_press_ms

///|
/// A window 400 by 300 pointed at with `pointing`: a box "别处" 50 by 50 that takes the focus, then the button "保存",
/// 120 by 40, its ground its state's (c_…): the tests' look, and what `adds` adds to it. `unsays`: a look that says
/// the node is something else and takes no press.
fn case(
  pointing? : @ui.Pointing = Mouse,
  unsays? : Bool = false,
  adds? : (@view.View, @headless.Button) -> Unit = fn(_, _) {  },
) -> Case raise {
  let flag = fn(v : Bool) { @signals.signal(v, same=fn(a : Bool, b : Bool) { a == b }) }
  let (pressed, given, node, state) = (Ref(0), [], Ref(None), Ref(None))
  let name = @signals.signal("保存")
  let touched = @signals.signal(0)
  let (off, holder, modal, there) = (flag(false), flag(true), flag(false), flag(true))
  let bones = @signals.signal(0L, same=fn(a, b) { a == b })
  let t = window(pointing~, fn(root) {
    root.box(fn(e) {
      e
      .width(Is(Some(50.0)))
      .height(Is(Some(50.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="别处"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    root.box(fn(h) {
      h.presses(By(fn() { holder.get() })).bones(By(fn() { bones.get() })) |> ignore
      h.show(at_once=true, fn() { there.get() }, leave=leave_ms, fn(s) {
        let made = @headless.button(
          s,
          fn() { name.get() },
          fn(v) {
            pressed.val += 1
            given.push(v.id())
            touched.get() |> ignore
          },
          fn(v, b) {
            state.val = Some(b)
            v
            .width(Is(Some(120.0)))
            .height(Is(Some(40.0)))
            .ground(By(fn() {
              if b.disabled() {
                c_disabled
              } else if b.pressed() {
                c_pressed
              } else if b.focus_shown() {
                c_focus
              } else if b.hovered() {
                c_hovered
              } else {
                c_rest
              }
            }))
            |> ignore
            if unsays {
              v.says(Is(Some(@view.said(Link, label="别的")))).presses(Is(false)).focusable(Is(false)).on_press(fn() {  })
              |> ignore
            }
            adds(v, b)
          },
          disabled=fn() { off.get() },
        )
        node.val = Some(made.id())
      })
    })
    |> ignore
    root.box(fn(m) { m.over(Is(true)).modal(By(fn() { modal.get() })) |> ignore }) |> ignore
  })
  { t, pressed, given, node, state, name, off, touched, holder, bones, modal, there }
}

///|
/// The ground the button's look draws now (its rect 120 by 40).
fn Case::ground(self : Case) -> Int64 {
  for r in self.t.drawn_rects() {
    if r.2 == 120.0 && r.3 == 40.0 {
      return r.4
    }
  }
  0L
}

///|
/// The middle of the button.
fn Case::middle(self : Case) -> (Double, Double) raise {
  let (x, y, w, h) = self.t.get(Button, label="保存").rect
  (x + w / 2.0, y + h / 2.0)
}

///|
/// Who has the keyboard's focus, by name ("": nobody that says a name).
fn Case::focus(self : Case) -> String {
  match self.t.focused() {
    Some(s) => s.label
    None => ""
  }
}

///|
/// What keeps the hand from a node, each as a case says it and takes it back (a frame drawn after each): disabled;
/// what holds it said to take no press; in its bones; a modal layer over it; leaving.
fn Case::kept_from(self : Case) -> Array[(String, () -> Unit, () -> Unit)] {
  let k = self
  let told = fn(f : () -> Unit) {
    fn() {
      f()
      k.t.frame()
    }
  }
  [
    ("disabled", told(fn() { k.off.set(true) }), told(fn() { k.off.set(false) })),
    ("held by what takes no press", told(fn() { k.holder.set(false) }), told(fn() { k.holder.set(true) })),
    ("in its bones", told(fn() { k.bones.set(0x808080FFL) }), told(fn() { k.bones.set(0L) })),
    ("under a modal layer", told(fn() { k.modal.set(true) }), told(fn() { k.modal.set(false) })),
    ("leaving", told(fn() { k.there.set(false) }), told(fn() { k.there.set(true) })),
  ]
}

///|
test "a button is read out a button by its name, with a press to do; a tap presses it once, given the node it is" {
  let k = case()
  let s = k.t.get(Button, label="保存")
  k.t.click(Button, label="保存")
  assert_eq((s.disabled, s.actions.contains(Activate), k.pressed.val, k.given == [k.node.val.unwrap()]), (false, true, 1, true))
}

///|
test "a button's name as its caller says it now" {
  let k = case()
  k.name.set("另存为")
  k.t.frame()
  assert_eq((k.t.query(Button, label="保存") is None, k.t.get(Button, label="另存为").actions.contains(Activate)), (true, true))
}

///|
test "Tab goes to a button; Enter presses it once, Space once, a screen reader's ask once" {
  let k = case()
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let at = k.focus()
  k.t.enter()
  let entered = k.pressed.val
  k.t.key(@ui.key_space)
  let spaced = k.pressed.val
  k.t.act(Button, Activate, label="保存")
  assert_eq((at, entered, spaced, k.pressed.val), ("保存", 1, 2, 3))
}

///|
test "a button disabled: read out disabled with nothing to do, no press by a tap, a key or its state's press; Tab passes it" {
  let k = case()
  k.off.set(true)
  k.t.frame()
  let s = k.t.get(Button, label="保存")
  let (x, y) = k.middle()
  k.t.tap(x, y)
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  k.t.enter()
  k.t.key(@ui.key_space)
  k.state.val.unwrap().press()
  assert_eq((s.disabled, s.actions.contains(Activate), k.focus() == "保存", k.pressed.val), (true, false, false, 0))
}

///|
test "a button disabled in the change that presses it, the tree not yet told: not pressed" {
  let k = case()
  // (as one change: what its caller says read by the press itself, not only by what the tree was last told)
  @signals.start_batch()
  k.off.set(true)
  k.state.val.unwrap().press()
  @signals.end_batch()
  assert_eq(k.pressed.val, 0)
}

///|
test "a button with the focus, disabled: the focus let go of it at that cause; able again, Tab comes to it" {
  let k = case()
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let had = k.focus()
  k.off.set(true)
  // (at that cause, no frame drawn)
  let lost = k.focus()
  k.t.draw()
  k.off.set(false)
  k.t.draw()
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  k.t.enter()
  assert_eq((had, lost, k.focus(), k.pressed.val), ("保存", "", "保存", 1))
}

///|
test "what a button's look reads under a mouse: hovered as the pointer comes over it, pressed while held on it, hovered again let go (pressed once), neither with the pointer gone" {
  let k = case()
  let (x, y) = k.middle()
  let rest = k.ground()
  k.t.move_to(x, y)
  let over = k.ground()
  k.t.press_at(x, y)
  let down = k.ground()
  k.t.release(x, y)
  let up = k.ground()
  k.t.move_to(390.0, 290.0)
  assert_eq((rest, over, down, up, k.ground(), k.pressed.val), (c_rest, c_hovered, c_pressed, c_hovered, c_rest, 1))
}

///|
test "what a button's look reads under a finger: pressed while it is held on it, never hovered, before the tap or after" {
  let k = case(pointing=Finger)
  let (x, y) = k.middle()
  k.t.press_at(x, y)
  let down = k.ground()
  k.t.release(x, y)
  let up = k.ground()
  assert_eq((down, up, k.state.val.unwrap().hovered(), k.pressed.val), (c_pressed, c_rest, false, 1))
}

///|
test "a mouse resting over a button and the hand then a finger (a machine with both): hovered no more once a finger's event is taken, wherever it lands; a mouse back over it, hovered again" {
  let k = case()
  let (x, y) = k.middle()
  let b = k.state.val.unwrap()
  k.t.host_says_finger(Some(false))
  k.t.move_to(x, y)
  let mouse = (k.ground(), b.hovered())
  // (a finger elsewhere: the mouse's pointer still where it was)
  k.t.host_says_finger(Some(true))
  k.t.tap(25.0, 25.0)
  let elsewhere = (k.ground(), b.hovered())
  k.t.host_says_finger(Some(false))
  k.t.move_to(x, y)
  let again = (k.ground(), b.hovered())
  // (a finger on it: held, pressed; let go, neither)
  k.t.host_says_finger(Some(true))
  k.t.press_at(x, y)
  let down = (k.ground(), b.hovered())
  k.t.release(x, y)
  let up = (k.ground(), b.hovered())
  assert_eq(
    (mouse, elsewhere, again, down, up, k.pressed.val),
    ((c_hovered, true), (c_rest, false), (c_hovered, true), (c_pressed, false), (c_rest, false), 1),
  )
}

///|
test "what a button's look reads: the focus come by the keyboard shows; disabled is told as its caller says it" {
  let k = case()
  let b = k.state.val.unwrap()
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let focus = (k.ground(), b.focus_shown(), b.disabled())
  k.off.set(true)
  k.t.draw()
  assert_eq((focus, (k.ground(), b.focus_shown(), b.disabled())), ((c_focus, true, false), (c_disabled, false, true)))
}

///|
test "a button's state's press: pressed as a press on it is, once, given the node it is" {
  let k = case()
  k.state.val.unwrap().press()
  assert_eq((k.pressed.val, k.given == [k.node.val.unwrap()]), (1, true))
}

///|
/// A little past a long press: where a hold has been told.
let held_ms : Double = @ui.long_press_ms + 50.0

///|
test "a look that takes the pointer by a gesture of its own, its tap and its hold ending in the state's press: pressed once each, given its node, the keyboard and a screen reader pressing it as ever; held on as it comes to be kept from the hand, its hold is called off and presses nothing, nor does a look that presses as it is called off" {
  let k = case(adds=fn(v, b) {
    v.gesture(
      @ui.touch_slop(),
      tap=fn(_) { b.press() },
      hold=(@ui.long_press_ms, fn(_) { b.press() }),
      // (a look's mistake: a press as its hold is called off, which the tree does as the node is kept from the hand)
      drag=fn(d) { if d.kind == Off { b.press() } },
    )
    |> ignore
  })
  let (x, y) = k.middle()
  k.t.press_at(x, y)
  k.t.release(x, y)
  let tapped = k.pressed.val
  k.t.press_at(x, y)
  k.t.run_for(held_ms)
  k.t.release(x, y)
  let held = k.pressed.val
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  k.t.enter()
  k.t.act(Button, Activate, label="保存")
  let asked = k.pressed.val
  // (the pointer held on it, and before its hold is due it comes to be kept from the hand)
  let kept = []
  for o in k.kept_from() {
    let (what, keep, back) = o
    k.t.press_at(x, y)
    keep()
    k.t.run_for(held_ms)
    k.t.release(x, y)
    back()
    kept.push((what, k.pressed.val))
  }
  k.t.press_at(x, y)
  k.t.release(x, y)
  assert_eq(
    (tapped, held, asked, kept, k.pressed.val, k.given == Array::make(5, k.node.val.unwrap())),
    (
      1,
      2,
      4,
      [("disabled", 4), ("held by what takes no press", 4), ("in its bones", 4), ("under a modal layer", 4), ("leaving", 4)],
      5,
      true,
    ),
  )
}

///|
test "a look whose reaction ends in the state's press (no hand in it): pressed where a press on it would be taken, and not while it is disabled, held by what takes no press, in its bones, under a modal layer or leaving" {
  let ask = @signals.signal(0)
  let k = case(adds=fn(v, b) { v.reacts(fn() { ask.get() }, fn(_) { b.press() }, at_start=false) })
  let again = fn() {
    ask.set(ask.untracked() + 1)
    k.t.frame()
    k.pressed.val
  }
  let first = again()
  let got = []
  for o in k.kept_from() {
    let (what, keep, back) = o
    keep()
    let kept = again()
    back()
    got.push((what, kept, again()))
  }
  assert_eq(
    (first, got),
    (
      1,
      [
        ("disabled", 1, 2),
        ("held by what takes no press", 2, 3),
        ("in its bones", 3, 4),
        ("under a modal layer", 4, 5),
        ("leaving", 5, 6),
      ],
    ),
  )
}

///|
test "a button's state's press asked where something is followed (an effect's run): what the press reads, the button's own and its caller's, is not followed by what asked" {
  let k = case()
  let b = k.state.val.unwrap()
  let runs = Ref(0)
  let stop = @signals.effect(fn() {
    runs.val += 1
    b.press()
  })
  // (what its caller's press read, and what the button itself reads to press: told anew)
  k.touched.set(1)
  k.off.set(true)
  k.off.set(false)
  stop()
  assert_eq((runs.val, k.pressed.val), (1, 1))
}

///|
test "a look that says, as it is made, that the node is something else and takes no press: what the button says of these after it stands: a button by its name, pressed and focused as one" {
  let k = case(unsays=true)
  k.t.click(Button, label="保存")
  k.t.act(Button, Focus, label="别处")
  k.t.tab()
  let at = k.focus()
  k.t.enter()
  assert_eq((k.t.query(Link, label="别的") is None, at, k.pressed.val), (true, "保存", 2))
}
