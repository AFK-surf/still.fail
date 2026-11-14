///|
test "a title's marked part is a run of its own in the accent, the rest in the title's ink, its marks read out as nothing" {
  let title = "模型已被 " + title_accented("still.fail 开发") + " 预设固定"
  assert_true(title_marked(title))
  assert_eq(title_plain(title), "模型已被 still.fail 开发 预设固定")
  let runs = title_runs(title, 0x123456FFL)
  assert_eq(runs.map(fn(r) { (r.text, r.color) }), [("模型已被 ", 0L), ("still.fail 开发", 0x123456FFL), (" 预设固定", 0L)])
  assert_false(title_marked("预设"))
  assert_eq(title_plain("预设"), "预设")
}
