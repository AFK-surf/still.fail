// A message's images in a row are each made once. One whose file the message tells again (its own size known, kept
// at another path) is the same image, drawn at its proportion now and opened as the file is now.

///|
test "an image in a row whose file its message tells again is the same image, drawn at its proportion now and opened as it is now" {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let told = @signals.signal(0)
  let text = "![甲](row-a.png)![乙](row-b.png)"
  let tree : Json = [["p", [["img", { "src": "row-a.png" }], ["img", { "src": "row-b.png" }]]]]
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" { return got }
        let version = told.get()
        guard version > 0 && got.value is Some(value) else { return got }
        // (乙 first as it was sent, wide; then told again upright, kept at another path)
        let b : Json = if version == 1 {
          { "name": "row-b.png", "path": "work/s-c1/row-b.png", "owner": "s-c1", "width": 640, "height": 480 }
        } else {
          { "name": "row-b.png", "path": "work/s-c1/kept/row-b.png", "owner": "s-c1", "width": 480, "height": 640 }
        }
        let files : Array[Json] = [
          { "name": "row-a.png", "path": "work/s-c1/row-a.png", "owner": "s-c1", "width": 640, "height": 480 },
          b,
        ]
        { ..got, version: got.version + version, value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(text)), ("placed", ["row-a.png", "row-b.png"]), ("attachments", Json::array(files)),
        ])) }
      },
      file: fn(station, owner, name) {
        images.get(station, @sfbase.file_image_id(station, owner, name), "mem:row-told/" + name, fn(_, done) {
          done(Ok((Json::object({}), Some(fixture_file_png("many-0.png")))))
        })
      },
    }
  })
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  @sf.markdown_read.val = Some(fn(words, done) { done(if words == text { Some(tree) } else { None }) })
  told.set(1)
  t.run_for(@ui.move_most_ms)
  let image_of = fn(name : String) raise {
    let found = t.semantics().filter(fn(s) { s.role == Button && s.label.contains(name) })
    assert_eq(found.length(), 1, msg="\{name}: \{found.map(fn(s) { s.label })}")
    found[0]
  }
  let a = image_of("row-a.png")
  let b = image_of("row-b.png")
  assert_true((b.rect.2 / b.rect.3 - 640.0 / 480.0).abs() < 0.02, msg="乙 drawn wide: \{b.rect}")
  told.set(2)
  t.frames_owed()
  @sf.markdown_read.val = None
  let a_now = image_of("row-a.png")
  let b_now = image_of("row-b.png")
  assert_eq(b_now.id, b.id, msg="乙 the same image")
  assert_eq(a_now.id, a.id, msg="甲 the same image")
  assert_true((b_now.rect.2 / b_now.rect.3 - 480.0 / 640.0).abs() < 0.02, msg="乙 drawn upright: \{b.rect} then \{b_now.rect}")
  // (pressed, it opens the file where it is kept now)
  t.tap(b_now.rect.0 + b_now.rect.2 / 2.0, b_now.rect.1 + b_now.rect.3 / 2.0)
  let opened = viewer.get().map(fn(v) { v.file.path })
  viewer.set(None)
  assert_eq(opened, Some("work/s-c1/kept/row-b.png"))
}
