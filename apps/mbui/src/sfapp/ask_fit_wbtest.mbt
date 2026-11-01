// A question with a long hint in a short window on 大屏: its panel within the window less what a dialog keeps round it
// (dialog_room: 24 over and under), its title over what it holds, its cancel and its action in sight; what it holds
// scrolling in it to its end. The old dialog's (parts.mbt's dialog: max_h, capped) as the contract.

///|
let ask_long_hint : String = "改名后，旧的名字仍会出现在通知和历史记录里，直到它们更新；分享出去的链接不受影响，打开时显示新的名字。这一段说明故意写得很长，好让它在窄小的窗口里折成很多行，比面板能放下的还高。再多写一些：搜索时新旧两个名字都能找到，导出的记录里保留改名的时间。"

///|
/// A title long enough to take two lines in the panel (520 wide, 24 in at its sides).
let ask_long_title : String = "重新命名这个对话，新的名字会同步给这个工作区里的所有成员，并出现在他们的对话列表和通知里"

///|
/// The rows of glyphs drawn in the last frame whose middle is within `r` (x, y, w, h), top to bottom: where each row's
/// middle is, and its glyphs as drawn (their boxes), whether each shows whole within its clip, and the clip.
fn glyph_rows(
  t : @ui.Tester,
  r : (Double, Double, Double, Double),
) -> Array[(Double, Array[((Double, Double, Double, Double), Bool, (Double, Double, Double, Double))])] {
  let rows : Array[(Double, Array[((Double, Double, Double, Double), Bool, (Double, Double, Double, Double))])] = []
  for e in t.glyph_clips() {
    let (b, clip) = e
    let (mx, my) = ((b.0 + b.2) / 2.0, (b.1 + b.3) / 2.0)
    if mx < r.0 || mx > r.0 + r.2 || my < r.1 || my > r.1 + r.3 {
      continue
    }
    // (whole within its clip: readable, not a sliver)
    let shows = b.0 >= clip.0 - 0.5 && b.1 >= clip.1 - 0.5 && b.2 <= clip.2 + 0.5 && b.3 <= clip.3 + 0.5
    match rows.search_by(fn(row) { (row.0 - my).abs() < 3.0 }) {
      Some(i) => rows[i].1.push((b, shows, clip))
      None => rows.push((my, [(b, shows, clip)]))
    }
  }
  rows.sort_by(fn(a, b) { a.0.compare(b.0) })
  rows
}

///|
/// Of the rows of glyphs drawn within `r` (glyph_rows), the glyphs of its last line (its middle within a line's height
/// of its foot, the height rows are apart): none where fewer than two rows are drawn.
fn last_line(
  t : @ui.Tester,
  r : (Double, Double, Double, Double),
) -> Array[((Double, Double, Double, Double), Bool, (Double, Double, Double, Double))] {
  let rows = glyph_rows(t, r)
  guard rows.length() >= 2 else { return [] }
  let apart = rows[1].0 - rows[0].0
  let out = []
  for row in rows {
    if row.0 > r.1 + r.3 - apart {
      out.append(row.1)
    }
  }
  out
}

