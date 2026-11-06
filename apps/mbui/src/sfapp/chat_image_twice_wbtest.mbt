// One file placed twice in a message's words: two images in its row, each its own showing. Pressed, the preview flies
// out of the one pressed (it alone hidden meanwhile) and back into it; so too when, the preview open, the message
// shows it once more, or tells its file kept at another path.

///|
/// A chat whose last message places one picture twice in a row; the one at `which` (0 the first) pressed; once the
/// preview is in, `during` ("third": the message places it a third time; "moved": its file told kept at another path;
/// "fewer": placed three times, the message places it twice, the showing pressed gone if it was the third; "":
/// nothing); then the
/// preview closed: what the ones beside it were asked by, where the preview flies from and back
/// to (by the showing whose rect it is, in the order they are drawn), and which showings are drawn halfway out,
/// halfway back and after.
fn twice_pressed(which : Int, during? : String = "") -> String raise {
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  // (0 as it was; 1 placed twice (three times for "fewer"); 2 as `during` says)
  let told = @signals.signal(0)
  let img : Json = ["img", { "src": "row-a.png" }]
  let words = fn() {
    if (told.get() == 2 && during == "third") || (told.get() == 1 && during == "fewer") {
      "![甲](row-a.png)![甲再一次](row-a.png)![甲第三次](row-a.png)"
    } else {
      "![甲](row-a.png)![甲再一次](row-a.png)"
    }
  }
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    { ..base, images,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        if name != "chat" || told.get() == 0 {
          return got
        }
        guard got.value is Some(value) else { return got }
        let path = if told.get() == 2 && during == "moved" { "work/s-c1/kept/row-a.png" } else { "work/s-c1/row-a.png" }
        let files : Array[Json] = [{ "name": "row-a.png", "path": path, "owner": "s-c1", "width": 640, "height": 480 }]
        { ..got, version: got.version + told.get(), value: Some(with_chat_message(value, 129.0, [
          ("text", Json::string(words())), ("placed", ["row-a.png"]), ("attachments", Json::array(files)),
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
  @sf.markdown_read.val = Some(fn(said, done) {
    let n = if said.contains("第三次") { 3 } else if said.contains("再一次") { 2 } else { 1 }
    done(if said.has_prefix("![甲](row-a.png)") { Some([["p", Json::array(Array::make(n, img))]]) } else { None })
  })
  told.set(1)
  t.run_for(@ui.move_most_ms)
  let near = fn(a : Double, b : Double) { (a - b).abs() < 0.5 }
  // (the showings as drawn now, in order)
  let rects = fn() {
    let shown = t.semantics().filter(fn(s) { s.role == Button && s.label.contains("row-a.png") })
    shown.sort_by(fn(a, b) { if near(a.rect.1, b.rect.1) { a.rect.0.compare(b.rect.0) } else { a.rect.1.compare(b.rect.1) } })
    shown.map(fn(s) { s.rect })
  }
  assert_eq(rects().length(), if during == "fewer" { 3 } else { 2 }, msg="\{rects()}")
  let at = fn(x : Double, y : Double, w : Double, h : Double) -> String {
    let mut found = "elsewhere"
    for i, r in rects() {
      if near(r.0, x) && near(r.1, y) && near(r.2, w) && near(r.3, h) {
        found = i.to_string()
      }
    }
    found
  }
  // (which showings are drawn where they are)
  let drawn = fn() -> String {
    rects()
    .map(fn(r) {
      t.drawn_images().any(fn(i) { i[8] > 0.5 && near(i[0], r.0) && near(i[1], r.1) && near(i[2], r.2) && near(i[3], r.3) })
    })
    .to_string()
  }
  let from_to = fn(v : Viewer) {
    match thumb_of(t.ctx(), v.thumb_id()) {
      Some(th) => at(th.x, th.y, th.w, th.h)
      None => "none"
    }
  }
  @sfbase.near_asked.clear()
  let pressed = rects()[which]
  t.tap(pressed.0 + pressed.2 / 2.0, pressed.1 + pressed.3 / 2.0)
  guard viewer.get() is Some(v) else { fail("pressed, nothing opened") }
  t.frame()
  // (the ones beside it asked as the core counts its message's files: the file once, whichever showing)
  let asked : Array[String] = []
  @sfbase.near_asked.each(fn(_, p) {
    let a = @sfbase.text(Some(Json::object(p)), "at")
    asked.push(a.view(start_offset=a.rev_find("/").unwrap_or(0)).to_string())
  })
  let from = from_to(v)
  t.run_for(@ui.move_most_ms / 2.0)
  let out_half = drawn()
  t.run_for(@ui.move_most_ms * 1.5)
  let mut changed = ""
  if during != "" {
    told.set(2)
    t.frames_owed()
    t.run_for(@ui.move_most_ms)
    changed = " \{during}: open on \{viewer.get().map(fn(v) { v.file.path })}, drawn \{drawn()};"
  }
  let v = viewer.get().unwrap()
  v.shut(t.ctx())
  t.run_for(@ui.move_most_ms / 2.0)
  let back_half = drawn()
  let back_to = from_to(v)
  t.run_for(@ui.move_most_ms * 1.5)
  let after = drawn()
  viewer.set(None)
  @sf.markdown_read.val = None
  "pressed \{which}: asked beside \{asked}, flies from \{from}, halfway out drawn \{out_half};\{changed} back to \{back_to}, halfway back drawn \{back_half}; then \{after}"
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

///|
test "one picture placed twice, the preview open: shown a third time, or its file kept elsewhere, it flies back into the one pressed" {
  inspect(
    [twice_pressed(0, during="third"), twice_pressed(0, during="moved")].join("\n"),
    content=(
      #|pressed 0: asked beside [/f], flies from 0, halfway out drawn [false, true]; third: open on Some(work/s-c1/row-a.png), drawn [true, true, true]; back to 0, halfway back drawn [false, true, true]; then [true, true, true]
      #|pressed 0: asked beside [/f], flies from 0, halfway out drawn [false, true]; moved: open on Some(work/s-c1/row-a.png), drawn [true, true]; back to 0, halfway back drawn [false, true]; then [true, true]
    ),
  )
}

///|
test "one picture placed three times, the preview open on the third: the message places it twice, it flies back into one left" {
  inspect(
    twice_pressed(2, during="fewer"),
    content="pressed 2: asked beside [/f], flies from 2, halfway out drawn [true, true, false]; fewer: open on Some(work/s-c1/row-a.png), drawn [true, true]; back to 0, halfway back drawn [false, true]; then [true, true]",
  )
}
