// Rule 1 of the spacing rules (gaps.mbt): rows that light up under the hand stand apart where one of them stays lit
// with no hand on it (the one chosen), not where the one lit is lit by the hand resting on it (a frame drawn with the
// pointer over a menu's row: a picture's hover), which lights any of them, one at a time.

///|
/// Three rows 44 high on a panel, flush, each lit under the hand; `chosen` (0..2, or -1) lit with no hand on it.
fn pointed_rows(chosen : Int) -> Tester {
  Tester::new(
    fn(c) {
      c.with_theme({ ..Theme::light(), lit_apart: 2.0, lit_reach: 6.0 }, fn() {
      c.box(w=Px(240.0), pad=6.0, bg=0xFFFFFFFFL, radius=24.0, fn() {
        for i in 0..<3 {
          let id = c.id("hand-row/\{i}")
          c.box(w=Fill(1.0), h=Px(44.0), radius=18.0, bg=if c.lit(id) || i == chosen { 0xEEEEEEFFL } else { 0L }, id~, fn() {
            c.text("row \{i}") |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      })
    },
    w=400.0,
    h=300.0,
  )
}

///|
fn rule1_count(t : Tester) -> Int {
  t.gap_faults().filter(fn(f) { f.has_prefix("rule 1") }).length()
}

///|
test "the spacing rules: rows flush under a resting pointer break no rule 1; one kept lit with no hand on it still does" {
  // the pointer resting on the first row (as a picture's hover leaves it)
  let pointed = pointed_rows(-1)
  pointed.frame()
  pointed.move_to(100.0, 24.0)
  pointed.frame()
  assert_eq(rule1_count(pointed), 0)
  // the first row chosen, no hand anywhere: its neighbours light up flush against it
  let kept = pointed_rows(0)
  kept.frame()
  assert_true(rule1_count(kept) > 0)
}

///|
/// A box `corner` round with three rows 44 high, 18 round, `reach` in from its sides, top and foot, each lit under
/// the hand; and a line of words beside them `words` in from its left where given.
fn reach_rows(corner : Double, reach : Double, words? : Double = -1.0) -> Tester {
  Tester::new(
    fn(c) {
      c.with_theme({ ..Theme::light(), lit_apart: 2.0, lit_reach: 6.0 }, fn() {
      c.box(w=Px(260.0), pad=reach, bg=0xFFFFFFFFL, radius=corner, fn() {
        if words >= 0.0 {
          c.box(w=Fill(1.0), pl=words - reach, fn() { c.text("heading") |> ignore }) |> ignore
        }
        for i in 0..<3 {
          let id = c.id("reach-row/\{i}")
          c.box(w=Fill(1.0), h=Px(44.0), radius=18.0, padx=16.0, bg=if c.lit(id) { 0xEEEEEEFFL } else { 0L }, id~, fn() {
            c.text("row \{i}") |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      })
    },
    w=400.0,
    h=300.0,
  )
}

///|
fn rule_count(t : Tester, rule : String) -> Int {
  t.gap_faults().filter(fn(f) { f.has_prefix(rule) }).length()
}

///|
test "the spacing rules 7 and 8: rows concentric with what holds them (24 round, 6 in; 26, 8), not swapped; words beside them on their words' line" {
  let t = reach_rows(24.0, 6.0)
  t.frame()
  assert_eq(rule_count(t, "rule 7"), 0)
  let t = reach_rows(26.0, 8.0)
  t.frame()
  assert_eq(rule_count(t, "rule 7"), 0)
  let t = reach_rows(24.0, 8.0)
  t.frame()
  assert_true(rule_count(t, "rule 7") > 0)
  let t = reach_rows(26.0, 6.0)
  t.frame()
  assert_true(rule_count(t, "rule 7") > 0)
  // words beside the rows on their words' line (8 + 16), and off it
  let t = reach_rows(26.0, 8.0, words=24.0)
  t.frame()
  assert_eq(rule_count(t, "rule 8"), 0)
  let t = reach_rows(26.0, 8.0, words=12.0)
  t.frame()
  assert_true(rule_count(t, "rule 8") > 0)
}

///|
fn tree_pointed_rows(chosen : Int, gap : Double) -> Tester {
  Tester::new(
    fn(c) {
      c.with_theme({ ..Theme::light(), lit_apart: 2.0, lit_reach: 6.0 }, fn() {  })
    },
    w=400.0,
    h=300.0,
    corners_held=false,
    tree=fn(root) {
      root.box(fn(panel) {
        panel
        .width(Is(Some(240.0)))
        .padding(Is((6.0, 6.0, 6.0, 6.0)))
        .gap(Is(gap))
        .ground(Is(0xFFFFFFFFL))
        .radius(Is(24.0))
        |> ignore
        for i in 0..<3 {
          panel.box(fn(row) {
            row
            .width(Is(Some(228.0)))
            .height(Is(Some(44.0)))
            .radius(Is(18.0))
            .presses(Is(true))
            .ground(By(fn() { if row.pointed() || row.pressed() || i == chosen { 0xEEEEEEFFL } else { 0L } }))
            .words(Is("row \{i}"))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
  )
}

///|
test "the spacing rules on @view.View tree: rows with a persistent active background require lit_apart >= 2; hover-only rows can sit 0 apart" {
  // no row kept lit at rest: 0px gap is valid
  let hover_only = tree_pointed_rows(-1, 0.0)
  assert_eq(rule1_count(hover_only), 0)
  // row 0 kept lit at rest with 0px gap: breaks rule 1
  let flush_active = tree_pointed_rows(0, 0.0)
  assert_true(rule1_count(flush_active) > 0)
  // row 0 kept lit at rest with 2px gap: passes rule 1
  let spaced_active = tree_pointed_rows(0, 2.0)
  assert_eq(rule1_count(spaced_active), 0)
}
