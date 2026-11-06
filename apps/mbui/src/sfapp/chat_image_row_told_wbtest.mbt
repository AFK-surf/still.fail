// A message's images in a row are each made once. One whose file the message tells again (its own size known, kept
// at another path) is the same image, drawn at its proportion now and opened as the file is now.

///|
test "an image in a row whose file its message tells again is the same image, drawn at its proportion now, opened as it is now, flying out of it and back into it" {
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
  // (the pictures as big as their files are: 乙 upright, as it is told last)
  t.add_image("mem:row-told/row-a.png", 640, 480)
  t.add_image("mem:row-told/row-b.png", 480, 640)
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
  // (pressed, it opens the file where it is kept now from this image, its thumbnail under the file now and none under
  // the file as it was: it flies out of it, the image hidden while the preview is its picture; closed, it flies back
  // into it, lands where it is drawn and the image is shown again, the same image all along)
  let drawn_b = (b_now.rect.0, b_now.rect.1, b_now.rect.2, b_now.rect.3)
  t.tap(b_now.rect.0 + b_now.rect.2 / 2.0, b_now.rect.1 + b_now.rect.3 / 2.0)
  guard viewer.get() is Some(v) else { fail("乙 opened nothing") }
  assert_eq(v.file.path, "work/s-c1/kept/row-b.png")
  let now_id = v.thumb_id()
  let was_id = now_id.replace(old="work/s-c1/kept/row-b.png", new="work/s-c1/row-b.png")
  assert_true(was_id != now_id, msg=now_id)
  let th = match thumb_of(t.ctx(), now_id) {
    Some(th) => th
    None => fail("no thumbnail of 乙 where it is kept now")
  }
  assert_true(
    (th.x - drawn_b.0).abs() < 0.5 && (th.y - drawn_b.1).abs() < 0.5 && (th.w - drawn_b.2).abs() < 0.5 &&
    (th.h - drawn_b.3).abs() < 0.5,
    msg="乙's thumbnail at \{(th.x, th.y, th.w, th.h)}, drawn at \{drawn_b}",
  )
  assert_true(thumb_of(t.ctx(), was_id) is None && !pv_thumbs.contains(was_id), msg="乙's thumbnail where it was let go")
  assert_true(v.flies && !v.fly_back, msg="the preview flies out")
  assert_eq(pv_hidden.get(), now_id, msg="乙 hidden while the preview is its picture")
  // (halfway out: its picture, upright, between 乙 and its place on the stage)
  t.run_for(@ui.move_most_ms / 2.0)
  let to = v.zoom.rect().unwrap()
  let on_way = t
    .drawn_images()
    .filter(fn(i) { i[8] > 0.5 && i[2] > th.w + 0.5 && i[2] < to.2 - 0.5 && (i[3] / i[2] - to.3 / to.2).abs() < 0.01 })
  assert_eq(on_way.length(), 1, msg="halfway out from \{(th.x, th.y, th.w, th.h)} to \{to}: \{on_way}")
  let (cx, cy) = (on_way[0][0] + on_way[0][2] / 2.0, on_way[0][1] + on_way[0][3] / 2.0)
  assert_true(cx > dmin(th.x + th.w / 2.0, to.0 + to.2 / 2.0) - 0.5 && cx < dmax(th.x + th.w / 2.0, to.0 + to.2 / 2.0) + 0.5)
  assert_true(cy > dmin(th.y + th.h / 2.0, to.1 + to.3 / 2.0) - 0.5 && cy < dmax(th.y + th.h / 2.0, to.1 + to.3 / 2.0) + 0.5)
  t.run_for(@ui.move_most_ms)
  assert_true(drawn_at(t, to), msg="in: \{to}")
  // (in, the stage over the chat: 乙 shown under it again, as for any picture)
  assert_eq(pv_hidden.get(), "")
  // (closed: back into 乙 where it is drawn now, then 乙 itself again)
  t.back()
  assert_true(v.fly_back, msg="the preview flies back")
  assert_eq(pv_hidden.get(), now_id, msg="乙 hidden while the preview flies back into it")
  t.run_for(@ui.move_most_ms)
  // (where 乙 is now: the chat may have moved under the preview)
  let home = image_of("row-b.png")
  let home_r = (home.rect.0, home.rect.1, home.rect.2, home.rect.3)
  assert_true(drawn_at(t, home_r), msg="landed: \{home_r} \{t.drawn_images()}")
  assert_true(pv_leaving.get() is None)
  assert_eq(pv_hidden.get(), "")
  assert_true(viewer.get() is None)
  t.draw()
  assert_eq(home.id, b.id, msg="乙 the same image after the preview")
  assert_true(drawn_at(t, home_r), msg="乙 shown again: \{t.drawn_images()}")
}
