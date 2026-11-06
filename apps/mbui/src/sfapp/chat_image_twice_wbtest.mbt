// One file placed twice in a message's words: two images in its row, each its own showing. Pressed, the preview flies
// out of the one pressed (it alone hidden meanwhile) and back into it.

///|
/// A chat whose last message places one picture twice in a row; the one at `which` (0 the first) pressed, its preview
/// closed once in: where the preview flies from and back to (by the showing whose rect it is), and which showings are
/// drawn halfway out and halfway back.
fn twice_pressed(which : Int) -> String raise {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let told = @signals.signal(false)
  let text = "![甲](row-a.png)![甲再一次](row-a.png)"
  let tree : Json = [["p", [["img", { "src": "row-a.png" }], ["img", { "src": "row-a.png" }]]]]
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" || !told.get() {
          return got
        }
        guard got.value is Some(value) else { return got }
        let files : Array[Json] = [{ "name": "row-a.png", "path": "work/s-c1/row-a.png", "owner": "s-c1", "width": 640, "height": 480 }]
        { ..got, version: got.version + 1, value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(text)), ("placed", ["row-a.png"]), ("attachments", Json::array(files)),
        ])) }
      },
      file: fn(station, owner, name) {
        images.get(station, @sfbase.file_image_id(station, owner, name), "mem:twice/" + name, fn(_, done) {
          done(Ok((Json::object({}), Some(fixture_file_png("many-0.png")))))
        })
      },
    }
  })
  t.add_image("mem:twice/row-a.png", 640, 480)
  t.check_looks(false)
  t.run_for(first_page_ms + @ui.move_most_ms + @sfpages.reveal_ms)
  @sf.markdown_read.val = Some(fn(words, done) { done(if words == text { Some(tree) } else { None }) })
  told.set(true)
  t.run_for(@ui.move_most_ms)
  @sf.markdown_read.val = None
  let shown = t.semantics().filter(fn(s) { s.role == Button && s.label.contains("row-a.png") })
  assert_eq(shown.length(), 2, msg="\{shown.map(fn(s) { (s.label, s.rect) })}")
  shown.sort_by(fn(a, b) { a.rect.0.compare(b.rect.0) })
  let rects = shown.map(fn(s) { s.rect })
  let near = fn(a : Double, b : Double) { (a - b).abs() < 0.5 }
  let at = fn(x : Double, y : Double, w : Double, h : Double) -> String {
    let mut found = "elsewhere"
    for i, r in rects {
      if near(r.0, x) && near(r.1, y) && near(r.2, w) && near(r.3, h) {
        found = i.to_string()
      }
    }
    found
  }
  // (which showings are drawn where they are)
  let drawn = fn() -> String {
    let at_rest = rects.map(fn(r) {
      t.drawn_images().any(fn(i) { i[8] > 0.5 && near(i[0], r.0) && near(i[1], r.1) && near(i[2], r.2) && near(i[3], r.3) })
    })
    at_rest.to_string()
  }
  @sfbase.near_asked.clear()
  let pressed = rects[which]
  t.tap(pressed.0 + pressed.2 / 2.0, pressed.1 + pressed.3 / 2.0)
  guard viewer.get() is Some(v) else { fail("pressed, nothing opened") }
  t.frame()
  // (the ones beside it asked as the core counts its message's files: the file once, whichever showing)
  let asked : Array[String] = []
  @sfbase.near_asked.each(fn(_, p) {
    let at = @sfbase.text(Some(Json::object(p)), "at")
    asked.push(at.view(start_offset=at.rev_find("/").unwrap_or(0)).to_string())
  })
  let from = match thumb_of(t.ctx(), v.thumb_id()) {
    Some(th) => at(th.x, th.y, th.w, th.h)
    None => "none"
  }
  t.run_for(@ui.move_most_ms / 2.0)
  let out_half = drawn()
  t.run_for(@ui.move_most_ms * 1.5)
  v.shut(t.ctx())
  t.run_for(@ui.move_most_ms / 2.0)
  let back_half = drawn()
  let back_to = match thumb_of(t.ctx(), v.thumb_id()) {
    Some(th) => at(th.x, th.y, th.w, th.h)
    None => "none"
  }
  t.run_for(@ui.move_most_ms * 1.5)
  let after = drawn()
  viewer.set(None)
  "pressed \{which}: asked beside \{asked}, flies from \{from}, halfway out drawn \{out_half}; back to \{back_to}, halfway back drawn \{back_half}; then \{after}"
}

///|
test "one picture placed twice: the preview flies out of the showing pressed and back into it, it alone hidden" {
  inspect(
    [twice_pressed(0), twice_pressed(1)].join("\n"),
    content=(
      #|pressed 0: asked beside [/f], flies from 0, halfway out drawn [false, true]; back to 0, halfway back drawn [false, true]; then [true, true]
      #|pressed 1: asked beside [/f], flies from 1, halfway out drawn [true, false]; back to 1, halfway back drawn [true, false]; then [true, true]
    ),
  )
}
