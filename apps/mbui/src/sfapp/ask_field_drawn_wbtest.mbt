// A question's field drawn where it is laid out, as the old dialog's was: its box (its ground and line round its line, as
// tall as a one-line field at least: the theme's controls', by the native input) whole within what cuts it; its own
// words drawn whole in its line, what is typed too. On 中屏 and 大屏, touch and keyboard and mouse.

///|
/// `w` wide (大屏 1280, 中屏 900), started as `platform` (0 macOS: keyboard and mouse; 2 Android: touch), chat A open,
/// a question with its line given open in it.
fn ask_field_tester(w : Double, platform : Int) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  wide_src.val = Some(src)
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=840.0, platform~)
  t.run_for(@ui.move_most_ms)
  @sf.ask("重新命名这个对话", "保存", fn(_) {  }, value="周报整理", hint="名字会同步给所有成员。")
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The field's line (its editor's rect); its box (the smallest rect drawn round the line, as wide as it and its sides'
/// room at least, less tall than a panel): its rect, whether what cuts it holds all of it; the editor's own glyphs (each
/// cut to its line, as paint_editor cuts what it draws: none of what is drawn round it): how many, whether each shows
/// whole within that; said with the box's clip and the first glyph's.
fn ask_field_drawn(
  t : @ui.Tester,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double)?, Bool, Int, Bool, String) {
  let line = t.query(TextField).unwrap().rect
  let (fx, fy, fw, fh) = line
  let mut bx : ((Double, Double, Double, Double), (Double, Double, Double, Double))? = None
  let mut n = 0
  let mut shown = true
  let mut said = ""
  for i in t.drawn_cut() {
    let (kind, x, y, w, h, clip) = i
    if kind == 0 && x <= fx - 8.0 && x + w >= fx + fw + 8.0 && y <= fy + 0.5 && y + h >= fy + fh - 0.5 && h < 100.0 &&
      bx.map(fn(b) { w * h < b.0.2 * b.0.3 }).unwrap_or(true) {
      bx = Some(((x, y, w, h), clip))
    }
    // (the editor's own: cut within its line)
    if kind == 1 && clip.0 >= fx - 0.5 && clip.1 >= fy - 0.5 && clip.2 <= fx + fw + 0.5 && clip.3 <= fy + fh + 0.5 {
      n += 1
      shown = shown && x >= clip.0 - 0.5 && y >= clip.1 - 0.5 && x + w <= clip.2 + 0.5 && y + h <= clip.3 + 0.5
      if n == 1 {
        said = said + " glyph \{(x, y, w, h)} clip \{clip}"
      }
    }
  }
  let held = match bx {
    Some(((x, y, w, h), c)) => {
      said = said + " box clip \{c}"
      c.0 <= x + 0.5 && c.1 <= y + 0.5 && c.2 >= x + w - 0.5 && c.3 >= y + h - 0.5
    }
    None => false
  }
  (line, bx.map(fn(b) { b.0 }), held, n, shown, said)
}

///|
test "中屏 and 大屏, touch and keyboard and mouse: a question, its line given: its field's box drawn whole, as tall as a one-line field at least; its words drawn whole in its line; a word typed, drawn too" {
  for c in [(1280.0, 0), (1280.0, 2), (900.0, 0), (900.0, 2)] {
    let t = ask_field_tester(c.0, c.1)
    let (line, bx, held0, n0, shown0, said0) = ask_field_drawn(t)
    let tall = bx.map(fn(b) { b.3 >= @sf.input_height() - 0.5 }).unwrap_or(false)
    t.type_text("好")
    t.run_for(@ui.move_most_ms)
    let (_, _, held1, n1, shown1, _) = ask_field_drawn(t)
    assert_eq(
      (tall, held0, n0 >= 4, shown0, held1, n1 > n0, shown1),
      (true, true, true, true, true, true, true),
      msg="\{c} line \{line} box \{bx} (one-line \{@sf.input_height()}) held \{held0} glyphs \{n0} shown \{shown0} → typed held \{held1} glyphs \{n1} shown \{shown1};\{said0}",
    )
  }
}
