// What fades out towards a cut inside a page's list (a field's words past its edge) moves with what the list holds as it
// is scrolled, on a host keeping groups and drawing them out (groups.h, ride_put): where the words fade is where the
// field is drawn, not where it was laid out. Till 2026-11-13 the list moved the words and left where they fade behind,
// so a field's words scrolled past it were faded out wholly: the settings' search placeholder gone or cut in half.

///|
/// A field of two lines holding five in row 1 of a page's list of ten rows 30 tall in a window 100 tall, the list
/// scrolled `by`: each of its glyphs drawn (what the host is handed, drawn out) that fades towards the field's top or
/// foot, how far that is from the same edge of its clip (the field's box, moved with it).
fn list_fade_offsets(by : Double) -> Array[Double] {
  let f = Field::new(text="1\n2\n3\n4\n5")
  let t = Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  t.set_groups(true)
  t.set_rows_on_pixels(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      col.scrolls_window(@view.Scroll::list(), fn() { [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] }, est=30.0, follows=fn() {
        false
      }, fn(b, k) {
        if k == 1 {
          field(b, f, label="名字", max_lines=2) |> ignore
        } else {
          b.box(fn(l) { l.words(Is("行 \{k}")).height(Is(Some(30.0))) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  if by != 0.0 {
    t.wheel(150.0, 50.0, by)
    t.draw()
  }
  let (a, n, _) = t.presented()
  let out = []
  for k in 0..<n {
    let b = k * inst_size
    if a[b + 5] == 1.0 && a[b + 53] > 0.0 {
      out.push((a[b + 52] - a[b + 17]).abs())
    }
    if a[b + 5] == 1.0 && a[b + 55] > 0.0 {
      out.push((a[b + 54] - a[b + 19]).abs())
    }
  }
  out
}

///|
test "a field's words fading out at its edge, in a page's list scrolled: they fade where the field is drawn" {
  for by in [0.0, 12.0, 25.0] {
    let offs = list_fade_offsets(by)
    assert_true(offs.length() > 0, msg="scrolled \{by}: no glyph fading at the field's edges")
    assert_true(offs.iter().all(fn(d) { d < 0.5 }), msg="scrolled \{by}: \{Repr(offs)}")
  }
}

///|
test "a field of one line in a box lower than its line: laid out again, its words stay where they were" {
  let f = Field::new(text="高")
  let t = Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      field(col, f, label="名字", max_lines=1, line=30.0).height(Is(Some(20.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  let fades = fn() {
    let (a, n, _) = t.presented()
    let out = []
    for k in 0..<n {
      let b = k * inst_size
      if a[b + 5] == 1.0 {
        out.push((a[b + 1], a[b + 53], a[b + 55]))
      }
    }
    out
  }
  let first = fades()
  t.run_for(caret_blink_ms)
  assert_eq(t.idle_said(), None)
  assert_true(fades() == first, msg="\{Repr(first)} then \{Repr(fades())}")
}
