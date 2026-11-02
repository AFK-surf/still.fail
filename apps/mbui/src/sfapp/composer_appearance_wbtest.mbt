// What is put into a composer begins changing it at once; what it already holds goes with its ground.

///|
let composer_sample_ms : Double = 50.0

///|
test "a quote already in the composer moves with its ground as another is added" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": quote_passage, "ts": "ts8" })
  t.run_for(@ui.move_most_ms)
  let gap = quote_ground(t).1 - composer_glass(t).1
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": "第二段引用", "ts": "ts9" })
  t.run_for(composer_sample_ms)
  let now = quote_ground(t).1 - composer_glass(t).1
  assert_true((now - gap).abs() < 2.0, msg="the first quote did not move with its ground")
}

///|
test "on a small screen a waiting quote moves with the composer when another arrives" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": quote_passage, "ts": "ts8" })
  t.run_for(@ui.move_most_ms)
  let ground = fn() {
    let glasses = t.drawn_glass_corners()
    glasses.sort_by(fn(a, b) { a.1.compare(b.1) })
    glasses[glasses.length() - 1].1
  }
  let gap = quote_ground(t).1 - ground()
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": "第二段引用", "ts": "ts9" })
  t.run_for(composer_sample_ms)
  assert_true((quote_ground(t).1 - ground() - gap).abs() < 2.0, msg="the first quote did not move with its ground")
}

///|
test "a quote without a visible source comes in within the growing composer" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  @sfbase.writing_quote(src, @sfbase.writing(src, "ws1/st1:s-c1"), {
    "author": "Ana", "text": quote_passage, "ts": "ts8",
  })
  t.run_for(composer_sample_ms)
  let (_, ground_y, _, _) = composer_glass(t)
  let cards = t.drawn_instances().filter(fn(a) {
    // (its card's shape, as big as the composer's room has grown for it by then)
    a[5] == 0.0 && a[3] > 0.0 && a[2] / a[3] > 11.5 && a[2] / a[3] < 14.5 && a[2] < 800.0 && a[1] > 500.0
  })
  assert_true(cards.length() > 0, msg="the quote's card should be drawn")
  assert_true(cards.iter().any(fn(a) { a[1] >= ground_y - 1.0 }), msg="the new quote appeared above the composer's ground")
}

///|
test "a file without a visible source comes in within the growing composer" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  @sfbase.writing_add(src, @sfbase.writing(src, "ws1/st1:s-c1"), "ws1/st1", "新文件.txt", b"test")
  t.run_for(composer_sample_ms)
  let (_, ground_y, _, _) = composer_glass(t)
  let (_, words_y) = t.drawn_of("新文件").unwrap()
  assert_true(words_y >= ground_y - 1.0, msg="the file appeared above the composer's ground")
}

///|
test "a newly added picture appears within the growing composer" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "新图片.png", png_head())
  t.run_for(composer_sample_ms)
  let picture = @sfbase.writing_pictures[text(Some(w.files[0]), "id")]
  let images = t.drawn_instances().filter(fn(a) { a[5] == 4.0 && t.image_src(a[20].to_int()) == picture })
  let (_, ground_y, _, _) = composer_glass(t)
  assert_true(images.length() > 0, msg="the picture was not drawn as the composer opened")
  assert_true(images.iter().any(fn(a) {
    let top = dmax(a[1], a[17])
    let bottom = dmin(a[1] + a[3], a[19])
    bottom > top && top >= ground_y - 1.0
  }), msg="the picture was visible above the composer's ground")
}

///|
test "a newly added picture comes in whole, never cut or faded across as the composer opens" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "新图片.png", png_head())
  let picture = @sfbase.writing_pictures[text(Some(w.files[0]), "id")]
  let mut seen = 0
  let mut ms = 0.0
  while ms < @ui.move_most_ms {
    t.run_for(@ui.frame_period_default)
    ms = ms + @ui.frame_period_default
    let (_, ground_y, _, _) = composer_glass(t)
    for a in t.drawn_instances() {
      if a[5] != 4.0 || t.image_src(a[20].to_int()) != picture || a[11] <= 0.0 {
        continue
      }
      seen = seen + 1
      let (top, bottom) = (a[1], a[1] + a[3])
      assert_true(a[17] <= top + 0.5 && a[19] >= bottom - 0.5, msg="at \{ms} ms the picture \{top}–\{bottom} was cut to \{a[17]}–\{a[19]}")
      assert_true(!(a[53] > 0.0 && a[52] + a[53] > top + 0.5) && !(a[55] > 0.0 && a[54] - a[55] < bottom - 0.5), msg="at \{ms} ms the picture \{top}–\{bottom} faded across: from its top \{a[52]}+\{a[53]}, its foot \{a[54]}-\{a[55]}")
      assert_true(top >= ground_y - 1.0, msg="at \{ms} ms the picture showed above the composer's ground")
    }
  }
  assert_true(seen > 0, msg="the picture was not drawn as the composer opened")
}

