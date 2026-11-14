// A connect's model control (model_triple_node) on its page: its model, its effort and who runs it in one row in its
// capsule, at the end of 模型's row; what is said at its longest given way within the row, never past the window.

///|
/// Where words that are `s` exactly are drawn now (Tester::words), the first of them.
fn words_exactly_at(t : @ui.Tester, s : String) -> (Double, Double, Double, Double)? {
  for w in t.words() {
    if w.0 == s {
      return Some((w.1, w.2, w.3, w.4))
    }
  }
  None
}

///|
test "a connect's model control says its model, effort and who runs it in one row, in that order" {
  for win in [corner_windows[0], corner_windows[5]] {
    let t = screen_in("settings-connect", win, "zh")
    let found = ["Opus 5.5", "高", "自动分配"].map(fn(s) { (s, words_exactly_at(t, s)) })
    let at = found.map(fn(f) raise {
      guard f.1 is Some(r) else { fail("\{win.0}: no \{f.0}: \{t.words().map(fn(w) { w.0 }).join("|")}") }
      r
    })
    let middle = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
    for i in 1..<at.length() {
      assert_true((middle(at[i]) - middle(at[0])).abs() < 1.0, msg="\{win.0}: not one row: \{Repr(found)}")
      assert_true(at[i].0 >= at[i - 1].0 + at[i - 1].2, msg="\{win.0}: out of order: \{Repr(found)}")
    }
    assert_true(at.iter().all(fn(r) { r.0 >= 0.0 && r.0 + r.2 <= win.1 }), msg="\{win.0}: past the window: \{Repr(found)}")
  }
}

///|
/// The nodes of the window's tree drawing words that begin with `s`: where each is drawn and how wide (a one-line words
/// node is cut to that width with "…").
fn drawn_words(s : String) -> Array[(Double, Double, Double)] {
  guard @ui.view_tree() is Some(tree) else { return [] }
  tree.drawn().filter(fn(d) { d.words.has_prefix(s) }).map(fn(d) { (d.x, d.y, d.w) })
}

///|
/// Each node drawing words that begin with one of `starts`, found, drawn with some width and inside a window `w` wide.
fn drawn_within(win : String, w : Double, starts : Array[String]) -> Unit raise {
  for s in starts {
    let found = drawn_words(s)
    assert_true(found.length() > 0, msg="\{win}: no \{s}")
    for d in found {
      assert_true(d.2 > 0.0 && d.0 >= 0.0 && d.0 + d.2 <= w, msg="\{win}: \{s} at \{d.0},\{d.1}, \{d.2} wide")
    }
  }
}

///|
test "a connect's model control said at its longest is cut within the window, its name never left out" {
  for win in [corner_windows[0], corner_windows[1], corner_windows[5]] {
    let _ = screen_in("settings-connect", win, "zh", said=true)
    drawn_within(win.0, win.1, ["Opus 5.5 — "])
    // (who runs it, where it is kept: within the window too)
    for d in drawn_words("自动分配 — ") {
      assert_true(d.2 > 0.0 && d.0 >= 0.0 && d.0 + d.2 <= win.1, msg="\{win.0}: 自动分配 at \{d.0},\{d.1}, \{d.2} wide")
    }
  }
}

///|
test "a connect's recent chat said at its longest: its title and when it was active each have room on its row" {
  for win in [corner_windows[0], corner_windows[1], corner_windows[5]] {
    let t = screen_in("settings-connect", win, "zh", said=true)
    t.scroll_all_to_end() |> ignore
    drawn_within(win.0, win.1, ["Slack 里问的报销流程 — ", "昨天 — "])
  }
}


///|
test "借用 in a connect's model panel: the panel goes and the ask stays up, its title, its lines, 取消 and 借用" {
  for win in [corner_windows[0], corner_windows[5]] {
    let t = screen_in("settings-connect-borrow", win, "zh")
    guard t.find("Opus 5.5") is Some((x, y)) else { fail("\{win.0}: no model control") }
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    guard t.query(Button, label="借用") is Some(b) else {
      fail("\{win.0}: no 借用 in the panel: \{t.words().map(fn(w) { w.0 }).join("|")}")
    }
    t.tap(b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
    t.run_for(@ui.move_most_ms)
    let said = t.words().map(fn(w) { w.0 }).join("|")
    assert_true(t.find("借用 Maple 的 Fable 5.1？") is Some(_), msg="\{win.0}: the ask gone: \{said}")
    assert_true(t.find("借用后，这个连接的会话也用它的额度。") is Some(_), msg="\{win.0}: its lines: \{said}")
    assert_true(t.query(Button, label="取消") is Some(_), msg="\{win.0}: its 取消: \{said}")
    // (the panel itself gone: its note over the foot no longer drawn)
    assert_true(t.find("Fable 5.1 在 Maple 上") is None, msg="\{win.0}: the panel still up: \{said}")
  }
}