///|
test "大屏, a short window: a question with a long title and a long hint, its panel within the window less 24 over and under; its title on two lines over what it holds, its cancel and action in the panel; what it holds scrolled by the wheel till its hint's last line shows in it, its title and buttons where they were" {
  let t = confirm_wide()
  t.resize(1280.0, 340.0)
  t.run_for(@ui.move_most_ms)
  @sf.ask(ask_long_title, "保存", fn(_) {  }, hint=ask_long_hint + ask_long_hint + "说明到此为止。")
  t.run_for(@ui.move_most_ms)
  let (_, py, _, ph) = t.query(Dialog, label=ask_long_title).unwrap().rect
  let within = py >= 24.0 - 0.5 && py + ph <= 340.0 - 24.0 + 0.5
  let no = t.query(Button, label="取消").unwrap().rect
  let ok = t.query(Button, label="保存").unwrap().rect
  // (its buttons in the panel)
  let in_panel = fn(r : (Double, Double, Double, Double)) { r.1 >= py && r.1 + r.3 <= py + ph + 0.5 }
  // (its title: two rows of glyphs drawn at least, wholly shown)
  let title = t.rect_of(ask_long_title).unwrap()
  let title_rows = glyph_rows(t, title)
  let title_whole = title_rows.iter().all(fn(row) { row.1.iter().all(fn(g) { g.1 }) })
  let title_foot = title.1 + title.3
  // (its field under its title)
  let field = t.query(TextField).unwrap().rect
  let under_title = field.1 >= title_foot - 0.5
  // (its hint's last line: none of it whole (drawn cut away, or not drawn); then all of it whole, in a clip under
  // its title and over its buttons: what it holds as it shows)
  let hint0 = t.rect_of("说明到此为止").unwrap()
  let end_hidden = last_line(t, hint0).iter().all(fn(g) { !g.1 })
  for _ in 0..<12 {
    t.wheel(640.0, py + ph / 2.0, 120.0)
    t.run_for(@ui.move_most_ms)
  }
  let hint1 = t.rect_of("说明到此为止").unwrap()
  let last1 = last_line(t, hint1)
  let foot = dmin(no.1, ok.1)
  let end_shown = last1.length() > 0 && last1.iter().all(fn(g) { g.1 && g.2.1 >= title_foot - 0.5 && g.2.3 <= foot + 0.5 })
  let moved = hint1.1 < hint0.1
  let kept = t.rect_of(ask_long_title) == Some(title) &&
    t.query(Button, label="取消").map(fn(b) { b.rect }) == Some(no) &&
    t.query(Button, label="保存").map(fn(b) { b.rect }) == Some(ok)
  assert_eq(
    (within, in_panel(no), in_panel(ok), title_rows.length() >= 2, title_whole, under_title, end_hidden, end_shown, moved, kept),
    (true, true, true, true, true, true, true, true, true, true),
    msg="panel \{py} \{ph} title \{title} rows \{title_rows.length()} field \{field} hint \{hint0} → \{hint1} buttons \{no} \{ok}",
  )
}

///|
test "大屏, a short window, started with keyboard and mouse or touch: a question with a long title and a long hint, the wheel turned at the middle of the window (over its field, an old view's, in what it holds): what it holds scrolled, its title and buttons where they were" {
  let out = []
  for platform in [0, 2] {
    let t = ask_field_tester(1280.0, platform)
    // (the question ask_field_tester asked closed; this one alone, in a window 340 tall)
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    t.resize(1280.0, 340.0)
    t.run_for(@ui.move_most_ms)
    @sf.ask(ask_long_title, "保存", fn(_) {  }, value="周报整理", hint=ask_long_hint + "说明到此为止。")
    t.run_for(@ui.move_most_ms)
    let hint0 = t.rect_of("改名后").unwrap()
    // (the foot of what shows of what it holds: its hint's glyphs' clip)
    let foot = glyph_rows(t, hint0).get(0).map(fn(row) { row.1[0].2.3 }).unwrap_or(-1.0)
    let field = t.query(TextField).unwrap().rect
    let title = t.rect_of(ask_long_title)
    let ok = t.query(Button, label="保存").map(fn(b) { b.rect })
    for _ in 0..<3 {
      t.wheel(640.0, 170.0, 300.0)
      t.run_for(@ui.move_most_ms)
    }
    let hint1 = t.rect_of("改名后").unwrap()
    out.push(
      (
        platform,
        hint1.1 < hint0.1 - 1.0,
        t.rect_of(ask_long_title) == title,
        t.query(Button, label="保存").map(fn(b) { b.rect }) == ok,
        "field \{field} hint \{hint0} (middle \{hint0.1 + hint0.3 / 2.0}) shown to \{foot} → \{hint1}",
      ),
    )
  }
  assert_eq(out.map(fn(o) { (o.0, o.1, o.2, o.3) }), [(0, true, true, true), (2, true, true, true)], msg="\{out}")
}