///|
test "a quote sent while the composer opens leaves from where it was seen" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.tap_text("发消息")
  t.type_text("先上屏")
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": quote_passage, "ts": "ts8" })
  t.run_for(composer_sample_ms * 2.0)
  let before = quote_once(t)
  tap_send(t)
  assert_true(send_flight.get() is Some(_), msg="the message was not sent")
  let after = quote_once(t)
  assert_true((after.0 - before.0).abs() < 1.0 && (after.1 - before.1).abs() < 1.0, msg="the quote jumped from \{before} to \{after} on sending")
}

///|
test "a picture sent while the composer opens leaves from where it was seen" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.tap_text("发消息")
  t.type_text("看这张")
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "新图片.png", png_head())
  let picture = @sfbase.writing_pictures[text(Some(w.files[0]), "id")]
  t.run_for(composer_sample_ms * 2.0)
  let before = picture_instances(t, picture)[0].1
  tap_send(t)
  assert_true(send_flight.get() is Some(_), msg="the message was not sent")
  let after = picture_instances(t, picture)
  let sent = match after.iter().find_first(fn(p) { (p.1[0] - before[0]).abs() < 1.0 && (p.1[1] - before[1]).abs() < 1.0 }) {
    Some((_, a)) => a
    None => fail("the picture moved as it was sent")
  }
  let visible_before = (dmax(before[1], before[17]), dmin(before[1] + before[3], before[19]))
  let visible_after = (dmax(sent[1], sent[17]), dmin(sent[1] + sent[3], sent[19]))
  assert_true((visible_after.0 - visible_before.0).abs() < 1.0 && (visible_after.1 - visible_before.1).abs() < 1.0, msg="the picture's visible part changed from \{visible_before} to \{visible_after} on sending")
  assert_true((sent[11] - before[11]).abs() < 0.03, msg="the picture's opacity changed on sending")
}

///|
test "an image's marks come into the room the composer opens" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.run_for(@ui.move_most_ms)
  marked_into["ws1/st1:s-c1"] = [("图片-标注.png", png_head(), [("图片 标注 1", quote_passage, "这里对齐")], "image")]
  t.run_for(composer_sample_ms)
  assert_eq(named(calls, "composer.quote").length(), 1, msg="the mark was not put in the composer")
  let (_, ground_y, _, _) = composer_glass(t)
  // (its card's shape, as big as the composer's room has grown for it by then)
  let cards = t.drawn_cut().filter(fn(r) { r.0 == 0 && r.4 > 0.0 && r.3 / r.4 > 11.5 && r.3 / r.4 < 14.5 && r.3 < 800.0 })
  assert_true(cards.length() > 0, msg="the mark's card was not drawn")
  assert_true(cards.iter().any(fn(r) {
    let (_, _, y, _, h, (_, top, _, bottom)) = r
    let visible_top = dmax(y, top)
    dmin(y + h, bottom) <= visible_top || visible_top >= ground_y - 1.0
  }), msg="the mark was visible above the composer's ground")
  t.run_for(@ui.move_most_ms)
  quote_once(t) |> ignore
}

///|
test "an existing file stays in place when a quote is added above it" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "原有文件.txt", b"test")
  t.run_for(@ui.move_most_ms)
  let before = t.drawn_of("原有文件").unwrap().1
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": quote_passage, "ts": "ts8" })
  t.draw()
  let first = t.drawn_of("原有文件").unwrap().1
  t.run_for(composer_sample_ms)
  let mid = t.drawn_of("原有文件").unwrap().1
  assert_true((first - before).abs() < 1.0 && (mid - before).abs() < 2.0, msg="the existing file jumped when the quote came in")
}

///|
test "the composer follows a waiting video's picture becoming available" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "视频.mov", b"video")
  @sfbase.writing_add(src, w, "ws1/st1", "日志.txt", b"log")
  t.run_for(@ui.move_most_ms)
  let ground = fn() {
    let glasses = t.drawn_glass_corners()
    glasses.sort_by(fn(a, b) { a.1.compare(b.1) })
    glasses[glasses.length() - 1].1
  }
  let before = ground()
  let id = text(Some(w.files[0]), "id")
  @sfbase.writing_pictures[id] = "mem:fixture/video-still.png"
  t.draw()
  let first = ground()
  t.run_for(composer_sample_ms)
  let mid = ground()
  assert_true((first - before).abs() < 1.0, msg="the composer's ground jumped when the video's picture appeared")
  assert_true((mid - before).abs() > 1.0, msg="the composer's ground did not move with the video's picture")
}

///|
test "a quote appears in place when motion is reduced" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.set_reduce_motion(true)
  t.draw()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": quote_passage, "ts": "ts8" })
  t.draw()
  assert_true(quote_ground(t).1 >= composer_glass(t).1, msg="the quote did not appear in the composer")
}
