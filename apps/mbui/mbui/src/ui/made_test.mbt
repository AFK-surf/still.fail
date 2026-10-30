///|
test "made: a node is filled once, and anew only as what its fill read changes; the others kept" {
  let word = @signals.signal("one")
  let fills = [0, 0]
  let t = Tester::new(
    fn(c) {
      c.made("view", fn() {
        made_box(fn(c) { c.box(pad=8.0, fn() {  }) |> ignore }, kids=[
          made_box(fn(c) {
            fills[0] = fills[0] + 1
            c.text(word.get()) |> ignore
          }),
          made_box(fn(c) {
            fills[1] = fills[1] + 1
            c.text("still") |> ignore
          }),
        ])
      })
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  assert_true(t.find("one") is Some(_))
  assert_true(t.find("still") is Some(_))
  let (a, b) = (fills[0], fills[1])
  t.frame()
  t.frame()
  assert_eq(fills[1], b)
  word.set("two")
  t.draw()
  assert_true(t.find("two") is Some(_))
  assert_true(t.find("one") is None)
  assert_true(fills[0] > a)
  assert_eq(fills[1], b)
}

///|
test "made: what each item makes is made as it comes, kept while it stays, let go as it goes" {
  let items = @signals.signal([1, 2, 3], same=fn(a, b) { a == b })
  let made = Ref(0)
  let t = Tester::new(
    fn(c) {
      c.made("list", fn() {
        made_holding(
          fn(c) { c.box(gap=4.0, fn() {  }) |> ignore },
          made_each(fn() { items.get() }, fn(i) { i }, fn(it) {
            made.val = made.val + 1
            made_box(fn(c) { c.text("item \{it.get()}") |> ignore })
          }),
        )
      })
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  assert_eq(made.val, 3)
  assert_true(t.find("item 2") is Some(_))
  items.set([1, 3, 4])
  t.draw()
  assert_eq(made.val, 4)
  assert_true(t.find("item 2") is None)
  assert_true(t.find("item 4") is Some(_))
  // (in their order: 1 above 3 above 4)
  let (_, y1) = t.find("item 1").unwrap()
  let (_, y3) = t.find("item 3").unwrap()
  let (_, y4) = t.find("item 4").unwrap()
  assert_true(y1 < y3 && y3 < y4)
}

///|
test "made: a press on a node does what it said as it is let go, and what reads what that set is filled anew" {
  let count = @signals.signal(0)
  let t = Tester::new(
    fn(c) {
      c.made("button", fn() {
        made_box(fn(c) {
          let id = c.id("tap me")
          c.box(id~, pad=10.0, fn() {  }) |> ignore
        }, kids=[made_box(fn(c) { c.text("pressed \{count.get()}") |> ignore })]).on_press(fn() {
          count.set(count.get() + 1)
        })
      })
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  t.tap_text("pressed 0")
  t.draw()
  assert_eq(count.get(), 1)
  assert_true(t.find("pressed 1") is Some(_))
}

///|
test "made: what shows while a condition holds comes and goes with it" {
  let open = @signals.signal(false)
  let t = Tester::new(
    fn(c) {
      c.made("shown", fn() {
        made_holding(
          fn(c) { c.box(fn() {  }) |> ignore },
          made_show(fn() { open.get() }, fn() { made_box(fn(c) { c.text("now you see it") |> ignore }) }),
        )
      })
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  assert_true(t.find("now you see it") is None)
  open.set(true)
  t.draw()
  assert_true(t.find("now you see it") is Some(_))
  open.set(false)
  t.draw()
  assert_true(t.find("now you see it") is None)
}
