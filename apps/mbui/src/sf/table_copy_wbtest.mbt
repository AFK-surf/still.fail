// A table's copy key (table_copy.mbt): on a row of its own over the table, at its end; its menu copying it as Markdown,
// as CSV, or as a picture of it whole.

///|
/// A table the core read (its tree kept: src/sfkept), with its Markdown and CSV as the core wrote them.
let copy_table : String = "| 模型 | 输入 | 输出 | 缓存读 |\n| --- | --- | --- | --- |\n| Opus 5.5 | $5 | $25 | $0.5 |\n| Sonnet 5 | $3 | $15 | $0.3 |"

///|
/// The table in a message's column, the presenters over it.
fn table_tester(platform : Int, w : Double, h : Double) -> @ui.Tester {
  presenters_reset()
  @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.column(w=Fill(1.0), pad=16.0, fn() { markdown(c, copy_table) |> ignore }) |> ignore
        presented(c)
      })
    },
    w~,
    h~,
    platform~,
  )
}

///|
test "a table's copy key: on a row of its own over the table, at its end; its menu copies it as CSV, as Markdown" {
  let t = table_tester(2, 390.0, 844.0)
  t.draw()
  let (kx, ky, kw, kh) = t.rect_of("复制").unwrap()
  let (hx, hy, _, _) = t.rect_of("模型").unwrap()
  // over the table, not over its head's words; at its end, right of where its first column's words begin
  assert_true(ky + kh < hy, msg="\{(ky, kh, hy)}")
  assert_true(kx > hx && kx + kw <= 390.0 - 16.0, msg="\{(kx, kw, hx)}")
  t.tap_text("复制")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("web-main.prose.copyCsv")
  assert_eq(t.clipboard(), "模型,输入,输出,缓存读\nOpus 5.5,$5,$25,$0.5\nSonnet 5,$3,$15,$0.3")
  t.frame()
  assert_true(t.find("已复制") is Some(_))
  t.tap_text("已复制")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("web-main.prose.copyMarkdown")
  assert_eq(t.clipboard(), copy_table)
}

///|
test "a table's copy key with a mouse: the same row over it; its picture copied whole, the key not in it" {
  let t = table_tester(0, 1280.0, 800.0)
  t.draw()
  t.draw()
  let (_, ky, _, kh) = t.rect_of("复制").unwrap()
  let (_, hy, _, _) = t.rect_of("模型").unwrap()
  assert_true(ky + kh < hy, msg="\{(ky, kh, hy)}")
  t.tap_text("复制")
  t.run_for(@kit.presence_in_ms)
  t.tap_text("desktop.contextMenu.copyImage")
  t.frame()
  t.frame()
  // the table whole, on its own, on the clipboard; its key says it copied a moment
  let shots = t.shots()
  assert_eq(shots.length(), 1)
  assert_true(shots[0].iter().any(fn(w) { w.contains("缓存读") }) && shots[0].iter().any(fn(w) { w.contains("Sonnet 5") }))
  assert_true(!shots[0].iter().any(fn(w) { w.contains("复制") }))
  assert_true(t.clipboard_png() is Some(_))
  assert_true(t.find("已复制") is Some(_))
  t.run_for(copied_ms)
  assert_true(t.find("已复制") is None)
}
