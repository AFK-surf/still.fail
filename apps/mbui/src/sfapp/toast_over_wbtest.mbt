// A toast said while the old frame's modal sheet is up (what is shared over another app, in the presenters' sheet): the
// toast over it, as the old frame's toast (an overlay of its own, after the presenters') was: drawn over the sheet, its
// action pressed where it is drawn and done once, a press beside it the sheet's; and read out, not hidden by the sheet.

///|
/// What is shared over another app (the fixture's share-in), its sheet risen, 390 by 844 to touch, a toast with its
/// action (撤销, counted in `runs`) said and come in.
fn over_sheet(runs : Ref[Int]) -> @ui.Tester {
  new_run()
  let src = fixture("share-in")
  open_drive_fixture("share-in")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  nav_rested(t)
  t.post(@hostapi.system_channel, "{\"over\":true}")
  t.frame()
  sheet_rested(t, "sf-present")
  @sfbase.toast_later(over_words, action="撤销", run=fn() { runs.val = runs.val + 1 })
  t.frame()
  t.run_for(@kit.presence_in_ms)
  t
}

///|
let over_words : String = "已归档「夜里的构建又失败了」"

///|
/// What is read out as `role` labelled `label`, hidden or not.
fn said_any(t : @ui.Tester, role : @ui.Role, label : String) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { s.role == role && s.label == label })
}

///|
/// How many drawn rects over rect `r` (where the toast is) are drawn after the toast's ground (the smallest rect drawn
/// holding its words) and are not in `r`: none where it is drawn over all else; -1 where none holds its words.
fn drawn_over(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Int {
  let (x, y, w, h) = r
  let (wx, wy, ww, wh) = match t.rect_of(over_words) {
    Some(q) => q
    None => return -1
  }
  let rects = t.drawn_rects()
  let mut own = -1
  for i, d in rects {
    if d.0 <= wx && d.1 <= wy && d.0 + d.2 >= wx + ww && d.1 + d.3 >= wy + wh && d.0 >= x - 0.5 && d.1 >= y - 0.5 &&
      d.0 + d.2 <= x + w + 0.5 && d.1 + d.3 <= y + h + 0.5 {
      own = i
    }
  }
  if own < 0 {
    return -1
  }
  let mut n = 0
  for i in (own + 1)..<rects.length() {
    let (dx, dy, dw, dh, _) = rects[i]
    let overlaps = dx < x + w && dx + dw > x && dy < y + h && dy + dh > y
    let inside = dx >= x - 0.5 && dy >= y - 0.5 && dx + dw <= x + w + 0.5 && dy + dh <= y + h + 0.5
    if overlaps && !inside {
      n = n + 1
    }
  }
  n
}

///|
test "a toast with its action said while the old frame's modal sheet is up: drawn over it, its action pressed where it is drawn done once, a press beside it the sheet's" {
  let runs = Ref(0)
  let t = over_sheet(runs)
  let sheet = t.find("发到") is Some(_)
  let toast = said_any(t, Status, over_words).map(fn(s) { s.rect })
  let button = said_any(t, Button, "撤销").map(fn(s) { s.rect })
  // (drawn over the sheet: nothing drawn over it after its ground)
  let over = match toast {
    Some(r) => drawn_over(t, r)
    None => -2
  }
  // (beside it, at its height: the sheet's, the toast neither pressed nor gone)
  let beside = match toast {
    Some((x, y, _, h)) => {
      t.tap(x / 2.0, y + h / 2.0)
      t.frame()
      (t.find(over_words) is Some(_), runs.val, t.find("发到") is Some(_))
    }
    None => (false, -1, false)
  }
  // (its action pressed where it is drawn: done once, the toast gone; its time after, nothing more)
  let acted = match button {
    Some((bx, by, bw, bh)) => {
      t.tap(bx + bw / 2.0, by + bh / 2.0)
      t.run_for(@kit.presence_out_ms)
      let once = (runs.val, t.find(over_words) is None)
      t.run_for(@sf.toast_action_ms)
      (once, runs.val)
    }
    None => ((-1, false), -1)
  }
  assert_eq((sheet, over, beside, acted), (true, 0, (true, 0, true), ((1, true), 1)))
}

///|
test "a toast said while the old frame's modal sheet is up: read out, it and its action, not hidden under the sheet" {
  let t = over_sheet(Ref(0))
  let read = [(@ui.Role::Status, over_words), (@ui.Role::Button, "撤销")].map(fn(k) {
    match said_any(t, k.0, k.1) {
      Some(s) => (true, s.hidden, s.actions.contains(Activate) || k.0 == Status)
      None => (false, true, false)
    }
  })
  assert_eq(read, [(true, false, true), (true, false, true)])
}
