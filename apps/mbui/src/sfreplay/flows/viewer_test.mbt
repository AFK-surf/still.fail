// 96-viewer (e2e/traces/viewer.trace): the viewer over a chat's two pictures (alice's other device sends them: peer
// createfiles): the first grows from its thumbnail; ›, the next (the core's imageNear); a swipe back to the first;
// marking: a box drawn, its note said, 下载标注后的图片 (the host draws the marks onto the picture: a PNG kept in the
// phone's photo album), then 添加到对话: the marked picture and the note's quote in the composer, sent with words.

///|
test "96-viewer" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("viewer"), seed~, env=[("MBUI_VIEWER_AWAKE", "1")])
    // (what the host drew of the marks, as the run's gave it: the PNG it sent up)
    // (handed to the core whole: composer.add; a run from before, its parts: station.upload.part)
    let handed = match f.r.sent_bytes_from("composer.add", "name", "e2e-photo-标注-") {
      Some(b) => Some(b)
      None => f.r.sent_bytes_from("station.upload.part", "name", "e2e-photo-标注-")
    }
    let marked = match handed {
      Some(b) => b
      None => fail("flow: the trace has no marked picture's bytes")
    }
    let ms300 = (300.0 / @ui.drag_step_ms).to_int()
    f.see("端到端测试")
    f.peer("peer createfiles 两张图片 201493 post:收到两张图片 201493 -- e2e-photo.jpg e2e-photo2.png")
    f.see("两张图片 201493")
    f.tap("两张图片 201493")
    f.run_to(@ui.nav_rest())
    f.see("=studio")
    f.see("img:e2e-photo.jpg")
    f.tap("img:e2e-photo.jpg")
    // flown open from its thumbnail, its bars on once it is in
    f.run_to(@sfapp.preview_rest())
    // grown from its thumbnail, its whole picture here (复制 offered)
    f.see("icon:copy")
    f.see("icon:chevron-right")
    f.tap("icon:chevron-right")
    f.see("e2e-photo2.png")
    // a swipe back to the first
    f.drag_at(60.0, 400.0, 300.0, 0.0, steps=ms300)
    f.see("e2e-photo.jpg")
    f.tap("icon:edit")
    f.see("icon:scribble")
    // a box drawn, its note said
    f.drag_at(120.0, 360.0, 140.0, 90.0, steps=ms300)
    // its note's box: its tick, 完成 (as Android's test finds it: its contentDescription)
    f.see("=完成")
    f.type_text("这里要对齐 201493")
    f.tap("=完成")
    f.gone("=完成")
    f.t.marks_make(marked)
    f.tap("icon:download")
    // (a phone's: into its photo album, said so: keep_way_of)
    f.see("已保存到相册")
    let kept = f.t.kept().filter(fn(k) { k.0.has_prefix("e2e-photo-标注-") && k.0.has_suffix(".png") })
    f.check(kept.length() == 1, "kept: \{f.t.kept().map(fn(k) { k.0 })}")
    f.check(
      f.t.kept_ways().iter().any(fn(k) { k.0.has_prefix("e2e-photo-标注-") && k.1.to_string() == "Photos" }),
      "kept: \{f.t.kept_ways()}",
    )
    f.check(f.t.marks_drawn().length() >= 1, "no marks drawn onto the picture")
    f.t.marks_make(marked)
    f.tap("添加到对话")
    f.gone("=添加到对话")
    f.see("发消息")
    // the quote and the picture in the composer long enough to be kept as the chat's draft (draft.put), in the run as
    // here, before anything is typed
    f.run_for(@sfapp.draft_keep_ms)
    f.tap("发消息")
    f.type_text("标注过的图片 201493")
    // the words in the field long enough to be kept as the chat's draft with the quote and the picture (draft.put),
    // in the run as here
    f.run_for(@sfapp.draft_keep_ms)
    f.tap("icon:arrow-up")
    f.check(f.t.field_words() == "", "the field not emptied as the message went: \{f.t.field_words()}")
    f.run_for(@sfapp.flight_ms)
    f.see("标注过的图片 201493")
    f.gone("正在发送")
    f.end()
  })
}
