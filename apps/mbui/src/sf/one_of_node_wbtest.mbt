// One of a few as a node of the window's tree (one_of_node) beside the old one (one_of), each given the same two
// accounts: with touch and with keyboard and mouse; its rows where the old one's are, drawn the same at rest and
// pointed at, read out the same (a radio group, each a radio, on or off); a press, Space and the arrows choosing as the
// old one's do, Tab stopping at the chosen one alone; more than it lists, a select.

///|
/// The two it is given, by value and words.
let one_of_two : Array[(String, String)] = [("u1", "lin@example.com"), ("u2", "lin@work.example")]

///|
/// The old one (an old view's, its left column) and the node's (its right) side by side on a window of `platform`, each
/// choosing among `options` into a signal of its own, read back by it; what each was told it chose, in order, by side.
fn one_of_tester(
  platform : Int,
  options : Array[(String, String)],
  old_now : @signals.Signal[String],
  new_now : @signals.Signal[String],
  told : Array[String],
) -> @ui.Tester {
  presenters_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(360.0))) |> ignore
      @ui.old(h, fn(c) {
        c.box(w=Fill(1.0), fn() {
          one_of(c, "one-of/old", old_now.get(), options, fn(v) {
            told.push("old " + v)
            old_now.set(v)
          }, label="所属账号")
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(40.0))) |> ignore }) |> ignore
    root.box(fn(col) {
      col.width(Is(Some(360.0))) |> ignore
      one_of_node(col, fn() { new_now.get() }, fn() { options }, fn(v) {
        told.push("new " + v)
        new_now.set(v)
      }, label=fn() { "所属账号" })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The old radio (left) and the node's (right) read out as `label`.
fn one_of_pair(t : @ui.Tester, label : String) -> (@ui.SemNode, @ui.SemNode) {
  let all = t.all(Radio, label~)
  guard all.length() == 2 else { @halt.saying("\{label}: \{all.length()} radios") }
  if all[0].rect.0 < all[1].rect.0 { (all[0], all[1]) } else { (all[1], all[0]) }
}

///|
test "one of a few as a node beside the old one, with touch and with keyboard and mouse: its rows where the old one's are, drawn the same at rest and pointed at, read out the same" {
  for platform in [2, 0] {
    let told : Array[String] = []
    let old_now = @signals.signal("u1", same=fn(a, b) { a == b })
    let new_now = @signals.signal("u1", same=fn(a, b) { a == b })
    let t = one_of_tester(platform, one_of_two, old_now, new_now, told)
    assert_eq(t.all(RadioGroup, label="所属账号").length(), 2, msg="\{platform}")
    for o in one_of_two {
      let (l, r) = one_of_pair(t, o.1)
      let at = "\{platform} \{o.1}"
      assert_eq((l.rect.1, l.rect.2, l.rect.3), (r.rect.1, r.rect.2, r.rect.3), msg="\{at}: where and how big")
      assert_true(l.check == r.check, msg="\{at}: read out")
      t.leave()
      t.draw()
      assert_eq(drawn_within(t, l.rect), drawn_within(t, r.rect), msg="\{at}: at rest")
      assert_eq(words_within(t, l.rect), words_within(t, r.rect), msg="\{at}: its words")
      if platform == 0 {
        t.move_to(l.rect.0 + 30.0, l.rect.1 + l.rect.3 / 2.0)
        t.draw()
        let lit = drawn_within(t, l.rect)
        t.move_to(r.rect.0 + 30.0, r.rect.1 + r.rect.3 / 2.0)
        t.draw()
        assert_eq(lit, drawn_within(t, r.rect), msg="\{at}: pointed at")
        t.leave()
        t.draw()
      }
    }
  }
}

///|
test "one of a few as a node beside the old one: a press chooses the one pressed, the one chosen pressed again nothing" {
  for platform in [2, 0] {
    let told : Array[String] = []
    let old_now = @signals.signal("u1", same=fn(a, b) { a == b })
    let new_now = @signals.signal("u1", same=fn(a, b) { a == b })
    let t = one_of_tester(platform, one_of_two, old_now, new_now, told)
    let (l, r) = one_of_pair(t, "lin@work.example")
    t.tap(l.rect.0 + 30.0, l.rect.1 + l.rect.3 / 2.0)
    t.draw()
    t.tap(r.rect.0 + 30.0, r.rect.1 + r.rect.3 / 2.0)
    t.draw()
    assert_eq(told, ["old u2", "new u2"], msg="\{platform}")
    let (l, r) = one_of_pair(t, "lin@work.example")
    assert_true(l.check == Some(@view.Check::On) && r.check == Some(@view.Check::On), msg="\{platform}")
    // (the pointer off both: each drawn chosen, neither under it)
    t.leave()
    t.draw()
    assert_eq(drawn_within(t, l.rect), drawn_within(t, r.rect), msg="\{platform}: chosen")
    t.tap(l.rect.0 + 30.0, l.rect.1 + l.rect.3 / 2.0)
    t.draw()
    t.tap(r.rect.0 + 30.0, r.rect.1 + r.rect.3 / 2.0)
    t.draw()
    assert_eq(told.length(), 2, msg="\{platform}: \{Repr(told)}")
  }
}

///|
test "one of a few as a node beside the old one: Tab stops at the chosen one, ↓ and ↑ choose the next and the one before round from the ends, Space the one with the focus" {
  let told : Array[String] = []
  let old_now = @signals.signal("u2", same=fn(a, b) { a == b })
  let new_now = @signals.signal("u2", same=fn(a, b) { a == b })
  let t = one_of_tester(0, one_of_two, old_now, new_now, told)
  for side in ["old", "new"] {
    // Tab to its group: its chosen one
    t.key(@ui.key_tab)
    t.draw()
    let (l, r) = one_of_pair(t, "lin@work.example")
    let on = if side == "old" { l } else { r }
    assert_true(t.focused().map(fn(f) { f.rect == on.rect }).unwrap_or(false), msg="\{side}: \{t.focus_said()}")
    t.key(@ui.key_code_down)
    t.draw()
    t.key(@ui.key_code_up)
    t.draw()
    t.key(@ui.key_code_up)
    t.draw()
  }
  assert_eq(told, ["old u1", "old u2", "old u1", "new u1", "new u2", "new u1"])
  let (l, r) = one_of_pair(t, "lin@example.com")
  assert_true(l.check == Some(@view.Check::On) && r.check == Some(@view.Check::On))
}

///|
test "one of more than it lists, as a node: a select, as the old one's" {
  let many = Array::makei(6, fn(i) { ("u\{i}", "user\{i}@example.com") })
  let told : Array[String] = []
  let old_now = @signals.signal("u0", same=fn(a, b) { a == b })
  let new_now = @signals.signal("u0", same=fn(a, b) { a == b })
  let t = one_of_tester(0, many, old_now, new_now, told)
  assert_eq(t.all(Radio).length(), 0)
  let selects = t.all(Button, label="所属账号: user0@example.com")
  assert_eq(selects.length(), 2)
  assert_eq((selects[0].rect.1, selects[0].rect.2, selects[0].rect.3), (selects[1].rect.1, selects[1].rect.2, selects[1].rect.3))
}
