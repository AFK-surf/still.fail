// What is built in a page's bones (Ctx::bones) is drawn as them: its words a bar on each line, no glyph; its grounds
// as they are but one that says something by its colour; nothing in it pressed, found or read out; a list's rows,
// built as it is laid out, as well.

///|
/// The bones' colour in these tests.
let bones_ink : Int64 = 0x999999FFL

///|
test "words in bones: a bar on each of their lines, as long as the line, no glyph, not found" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(200.0), fn() {
        c.bones(bones_ink, fn() { c.text("骨架里的字", size=16.0, line=24.0) |> ignore })
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  t.frame()
  assert_eq(t.drawn_glyphs().length(), 0)
  assert_eq(t.locate("骨架里的字").length(), 0)
  let bars = t.drawn_rects().filter(fn(r) { r.4 == bones_ink })
  assert_eq(bars.length(), 1)
  let (_, y, w, h, _) = bars[0]
  // (the line's words five of the Tester's Chinese letters, each as wide as their size; the bar 0.8 of their size, in
  // the line's middle)
  assert_eq(w, 80.0)
  assert_eq(h, 13.0)
  assert_eq(y, (24.0 - 13.0) / 2.0)
}

///|
test "a ground with words in bones over it, laid beside them as a card's row lays its ground: what it holds carries it, as words would" {
  // (still.fail's group rows: the card's ground a layer of its own, the row's words beside it in the same box; white
  // on a page's #f5f3ef, 1.11 to 1, seen by what is in it)
  for top in [0.0, 24.0, 24.4] {
    let t = Tester::new(
      fn(c) {
        c.box(w=Px(300.0), h=Px(200.0), bg=0xF5F3EFFFL, fn() {
          c.box(h=Px(top), fn() {  }) |> ignore
          c.bones(bones_ink, fn() {
            c.box(w=Px(200.0), h=Px(46.0), fn() {
              c.layer(fn() { c.box(w=Px(200.0), h=Px(46.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore }) |> ignore
              c.text("骨架里的字", size=16.0, line=24.0) |> ignore
            })
            |> ignore
          })
        })
        |> ignore
      },
      w=300.0,
      h=200.0,
    )
    assert_eq(t.contrast_faults(), [], msg="\{top}")
  }
}

///|
test "a box in bones takes no press, says nothing to a screen reader; a coloured ground in their colour, a grey one its own" {
  let pressed = Ref(false)
  let t = Tester::new(
    fn(c) {
      c.bones(bones_ink, fn() {
        let id = c.id("press")
        if c.clicked(id) {
          pressed.val = true
        }
        let b = c.box(id~, w=Px(80.0), h=Px(40.0), bg=0xE5532DFFL, fn() { c.text("按我") |> ignore })
        c.semantics(b, Button, id~, label="按我")
        c.box(w=Px(80.0), h=Px(40.0), bg=0xF6F6F7FFL, fn() {  }) |> ignore
      })
    },
    w=300.0,
    h=200.0,
  )
  t.frame()
  t.tap(40.0, 20.0)
  assert_true(!pressed.val)
  assert_true(t.semantics().iter().all(fn(s) { s.hidden || s.label != "按我" }))
  let colours = t.drawn_rects().map(fn(r) { r.4 })
  assert_true(colours.contains(bones_ink))
  assert_true(!colours.contains(0xE5532DFFL))
  assert_true(colours.contains(0xF6F6F7FFL))
}

///|
test "a list's rows in bones, built as it is laid out, are bones too" {
  let t = Tester::new(
    fn(c) {
      c.bones(bones_ink, fn() {
        c.list("bones-list", 3, 30.0, fn(i) { c.text("第" + i.to_string() + "行", size=16.0, line=24.0) |> ignore }) |> ignore
      })
    },
    w=300.0,
    h=200.0,
  )
  t.frame()
  assert_eq(t.drawn_glyphs().length(), 0)
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == bones_ink }).length(), 3)
}
