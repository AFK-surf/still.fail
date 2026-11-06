// Two images sent from here, one opened while they go up: the preview asks for the ones beside it by its upload's path,
// and the core tells them, going up or up (client/core-ts placed.ts near(), by its upload): one going up by its upload's
// path, on no station yet, its picture the one picked here. The preview open on it steps there and back, going up and
// once up.

///|
test "an image opened while it goes up: the ones beside it, going up and once up, the preview open on it stepping there and back" {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let up = @signals.signal(false)
  let asked : Array[String] = []
  let src : Ref[Source?] = Ref(None)
  // (each its own picture, as big as it is: shot wide, next upright; what is fetched of each said)
  let shot_png = @sffixture.fixture_png(600, 400)
  let next_png = @sffixture.fixture_png(400, 640)
  let fetched : Array[String] = []
  let file = fn(name : String, path : String) -> Json {
    { "name": name, "path": path, "owner": "s-c1", "width": 600, "height": 400 }
  }
  // (each as the core has it: going up, by its upload on no station; up, where its station keeps it)
  let sent = fn(name : String, id : String, w : Int, h : Int) -> Json {
    if up.get() {
      { "name": name, "path": "work/s-c1/uploads/" + name, "owner": "s-c1", "upload": id, "width": w, "height": h }
    } else {
      { "name": name, "path": "upload:" + id, "upload": id, "width": w, "height": h }
    }
  }
  let shot = fn() { sent("shot.png", "u1", 600, 400) }
  let next = fn() { sent("next.png", "u2", 400, 640) }
  // (the pictures picked here, as big as they are)
  @sfbase.sent_pictures["upload\u{1}u1"] = "mem:near-upload/picked-shot"
  @sfbase.sent_pictures["upload\u{1}u2"] = "mem:near-upload/picked-next"
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    let s = { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        match name {
          "chat" => {
            guard got.value is Some(value) else { return got }
            // (its message: one image sent from here, going up, then up where its station keeps it)
            { ..got, version: got.version + (if up.get() { 2 } else { 1 }), value: Some(with_chat_message(value, 129.0, [
              ("text", Json::string("")), ("attachments", Json::array([shot(), next()])),
            ])) }
          }
          "imageNear" => {
            let path = match params.get("path") {
              Some(String(p)) => p
              _ => ""
            }
            asked.push(path)
            // (as the core tells it: going up, none beside it; once up, by its upload's path, those beside it)
            let near : Json = if path == "upload:u1" || path == "work/s-c1/uploads/shot.png" {
              { "before": file("before.png", "work/s-c1/before.png"), "after": next(), "index": 1, "count": 3 }
            } else if path == "upload:u2" || path == "work/s-c1/uploads/next.png" {
              { "before": shot(), "index": 2, "count": 3 }
            } else {
              { "count": 1 }
            }
            { ..got, version: got.version + (if up.get() { 2 } else { 1 }), value: Some(near) }
          }
          _ => got
        }
      },
      file: fn(station, owner, name) {
        images.get(station, @sfbase.file_image_id(station, owner, name), "mem:near-upload/" + name, fn(_, done) {
          fetched.push(name)
          let bytes = if name == "next.png" { next_png } else if name == "shot.png" { shot_png } else { fixture_file_png("many-0.png") }
          done(Ok((Json::object({}), Some(bytes))))
        })
      },
    }
    src.val = Some(s)
    s
  })
  t.add_image("mem:near-upload/shot.png", 600, 400)
  t.add_image("mem:near-upload/next.png", 400, 640)
  t.add_image("mem:near-upload/picked-shot", 600, 400)
  t.add_image("mem:near-upload/picked-next", 400, 640)
  t.check_looks(false)
  // (the preview's picture whole on its stage: of a proportion, the stage's width (the window's but its margins, 366);
  // the chat's under it no wider than its column, 358)
  let staged = fn(ratio : Double) {
    t.drawn_images().filter(fn(i) { i[8] > 0.5 && (i[3] / i[2] - ratio).abs() < 0.01 && i[2] > 362.0 }).length() > 0
  }
  let decoded = fn(b : Bytes) { t.image_loads().any(fn(l) { l.0 == "bytes:\{b.length()}" }) }
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  let shot_button = t.semantics().filter(fn(s) { s.role == Button && s.label.contains("shot.png") })
  assert_eq(shot_button.length(), 1, msg="\{shot_button.map(fn(s) { s.label })}")
  let (x, y, w, h) = shot_button[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  guard viewer.get() is Some(v) else { fail("the image going up opened nothing") }
  assert_eq(v.file.path, "upload:u1")
  // (a swipe to the next, and back: by `path`, what the preview shows now; on the stage, its picture whole)
  let step = fn(to : Double, path : String, ratio : Double, gone : Double) raise {
    t.drag(200.0 - to, 422.0, 200.0 + to, 422.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(viewer.get().map(fn(v) { v.file.path }), Some(path), msg="asked \{asked}")
    assert_true(staged(ratio), msg="\{path} on the stage: \{t.drawn_images()}")
    assert_true(!staged(gone), msg="the other gone from the stage: \{t.drawn_images()}")
  }
  // (going up: the one going up with it beside it, its picture the one picked here)
  assert_true(v.near(src.val.unwrap()) is (Some(_), Some(_)), msg="asked \{asked}")
  step(-100.0, "upload:u2", 640.0 / 400.0, 400.0 / 600.0)
  step(100.0, "upload:u1", 400.0 / 600.0, 640.0 / 400.0)
  // (up: the preview open on it, still by its upload's path, told those beside it where their station keeps them)
  up.set(true)
  t.frames_owed()
  assert_true(viewer.get().unwrap().near(src.val.unwrap()) is (Some(_), Some(_)), msg="asked \{asked}")
  step(-100.0, "work/s-c1/uploads/next.png", 640.0 / 400.0, 400.0 / 600.0)
  assert_true(fetched.contains("next.png") && decoded(next_png), msg="fetched \{fetched}")
  step(100.0, "work/s-c1/uploads/shot.png", 400.0 / 600.0, 640.0 / 400.0)
  viewer.set(None)
  @sfbase.sent_pictures.clear()
}
