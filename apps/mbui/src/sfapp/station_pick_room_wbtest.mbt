// The station files picker (＋'s Station 文件, a dialog drawn by the window's tree) in the touch and tablet windows: its
// way's first step, 「所有位置」, has a finger's room to be pressed in (rooms.mbt: 9 under it before the list's first
// row's), and pressed it goes back to all the places; the first row under it ticks the whole folder.

///|
test "the station files picker: 所有位置 has a finger's room, and it and the first row under it do what they say" {
  let said : Array[String] = []
  for win in corner_windows {
    if win.0 != "touch" && win.0 != "tablet" {
      continue
    }
    let t = screen_in("chat-station-files", win, "zh")
    let frames = fn() {
      for _ in 0..<3 {
        t.frame_at(t.next_frame_time())
      }
    }
    let faults = t.room_faults().filter(fn(f) { f.contains("所有位置") })
    // (the fixture's: 发布清单.md ticked)
    let one = t.find("添加 1 个") is Some(_)
    t.tap_text("整个文件夹")
    frames()
    let two = t.find("添加 2 个") is Some(_)
    t.tap_text("所有位置")
    frames()
    let places = t.find("整个文件夹") is None && t.find("Willow · 文档") is None && t.find("所有位置") is Some(_)
    said.push("\{win.0}: \{@ui.list_text(faults)} \{one} \{two} \{places}")
  }
  assert_eq(said, ["touch: [] true true true", "tablet: [] true true true"])
}
