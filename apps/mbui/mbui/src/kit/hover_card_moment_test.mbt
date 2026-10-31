// A hover card's waits counted from when what each waits for came to be, as the hand's facts say it (an event by its
// own time, a frame by its clock), not from the frame that first saw it; each wait the trigger's this time it is drawn.

///|
/// How far before and after its moment a card is looked at.
let card_around_ms : Double = 20.0

///|
/// What the card's view is given: whether the trigger is drawn, how far down it stands, whether the card's inner
/// popover is open, whether the trigger and its card are a part kept (an island: kept while nothing it read changed).
struct CardView {
  shown : Ref[Bool]
  down : Ref[Double]
  inner : Ref[Bool]
  kept : Bool
  open : Ref[Bool]
}

///|
/// A Tester of a trigger (@ada) `down` below the top, its card holding a line and a button (Notes) that opens a popover
/// of its own (a button there, Inner notes).
fn card_tester(kept? : Bool = false) -> (@ui.Tester, CardView) {
  let v : CardView = { shown: Ref(true), down: Ref(0.0), inner: Ref(false), kept, open: Ref(false) }
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=40.0, fn() {
      c.box(style=@ui.style(h=Fixed(v.down.val)), fn() {  }) |> ignore
      let body = fn() {
        if v.shown.val {
          let r = button(c, "@ada", key="ada", variant=Ghost)
          v.open.val = hover_card(c, "card", r.id, fn() {
            c.text("Ada's card") |> ignore
            let b = button(c, "Notes", key="notes")
            if b.clicked {
              v.inner.val = true
            }
            popover(c, "inner", v.inner.val, b.id, side=Right, fn() {
              button(c, "Inner notes", key="inner-notes", variant=Ghost) |> ignore
            })
            |> ignore
          })
        }
      }
      if v.kept {
        c.kept_part(c.id("ada-row"), "ada-row", fn() { c.box(fn() { body() }) |> ignore }, own=true)
      } else {
        body()
      }
    })
    |> ignore
  })
  (t, v)
}

///|
/// The middle of what is labelled `label`.
fn middle_of(t : @ui.Tester, label : String) -> (Double, Double) raise {
  let (x, y, w, h) = t.get(@ui.Role::Button, label~).rect
  (x + w / 2.0, y + h / 2.0)
}

///|
/// Whether the card is open `before` and `after` around `at` + `ms` (a card's moment), as (ms after `at`, open).
fn around(t : @ui.Tester, v : CardView, at : Double, ms : Double) -> Array[(Double, Bool)] {
  let seen = []
  t.run_for(at + ms - card_around_ms - t.time())
  seen.push((t.time() - at, v.open.val))
  t.run_for(at + ms + card_around_ms - t.time())
  seen.push((t.time() - at, v.open.val))
  seen
}

///|
test "hover card: its trigger gone a frame and drawn again under the resting pointer waits from when it is drawn again, not from before" {
  let (t, v) = card_tester()
  let (x, y) = middle_of(t, "@ada")
  t.move(x, y)
  t.run_for(hover_card_open_ms / 2.0)
  v.shown.val = false
  t.draw()
  v.shown.val = true
  t.frame()
  // (drawn again: under the pointer from this frame)
  let again = t.time()
  let seen = around(t, v, again, hover_card_open_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [false, true], msg="(ms after drawn again, open): \{seen}")
}

///|
test "hover card: kept with its part while nothing it reads changes, its wait goes on and it opens on time" {
  let (t, v) = card_tester(kept=true)
  t.draw()
  // (by its words: a part kept says no semantics of its own to the Tester's tree)
  let (ax, ay, aw, ah) = t.rect_of("@ada").unwrap()
  let (x, y) = (ax + aw / 2.0, ay + ah / 2.0)
  let came = t.time()
  t.touch_at(1, x, y, came)
  t.advance(hover_card_open_ms / 3.0)
  t.frame()
  let seen = around(t, v, came, hover_card_open_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [false, true], msg="(ms after it came, open): \{seen}")
}

