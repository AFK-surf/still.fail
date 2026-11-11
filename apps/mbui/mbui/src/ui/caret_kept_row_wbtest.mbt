// A field of the window's tree in a row of a page's list, on a host keeping groups (every platform's but the web's),
// painted as a device paints (no frame built whole again after it): its caret blinks as anywhere, drawn among what the
// host is handed on each blink's shown half and not on its hidden half, a frame painted at each turn. The list drawn
// whole as one (ListRiding) was drawn again from what it kept while it held the field, the field's paint not run: no
// caret where it was focused after its row was drawn, one that never blinked where it was drawn shown, no frame asked
// for its next turn (till 2026-11-12).

///|
/// The field in row 1 of a page's list of three, focused from the start (`first`) or once the list was drawn: for each
/// of `turns` of its caret's blink from the focus, whether it is drawn a hair after the turn, and whether a frame was
/// painted at the turn, the wake its last frame asked for (not the hair's, which a test's run draws whatever is asked).
fn caret_kept_turns(first : Bool, turns : Int) -> String {
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  t.set_groups(true)
  t.set_rows_on_pixels(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      col.scrolls_window(@view.Scroll::list(), fn() { [0, 1, 2] }, est=30.0, follows=fn() { false }, fn(b, k) {
        if k == 1 {
          field(b, f, label="名字", max_lines=1) |> ignore
        } else {
          b.box(fn(l) { l.words(Is("行 \{k}")).height(Is(Some(30.0))) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  if first {
    f.focus()
  }
  t.draw()
  if !first {
    t.run_for(caret_blink_ms + 100.0)
    f.focus()
    t.draw()
  }
  let at = t.fake.time
  let p = caret_blink()
  let painted : Array[Double] = []
  t.each_frame(Some(fn() { painted.push(t.time()) }))
  let seen = ["\{carets_drawn().length()}"]
  for k in 1..=turns {
    let turn = at + k.to_double() * p
    t.run_for(turn + 1.0 - t.fake.time)
    let drawn = painted.iter().any(fn(m) { m >= turn - 1.0e-6 && m < turn + 0.5 })
    seen.push("\{carets_drawn().length()}\{if drawn { "" } else { " (no frame)" }}")
  }
  t.each_frame(None)
  seen.join(" ")
}

///|
test "a field in a page's list's row, focused once its row was drawn, its list drawn whole as one: its caret blinks" {
  inspect(caret_kept_turns(false, 4), content="1 0 1 0 1")
}

///|
test "a field in a page's list's row, focused from the start, its list drawn whole as one: its caret blinks" {
  inspect(caret_kept_turns(true, 4), content="1 0 1 0 1")
}
