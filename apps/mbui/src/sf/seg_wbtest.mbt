// The segmented choice as the web's narrow pages have it (seg.mbt): what it does short of room.

///|
test "a filling Seg short of room for equal shares: each option's words whole, the longer ones as wide as they need, the rest sharing what is left, all in its track" {
  let parts = ["Android", "Desktop", "Web", "Station", "Cloud"]
  // a phone 340 wide, the changelog's tabs 16 in from its sides (about.mbt cl_narrow_tabs): 61 a part, less than the
  // longer words need
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { seg(c, "parts", parts, 0, fill=true, height=34.0) |> ignore }) |> ignore
      })
    },
    w=340.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  let mut upto = 16.0
  for words in parts {
    assert_eq(t.lines_of(words), [words], msg=words)
    let (x, _, w, _) = t.get(@ui.Radio, label=words).rect
    assert_true(x >= upto - 0.5, msg=words)
    upto = x + w
  }
  assert_true(upto <= 324.5)
  // the short ones more than their words and 8 either side, the long ones that alone
  for words in parts {
    let (_, _, option, _) = t.get(@ui.Radio, label=words).rect
    let (_, _, need, _) = t.rect_of(words).unwrap()
    if words == "Web" || words == "Cloud" {
      assert_true(option > need + 16.5, msg=words)
    } else {
      assert_true((option - need - 16.0).abs() < 0.5, msg=words)
    }
  }
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a filling Seg with less room than its options' words: they scroll sideways in its track, whole, the chosen one in view" {
  let parts = ["Android", "Desktop", "Web", "Station", "Cloud"]
  let chosen = Ref::new(4)
  // 260 wide: 224 in the track for options needing 283
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() {
          chosen.val = seg(c, "parts", parts, chosen.val, fill=true, height=34.0)
        })
        |> ignore
      })
    },
    w=260.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  for words in parts {
    assert_eq(t.lines_of(words), [words], msg=words)
  }
  // the chosen one, the last, whole in the track (16 in, 2 inside it); the first scrolled out at its start
  let (x, _, w, _) = t.get(@ui.Radio, label="Cloud").rect
  assert_true(x >= 17.5 && x + w <= 242.5)
  assert_true(t.get(@ui.Radio, label="Android").rect.0 < 17.5)
  assert_eq(t.squeeze_faults(), [])
  // the first, a sliver of it showing, tapped there: chosen, brought whole into view
  let (_, y, _, h) = t.get(@ui.Radio, label="Android").rect
  t.tap(21.0, y + h / 2.0)
  t.draw()
  assert_eq(chosen.val, 0)
  assert_true((t.get(@ui.Radio, label="Android").rect.0 - 18.0).abs() < 0.5)
}

///|
/// Where the Seg is: a phone's page, 16 in from its sides.
// kept across runs: a value (no field of it changes)
let seg_test_room : @ui.Style = @ui.css("w=Full px=S4")
