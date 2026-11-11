// The row/heading alignment check measures a list card, not a page or a side panel that happens to hold rows.

///|
test "row alignment catches words too far out on a list card" {
  let t = @ui.Tester::new(fn(c) {
    c.with_theme({ ..@ui.Theme::light(), lit_reach: 6.0 }, fn() {
      // (a card of the ladder's, 26, its rows concentric with it 8 in, 18 round)
      c.box(w=Px(320.0), pad=8.0, bg=0xEEEEEEFFL, radius=26.0, fn() {
        let id = c.id("row")
        ignore(c.lit(id))
        c.box(w=Fill(1.0), h=Px(44.0), padx=10.0, radius=18.0, id~, fn() {
          c.text("Row words") |> ignore
        }) |> ignore
        c.text("Heading too far out") |> ignore
      }) |> ignore
    })
  }, w=400.0, h=300.0, corners_held=false)
  t.draw()
  let faults = t.gap_faults().filter(fn(f) { f.contains("rule 8:") })
  assert_true(faults.length() > 0, msg="\{Repr(faults)}")
}

///|
test "row alignment does not mistake a page or side panel for a list card" {
  let found : Array[String] = []
  for (mode, window) in [("drive", corner_windows[0]), ("history", corner_windows[5]), ("reader-contents", corner_windows[1]), ("place-stations", corner_windows[2]), ("place-stations", corner_windows[3])] {
    let t = screen_in(mode, window, "zh")
    let faults = t.gap_faults().filter(fn(f) { f.contains("rule 8:") })
    for fault in faults {
      found.push("\{mode}: \{fault}")
    }
  }
  assert_true(found.is_empty(), msg=found.join("\n"))
}
