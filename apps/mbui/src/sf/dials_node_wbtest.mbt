// An allowance's dials on a narrow page (quota_node.mbt dials_node with `lines`): two a line, more going on in lines,
// a name or a note going on under itself where it is longer than its dial: nothing cut, nothing past its card.

///|
/// A Claude subscription's windows as its profile's page says them (station_cards.mbt quota_dials_of), named and
/// refilling in the words the core says: the account's, then `own` of its models' own weeks.
fn allowance_dials(own : Int) -> Array[Dial] {
  let dial = fn(left : Int, label : String, note : String) -> Dial {
    { number: left.to_string(), unit: "%", fill: left, level: "ok", label, note, label_short: "", note_short: "" }
  }
  let dials = [dial(62, "5 小时", "3 小时 5 分钟后刷新"), dial(19, "每周", "2 天 4 小时后刷新")]
  for m in [("Fable", 46), ("Opus", 8), ("Sonnet", 100)].iter().take(own) {
    dials.push(dial(m.1, "每周 · " + m.0, "2 天 4 小时后刷新"))
  }
  dials
}

///|
/// The dials in a card of a phone's page `w` wide, the system's words at `scale`.
fn dials_tester(dials : Array[Dial], w : Double, scale? : Double = 1.0) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w~, h=900.0, platform=2)
  t.set_font_scale(scale)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      page_block(b, fn(room) {
        group_node(room, fn(g) { block_node(g, fn(bl) { dials_node(bl, fn() { dials }, lines=2) }) })
      })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// How the dials shown stand, by their names: how many lines they are on, having held each to the window and to its
/// words drawn whole (none cut to an ellipsis).
fn dial_lines(t : @ui.Tester, dials : Array[Dial], w : Double, at : String) -> Int {
  let shown = t.words().filter(fn(x) { x.5 > 0.5 })
  let names = dials.map(fn(d) {
    match shown.filter(fn(x) { x.0 == d.label }) {
      [x] => x
      found => @halt.saying("\{at}: \{d.label}: \{Repr(found)} in \{Repr(shown.map(fn(x) { x.0 }))}")
    }
  })
  let drawn = t.text_runs().map(fn(r) { r.text })
  guard drawn.iter().all(fn(s) { !s.has_suffix("…") }) else { @halt.saying("\{at}: cut: \{Repr(drawn)}") }
  guard shown.iter().all(fn(x) { x.1 >= 0.0 && x.1 + x.3 <= w + 0.01 }) else { @halt.saying("\{at}: past the window: \{Repr(shown)}") }
  let tops : Array[Double] = []
  for n in names {
    if !tops.contains(n.2) {
      tops.push(n.2)
    }
  }
  // (a line's dials from the first column on, each column where the line before has it)
  for i, n in names {
    let per = (names.length() + tops.length() - 1) / tops.length()
    if i >= per {
      guard (n.1 - names[i - per].1).abs() < 0.01 else { @halt.saying("\{at}: \{n.0} not under \{names[i - per].0}: \{Repr(names)}") }
    }
  }
  tops.length()
}

///|
test "an allowance's dials, narrow: two a line, the rest under them in their columns, a name or a note never cut" {
  // (three in a line: 每周 · Fable was cut to 每周 · Fa… and 2 天 4 小时后刷新 to 2 天 4 小时后刷… at a third of a phone's
  // card; five ran past the card's end)
  for scale in [1.0, 1.3, 2.0] {
    for w in [300.0, 320.0, 360.0, 390.0, 430.0] {
      for own in [0, 1, 2, 3] {
        let dials = allowance_dials(own)
        assert_eq(dial_lines(dials_tester(dials, w, scale~), dials, w, "\{own} own, \{w} at \{scale}"), (dials.length() + 1) / 2)
      }
    }
  }
  // an account with no 5 小时 window: its week and its model's own, a line
  let all = allowance_dials(1)
  let two = [all[1], all[2]]
  assert_eq(dial_lines(dials_tester(two, 390.0), two, 390.0, "week and Fable"), 1)
}
