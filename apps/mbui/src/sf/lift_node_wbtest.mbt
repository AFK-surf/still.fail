// What a finger holds lifted as a node (lift_node): its scale on lift_spring from the moment its menu is said up, all
// the way, and back down from the moment it goes, as lift_of's; lifted, drawn over the menu's scrim and kept clear of
// the sheet the menu is in.

///|
let lift_test_side : Double = 100.0

///|
/// How much larger it is all the way up (a message's picture's).
let lift_test_scale : Double = 1.04

///|
/// A moment on its way up to look at.
let lift_test_mid : Double = 120.0

///|
/// The square lifted, as it is drawn: (x, y, w, h) and where among what is drawn; None where it is not.
fn lift_square(t : @ui.Tester) -> ((Double, Double, Double, Double), Int)? {
  for i, r in t.drawn_rects() {
    if r.4 == lift_test_ink {
      return Some(((r.0, r.1, r.2, r.3), i))
    }
  }
  None
}

///|
let lift_test_ink : Int64 = 0x336699FFL

///|
test "lifted as lift_of's: on lift_spring from the moment its menu is said up, back down from the moment it goes" {
  let open = @signals.signal(false)
  let root : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(r) {
      root.val = Some(r)
      r.box(fn(b) {
        b.width(Is(Some(lift_test_side))).height(Is(Some(lift_test_side))).ground(Is(lift_test_ink)) |> ignore
        lift_node(b, fn() { false }, fn() { open.get() }, lift_test_scale)
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
    platform=2,
  )
  t.run_for(lift_test_mid)
  let want = @motion.Way::new(0.0)
  for to in [true, false] {
    let at = t.time() + lift_test_mid
    root.val.unwrap().at_moment(at, fn() { open.set(to) }) |> ignore
    want.go(if to { 1.0 } else { 0.0 }, @motion.lift_spring, at~)
    for dt in [lift_test_mid / 2.0, lift_test_mid, @ui.move_most_ms] {
      t.run_for(at + dt - t.time())
      let w = lift_test_side * (1.0 + (lift_test_scale - 1.0) * want.value_at(t.time()))
      let got = lift_square(t).unwrap().0.2
      assert_true((got - w).abs() < 0.001, msg="\{to} at \{dt}: \{got} wanted \{w}")
    }
  }
  assert_eq(lift_square(t).unwrap().0.2, lift_test_side)
  assert_eq(t.audit(), [])
}

///|
test "lifted with its menu up from the foot: drawn over the scrim, and up clear of the sheet the menu is in; back in its place as it goes" {
  presenters_reset()
  let square : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(
    @ui.old_views_here,
    tree=fn(root) {
      presented_tree(fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() { presented(c) })
      })(root)
      // (at the window's foot, where the sheet comes up)
      root.box(fn(b) {
        square.val = Some(b)
        b
        .over(Is(true))
        .offset(Is((20.0, 844.0 - lift_test_side - 20.0)))
        .width(Is(Some(lift_test_side)))
        .height(Is(Some(lift_test_side)))
        .ground(Is(lift_test_ink))
        |> ignore
        lift_node(b, fn() { false }, fn() { presented_from(Node(b)) }, lift_test_scale)
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  t.draw()
  let (laid, _) = lift_square(t).unwrap()
  menu([Some(menu_item_of("一项", fn() {  }))], from=Node(square.val.unwrap()))
  t.run_for(@ui.move_most_ms)
  let (up, at) = lift_square(t).unwrap()
  assert_true((up.2 - lift_test_side * lift_test_scale).abs() < 0.001, msg="\{Repr(up)}")
  assert_true(up.1 + up.3 < laid.1 + laid.3, msg="up clear of the sheet: \{Repr(up)} from \{Repr(laid)}")
  // (drawn after the scrim: a rect over the whole window drawn before it)
  let mut scrim : Int? = None
  for i, r in t.drawn_rects() {
    if scrim is None && r.2 >= 390.0 && r.3 >= 844.0 && (r.4 & 0xFFL) < 0xFFL {
      scrim = Some(i)
    }
  }
  assert_true(scrim is Some(s) && s < at, msg="scrim \{Repr(scrim)}, square \{at}")
  close_presented_of(last_presented())
  t.run_for(@ui.move_most_ms)
  assert_eq(lift_square(t).unwrap().0, laid)
  assert_true(!presented_drawn())
}
