// One of a station's memory pages (memory_doc.mbt) alone, at each width, with a finger and with a mouse: a skill, what
// it is and when it is read, sharing it, its pages picked by their pills; the global memory a part at a time.

///|
test "a skill's memory page, at each width and with either hand: what it is and when it is read, its pages picked by their pills" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(MemoryDoc("ws1/st1", "发布流程", 0), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("项目记忆 · 读取时机") is Some(_), msg="\{at}: what it is, the core's")
    assert_true(t.find("发布新版本时") is Some(_), msg=at)
    // its SKILL.md first, then the file picked: every pill there, none out of the row
    assert_true(t.find("总览") is Some(_) && t.find("checklist") is Some(_), msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
    t.click(Tab, label="checklist")
    t.draw()
    assert_true(t.find("签名") is Some(_), msg="\{at}: the file's text")
  }
}

///|
test "the global memory's page, at each width and with either hand: when it is read, its parts picked by their pills" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(MemoryDoc("ws1/st1", "", 0), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("全局记忆") is Some(_), msg=at)
    assert_true(t.find("习惯") is Some(_), msg="\{at}: its parts' pills")
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}
