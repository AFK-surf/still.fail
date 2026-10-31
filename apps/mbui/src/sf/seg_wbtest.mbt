// The segmented choices (seg.mbt's Seg, the narrow pages'; parts.mbt's segmented, the wide pages'): what they do short
// of room.

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
    let (x, _, w, _) = t.get(@ui.Role::Radio, label=words).rect
    assert_true(x >= upto - 0.5, msg=words)
    upto = x + w
  }
  assert_true(upto <= 324.5)
  // the short ones more than their words and 8 either side, the long ones that alone
  for words in parts {
    let (_, _, option, _) = t.get(@ui.Role::Radio, label=words).rect
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
test "a filling Seg short of room at a larger size of words: their words smaller alike, no smaller than at the system's own size, each whole on one line, all in its track" {
  let parts = ["Overview", "Settings", "Software & device"]
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { seg(c, "parts", parts, 0, fill=true, height=34.0) |> ignore }) |> ignore
      })
    },
    w=600.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  // their words as wide as they are drawn with room for them, at the system's own size and at 1.3 of it
  let drawn = fn() { parts.map(fn(words) { t.rect_of(words).unwrap().2 }) }
  let own = drawn()
  t.set_font_scale(1.3)
  t.draw()
  let larger = drawn()
  let sum = fn(a : Array[Double]) { a.fold(init=0.0, fn(s, w) { s + w }) }
  // a page between the two (16 in from its sides, the track 2 in): room for them at the least either side at the
  // system's own size, not at 1.3
  let w = 36.0 + 6.0 * seg_least + (sum(own) + sum(larger)) / 2.0
  t.resize(w, 200.0)
  t.draw()
  let now = drawn()
  let mut upto = 17.5
  for i, words in parts {
    assert_eq(t.lines_of(words), [words], msg=words)
    let (x, _, ow, _) = t.get(@ui.Role::Radio, label=words).rect
    assert_true(x >= upto - 0.5, msg=words)
    upto = x + ow
    let (wx, _, ww, _) = t.rect_of(words).unwrap()
    assert_true(wx >= x && wx + ww <= x + ow + 0.5, msg=words)
    // (smaller alike, not smaller than at the system's own size)
    assert_true(now[i] < larger[i] - 0.5 && now[i] >= own[i] - 0.5, msg="\{words} \{own[i]} \{now[i]} \{larger[i]}")
    assert_true((now[i] / larger[i] - now[0] / larger[0]).abs() < 0.02, msg=words)
  }
  assert_true(upto <= w - 17.5)
  assert_eq(t.squeeze_faults(), [])
  // given the room again: their words as large as the system says
  t.resize(600.0, 200.0)
  t.draw()
  assert_eq(drawn(), larger)
}

///|
test "a filling Seg whose options do not fit side by side even at the system's own size: the chosen one and a chevron, as wide as its room; a sheet of them all, one picked chosen; given the room, side by side again" {
  let parts = ["Android", "Desktop", "Web", "Station", "Cloud"]
  let chosen = Ref::new(4)
  presenters_reset()
  // 260 wide: 224 in the track for options whose words with the least either side need 243
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() {
          chosen.val = seg(c, "parts", parts, chosen.val, fill=true, height=34.0)
        })
        |> ignore
        presented(c)
      })
    },
    w=260.0,
    h=700.0,
    platform=2,
  )
  t.draw()
  assert_eq(t.all(@ui.Role::Radio).length(), 0)
  let (x, _, w, h) = t.get(@ui.Role::Button, label="Cloud").rect
  assert_true((x - 16.0).abs() < 0.5 && (x + w - 244.0).abs() < 0.5 && h == 34.0, msg="\{x} \{w} \{h}")
  assert_eq(t.lines_of("Cloud"), ["Cloud"])
  assert_true(t.find("Station") is None)
  assert_eq(t.squeeze_faults(), [])
  open_choice(t, "Cloud")
  assert_eq(presented_how, [AsSheet])
  t.tap_text("Station")
  assert_true(!presenting())
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_eq(chosen.val, 3)
  assert_true(t.query(@ui.Role::Button, label="Station") is Some(_))
  // (given the room: its options side by side, the one picked chosen)
  t.resize(600.0, 700.0)
  t.draw()
  assert_eq(t.all(@ui.Role::Radio).length(), 5)
  assert_eq(t.get(@ui.Role::Radio, label="Station").check, Some(@ui.Check::On))
}

