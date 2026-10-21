// The run's models (settings/model_list.mbt; SettingParts.kt ModelList) over settings-run-models' many.

///|
test "a run's models: by series, filtered by what is typed, none said so" {
  let t = settings_tester("run:ws1/st1#s-c1", mode="settings-run-models", shows="settings-run-models")
  assert_true(t.find("搜索模型") is Some(_), msg="a filter once more than 8")
  assert_true(t.find("Sonnet") is Some(_), msg="a series' name")
  assert_true(t.find("Haiku 4.5") is Some(_))
  t.tap_text("搜索模型")
  t.type_text("haiku")
  t.frame()
  assert_true(t.find("Haiku 4.5") is Some(_))
  assert_true(t.find("Opus 5.1") is None)
  t.type_text("x")
  t.frame()
  assert_true(t.find("没有匹配的模型") is Some(_))
}

///|
test "a file's code highlighted as a whole, then cut at its lines (FilePreview.kt TextViewer)" {
  let runs = @sf.highlight("let a = 1\n// note\nlet b = \"x\"", "javascript", false).unwrap()
  let lines = runs_by_line(runs)
  assert_eq(lines.length(), 3)
  let words = lines.map(fn(l) { l.map(fn(r) { r.text }).join("") })
  assert_eq(words, ["let a = 1", "// note", "let b = \"x\""])
  // more than one colour on a line of code
  assert_true(lines[0].length() > 1)
  assert_true(lines.iter().all(fn(l) { l.iter().all(fn(r) { r.mono }) }))
}