///|
test "hover card: a new run waits from its own pointer, nothing of the run before" {
  let (t, v) = card_tester()
  let (x, y) = middle_of(t, "@ada")
  t.move(x, y)
  t.run_for(hover_card_open_ms / 2.0)
  let (t, v2) = card_tester()
  ignore(v)
  let came = t.time()
  t.touch_at(1, x, y, came)
  t.frame()
  let seen = around(t, v2, came, hover_card_open_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [false, true], msg="(ms after it came, open): \{seen}")
}

///|
test "hover card: its trigger moved under the still pointer waits from the frame that drew it there, the next frame late" {
  let (t, v) = card_tester()
  let (x, y) = middle_of(t, "@ada")
  // (the pointer where the trigger will be once it is 240 further down: its card under it, clear of the pointer once
  // it is back)
  t.move(x, y + 240.0)
  t.run_for(hover_card_open_ms * 2.0)
  assert_false(v.open.val, msg="nothing under the pointer")
  v.down.val = 240.0
  t.frame()
  // (drawn under it as this frame ended)
  let drawn = t.time()
  t.advance(hover_card_open_ms * 2.0 / 3.0)
  t.frame()
  let seen = around(t, v, drawn, hover_card_open_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [false, true], msg="(ms after it was drawn under the pointer, open): \{seen}")
  // moved from under it again: closes from the frame that drew it away
  t.run_for(hover_card_open_ms)
  v.down.val = 0.0
  t.frame()
  let away = t.time()
  t.advance(hover_card_close_ms * 2.0 / 3.0)
  t.frame()
  let seen = around(t, v, away, hover_card_close_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [true, false], msg="(ms after it was drawn away, open): \{seen}")
}

///|
test "hover card: kept open while the pointer is in a popover opened from it; closes hover_close_ms after it leaves that, the frame late" {
  let (t, v) = card_tester()
  let (x, y) = middle_of(t, "@ada")
  t.move(x, y)
  t.run_for(hover_card_open_ms * 2.0)
  assert_true(v.open.val, msg="opened")
  let (nx, ny) = middle_of(t, "Notes")
  t.move(nx, ny)
  t.click(@ui.Role::Button, label="Notes")
  t.run_for(hover_card_open_ms)
  let (ix, iy) = middle_of(t, "Inner notes")
  t.move(ix, iy)
  t.run_for(hover_card_close_ms * 2.0)
  assert_true(v.open.val, msg="kept by the pointer in its popover")
  let left = t.time()
  t.touch_at(1, 900.0, 900.0, left)
  t.advance(hover_card_close_ms * 2.0 / 3.0)
  t.frame()
  let seen = around(t, v, left, hover_card_close_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [true, false], msg="(ms after it left, open): \{seen}")
}

///|
test "hover card: kept open while the keyboard's focus is in it; closes hover_close_ms after Tab takes the focus out of it, the frame late" {
  let (t, v) = card_tester()
  let (x, y) = middle_of(t, "@ada")
  t.move(x, y)
  t.run_for(hover_card_open_ms * 2.0)
  assert_true(v.open.val, msg="opened")
  let mut on = false
  for _ in 0..<12 {
    t.tab()
    if t.focused() is Some(f) && f.label == "Notes" {
      on = true
      break
    }
  }
  assert_true(on, msg="Tab to Notes: \{t.focused()}")
  t.move(900.0, 900.0)
  t.run_for(hover_card_close_ms * 2.0)
  assert_true(v.open.val, msg="kept by the focus in it")
  // Tab out as the host hands it on, the frame late: its close from the key's moment
  let moved = t.time()
  t.key_told(@ui.key_tab, 0, moved)
  t.advance(hover_card_close_ms * 2.0 / 3.0)
  t.frame()
  assert_true(t.focused().map(fn(f) { f.label }) != Some("Notes"), msg="the focus out of it: \{t.focused()}")
  let seen = around(t, v, moved, hover_card_close_ms)
  assert_eq(seen.map(fn(s) { s.1 }), [true, false], msg="(ms after the focus moved, open): \{seen}")
}