///|
/// The thumb on the dark theme's track on every ground it may lie on: seen off it (1.25 to 1, docs/ui-panels.md 对比度)
/// and the chosen words read on it. (The light one is white with a shadow round it, the track grey: what a shadow does
/// a ratio does not say.) The canvas and an opaque grey were 1.02 and 1.05 to 1 off it (2026-10-27).
test "the dark theme's segmented thumb seen off its track on every ground, its words read on it" {
  let lifted = @ui.Theme::narrow_dark().lifted
  let wrong : Array[String] = []
  for p in [("dark", dark_palette), ("web dark", web_dark)] {
    let (name, pal) = p
    let grounds = [
      ("page", pal.bg),
      ("canvas", pal.canvas),
      ("raised", pal.raised),
      ("sidebar", pal.sidebar),
      ("list", pal.list),
      ("selected", pal.selected),
      ("paper", pal.paper),
      ("card", pal.card),
      ("card2", pal.card2),
      ("chip", pal.chip),
    ]
    for g in grounds {
      let track = over(g.1, alpha(pal.text, 0.06))
      let thumb = over(track, lifted)
      let seen = @ui.contrast_ratio(thumb, track)
      let read = @ui.contrast_ratio(pal.text, thumb)
      if seen < 1.25 {
        wrong.push("\{name}: the thumb on a track on the \{g.0} \{seen}:1, under 1.25")
      }
      if read < 4.5 {
        wrong.push("\{name}: the chosen words on the thumb on the \{g.0} \{read}:1, under 4.5")
      }
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}

///|
test "segmented whose options do not fit side by side even at the system's own size: the chosen one and a chevron; a pick of them all, one picked chosen" {
  let parts = ["Overview", "Software and devices", "Settings"]
  let chosen = Ref::new(0)
  presenters_reset()
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { chosen.val = segmented(c, "parts", parts, chosen.val) }) |> ignore
        presented(c)
      })
    },
    w=220.0,
    h=700.0,
  )
  t.draw()
  assert_eq(t.all(@ui.Role::Radio).length(), 0)
  let (x, _, w, _) = t.get(@ui.Role::Button, label="Overview").rect
  assert_true((x - 16.0).abs() < 0.5 && (x + w - 204.0).abs() < 0.5, msg="\{x} \{w}")
  assert_eq(t.lines_of("Overview"), ["Overview"])
  assert_eq(t.squeeze_faults(), [])
  // (a window 220 wide is Small: the pick a sheet, with either hand: docs/architecture.md, rule 3)
  open_choice(t, "Overview")
  assert_eq(presented_how, [AsSheet])
  t.tap_text("Settings")
  assert_true(!presenting())
  t.run_for(@kit.presence_out_ms)
  assert_eq(chosen.val, 2)
  assert_true(t.query(@ui.Role::Button, label="Settings") is Some(_))
}

///|
test "segmented short of room for its equal columns: the longer as wide as its words with their sides, the other the rest; given the room again, equal columns" {
  let parts = ["Settings", "Software and devices"]
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(style=seg_test_room, fn() { segmented(c, "parts", parts, 1) |> ignore }) |> ignore
      })
    },
    w=320.0,
    h=200.0,
  )
  t.draw()
  let widths = fn() raise { option_rects(t, parts).map(fn(r) { r.2 }) }
  // (the longer's words with 12 either side, in the theme's size of words at this width)
  let need = fn() { t.rect_of("Software and devices").unwrap().2 + 2.0 * segmented_in }
  for words in parts {
    assert_eq(t.lines_of(words), [words], msg=words)
  }
  let short = widths()
  assert_true((short[1] - need()).abs() < 1.0, msg="\{short} \{need()}")
  assert_true(short[0] < short[1])
  let (x0, _, _, _) = t.get(@ui.Role::Radio, label="Settings").rect
  let (x1, _, w1, _) = t.get(@ui.Role::Radio, label="Software and devices").rect
  assert_true(x0 >= 16.0 && x1 + w1 <= 304.5)
  assert_eq(t.squeeze_faults(), [])
  t.resize(600.0, 200.0)
  t.draw()
  let wide = widths()
  assert_true((wide[0] - wide[1]).abs() < 0.5 && (wide[1] - need()).abs() < 1.0, msg="\{wide} \{need()}")
  t.resize(320.0, 200.0)
  t.draw()
  assert_eq(widths(), short)
}

///|
test "option_widths: alike, none narrower than its words and sides; then their sides narrower; then their words smaller alike, to the least it may; then not side by side" {
  // words 40, 100 and 60 wide, 12 either side, 8 at the least
  let at = fn(room : Double, smallest : Double) { option_widths([40.0, 100.0, 60.0], room, 12.0, 8.0, smallest) }
  assert_eq(at(450.0, 1.0), ([150.0, 150.0, 150.0], Whole))
  // (the longer's 124 its own, the others sharing the rest)
  assert_eq(at(300.0, 1.0), ([88.0, 124.0, 88.0], Whole))
  // (their sides 10)
  assert_eq(at(260.0, 1.0), ([60.0, 120.0, 80.0], Whole))
  // (their words at 3/4, 8 either side: as far as they may go, to 0.7 of their size)
  assert_eq(at(198.0, 0.7), ([46.0, 91.0, 61.0], Smaller(0.75)))
  // (not that far: not side by side)
  assert_eq(at(198.0, 0.8), ([], Menu))
  assert_eq(at(248.0, 1.0), ([56.0, 116.0, 76.0], Whole))
  assert_eq(at(247.0, 1.0).1, Menu)
}

///|
/// The choice drawn as `words` pressed, and its pick come in: a sheet risen, else the web's in.
fn open_choice(t : @ui.Tester, words : String) -> Unit raise {
  t.click(@ui.Role::Button, label=words)
  if presented_how == [AsSheet] {
    t.run_for(@kit.sheet_rest("sf-present") - t.time())
  } else {
    t.run_for(@kit.presence_in_ms)
  }
}

///|
/// Where each option is (x, y, w, h), as the semantics tree has them.
fn option_rects(t : @ui.Tester, labels : Array[String]) -> Array[(Double, Double, Double, Double)] raise {
  let out = []
  for words in labels {
    out.push(t.get(@ui.Role::Radio, label=words).rect)
  }
  out
}

///|
/// Where the Seg is: a phone's page, 16 in from its sides.
// kept across runs: a value (no field of it changes)
let seg_test_room : @ui.Style = @ui.css("w=Full px=S4")
