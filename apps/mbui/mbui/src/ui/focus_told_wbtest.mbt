// What of the old views reads the focus (Ctx::has_focus, focused_id, focus_shown) told of every move of it, one made as
// a frame is built too: the focus taken from 甲 and given back to it within one build (a menu's item taking it as the
// pointer comes onto it, built each pass of a frame, before a field asking for it back), what read it while it was off
// 甲 built again from it, what read none of it kept.

///|
/// An old view taking the focus to its own "乙" each time it is built in the frame `steal` was set in; after it three
/// old views each reading one thing of 甲's focus (whether it has it, whether it is what has it, whether it shows), what
/// each read as it was last built in `seen`; after them an old view of a field "甲" given the focus (shown) as it is first
/// built, and asking for it back as it is built without it while `steal`; after that an old view reading nothing of it,
/// its builds counted in `others`. `check`: the Tester's own check that each frame is as built whole.
fn told_tester(
  steal : @signals.Signal[Bool],
  seen : Array[Bool],
  others : Ref[Int],
  check : Bool,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(check)
  let stole_in = Ref(-1)
  let first = Ref(true)
  // (甲's id, as its own view names it: 0, none's, till it is built)
  let a = Ref(0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let b = c.id("乙")
      c.focusable(b)
      c.box(id=b, w=Px(80.0), h=Px(30.0), fn() {  }) |> ignore
      // (each pass of the frame it is set in, as a menu's item under the pointer that moved in that frame: kit's menu)
      if steal.get() && (stole_in.val < 0 || stole_in.val == c.frame_number()) {
        stole_in.val = c.frame_number()
        c.focus_on(b)
      }
    })
    .height(Is(Some(30.0)))
    |> ignore
    let reads : Array[(Ctx) -> Bool] = [
      fn(c) { c.has_focus(a.val) },
      fn(c) { a.val != 0 && c.focused_id() == a.val },
      fn(c) { c.focus_shown(a.val) },
    ]
    for i, read in reads {
      old(root, fn(c) {
        seen[i] = read(c)
        c.text(if seen[i] { "有" } else { "无" }) |> ignore
      })
      .height(Is(Some(30.0)))
      |> ignore
    }
    old(root, fn(c) {
      a.val = c.id("甲")
      c.focusable(a.val)
      c.box(id=a.val, w=Px(80.0), h=Px(30.0), fn() {  }) |> ignore
      if first.val {
        first.val = false
        c.focus_on(a.val, visible=true)
      } else if steal.get() && !c.has_focus(a.val) {
        c.focus_on(a.val, visible=true)
      }
    })
    .height(Is(Some(30.0)))
    |> ignore
    old(root, fn(c) {
      others.val = others.val + 1
      c.text("无关") |> ignore
    })
    .height(Is(Some(30.0)))
    |> ignore
  })
  t.draw()
  // (laid out the same twice: each frame after kept where nothing it read changed, as a host draws it, Tester::draw
  // building what is kept anew)
  t.clock_frame()
  t.clock_frame()
  t
}

///|
test "the focus taken from a field and given back to it as a frame is built: what read whether it has it, whether it is what has it and whether that shows, each while it was taken, built again from it by the next frame, each frame as built whole" {
  let steal = @signals.signal(false)
  let seen = [false, false, false]
  let t = told_tester(steal, seen, Ref(0), true)
  let before = seen.copy()
  steal.set(true)
  // (the change the test made: a step of its own, the frame after it built from what it changed alone)
  t.frame()
  t.clock_frame()
  let next = seen.copy()
  t.clock_frame()
  assert_eq((before, next, seen), ([true, true, true], [true, true, true], [true, true, true]))
}

///|
test "the focus taken from a field and given back to it as a frame is built: in the frame after, what read none of it not built again (that frame alone counted: the frame it was taken in builds the frame whole)" {
  let steal = @signals.signal(false)
  let seen = [false, false, false]
  let others = Ref(0)
  let t = told_tester(steal, seen, others, false)
  steal.set(true)
  // (the change the test made: a step of its own, the frame after it built from what it changed alone)
  t.frame()
  let built = others.val
  t.clock_frame()
  let next = (seen.copy(), others.val - built)
  t.clock_frame()
  assert_eq((next, (seen, others.val - built)), (([true, true, true], 0), ([true, true, true], 0)))
}
