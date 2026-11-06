// An image sent from here, opened while it goes up: the preview asks for the ones beside it by its upload's path, and
// the core tells none while it goes up and those beside it once up (client/core-ts placed.ts near(), by its upload).
// The preview open on it shows the way to them as soon as it is told, steps there and back.

///|
test "an image opened while it goes up: none beside it, then once up the ones beside it, the preview open on it stepping there and back" {
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
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    let s = { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        match name {
          "chat" => {
            guard got.value is Some(value) else { return got }
            // (its message: one image sent from here, going up, then up where its station keeps it)
            let shot : Json = if up.get() {
              { "name": "shot.png", "path": "work/s-c1/uploads/shot.png", "owner": "s-c1", "upload": "u1", "width": 600, "height": 400 }
            } else {
              { "name": "shot.png", "path": "upload:u1", "upload": "u1", "width": 600, "height": 400 }
            }
            { ..got, version: got.version + (if up.get() { 2 } else { 1 }), value: Some(with_chat_message(value, 129.0, [
              ("text", Json::string("")), ("attachments", Json::array([shot])),
            ])) }
          }
          "imageNear" => {
            let path = match params.get("path") {
              Some(String(p)) => p
              _ => ""
            }
            asked.push(path)
            // (as the core tells it: going up, none beside it; once up, by its upload's path, those beside it)
            let near : Json = if up.get() && path == "upload:u1" {
              {
                "before": file("before.png", "work/s-c1/before.png"),
                "after": { "name": "next.png", "path": "work/s-c1/next.png", "owner": "s-c1", "width": 400, "height": 640 },
                "index": 1,
                "count": 3,
              }
            } else if path == "work/s-c1/next.png" {
              { "before": { "name": "shot.png", "path": "work/s-c1/uploads/shot.png", "owner": "s-c1", "upload": "u1", "width": 600, "height": 400 }, "index": 2, "count": 3 }
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
  t.check_looks(false)
  // (the preview's picture whole on its stage: of a proportion, and big)
  let staged = fn(ratio : Double) {
    t.drawn_images().filter(fn(i) { i[8] > 0.5 && (i[3] / i[2] - ratio).abs() < 0.01 && i[2] * i[3] > 200.0 * 200.0 }).length() > 0
  }
  let decoded = fn(b : Bytes) { t.image_loads().any(fn(l) { l.0 == "bytes:\{b.length()}" }) }
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  let shot = t.semantics().filter(fn(s) { s.role == Button && s.label.contains("shot.png") })
  assert_eq(shot.length(), 1, msg="\{shot.map(fn(s) { s.label })}")
  let (x, y, w, h) = shot[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  guard viewer.get() is Some(v) else { fail("the image going up opened nothing") }
  assert_eq(v.file.path, "upload:u1")
  // (going up: none beside it, nothing to step to)
  assert_true(v.near(src.val.unwrap()) is (None, None), msg="asked \{asked}")
  t.drag(300.0, 422.0, 100.0, 422.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(viewer.get().map(fn(v) { v.file.name }), Some("shot.png"))
  // (up: the preview open on it, still by its upload's path, told those beside it)
  up.set(true)
  t.frames_owed()
  assert_true(v.near(src.val.unwrap()) is (Some(_), Some(_)), msg="asked \{asked}")
  // (a swipe to the next, and back)
  t.drag(300.0, 422.0, 100.0, 422.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(viewer.get().map(fn(v) { v.file.path }), Some("work/s-c1/next.png"))
  assert_true(fetched.contains("next.png") && decoded(next_png), msg="fetched \{fetched}")
  assert_true(staged(640.0 / 400.0), msg="next on the stage: \{t.drawn_images()}")
  t.drag(100.0, 422.0, 300.0, 422.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(viewer.get().map(fn(v) { v.file.path }), Some("work/s-c1/uploads/shot.png"))
  assert_true(staged(400.0 / 600.0), msg="shot on the stage again: \{t.drawn_images()}")
  assert_true(!staged(640.0 / 400.0), msg="next gone from the stage: \{t.drawn_images()}")
  viewer.set(None)
}
