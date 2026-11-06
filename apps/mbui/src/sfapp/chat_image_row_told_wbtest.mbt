// A message's images in a row are each made once. One whose file the message tells again (its own size known, kept
// at another path) is the same image, drawn at its proportion now and opened as the file is now.

///|
/// A chat whose last message places two images in a row, 甲 and 乙, 乙 told first wide at one path, then again
/// upright at another (`again`; else when `told` is set to 2): the tester, an image's node by its file, 甲's and 乙's
/// as first drawn, and what is told.
fn row_told(again? : Bool = true) -> (@ui.Tester, (String) -> @ui.SemNode raise, @ui.SemNode, @ui.SemNode, @signals.Signal[Int]) raise {
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
  if again {
    told.set(2)
    t.frames_owed()
  }
  @sf.markdown_read.val = None
  (t, image_of, a, b, told)
}

///|
test "an image in a row whose file its message tells again is the same image, drawn at its proportion now" {
  let (_, image_of, a, b, _) = row_told()
  assert_true((b.rect.2 / b.rect.3 - 640.0 / 480.0).abs() < 0.02, msg="乙 drawn wide: \{b.rect}")
  let a_now = image_of("row-a.png")
  let b_now = image_of("row-b.png")
  assert_eq(b_now.id, b.id, msg="乙 the same image")
  assert_eq(a_now.id, a.id, msg="甲 the same image")
  assert_true((b_now.rect.2 / b_now.rect.3 - 480.0 / 640.0).abs() < 0.02, msg="乙 drawn upright: \{b.rect} then \{b_now.rect}")
}

///|
/// 乙 (row_told's) pressed and its preview closed when it is in, each of `frames` (ms from the press) drawn and looked
/// at on the way: what is seen at the moments said (the preview's picture, 乙 hidden or not, where 乙 is), the same
/// whichever frames are drawn between.
fn row_told_preview(frames : Array[Double]) -> Array[String] raise {
  let (t, image_of, _, b, _) = row_told()
  let b_now = image_of("row-b.png")
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let rect = fn(r : (Double, Double, Double, Double)) { (r2(r.0), r2(r.1), r2(r.2), r2(r.3)) }
  // (the upright pictures drawn, 乙's proportion: 乙 itself, or the preview's)
  let upright = fn() {
    t.drawn_images().filter(fn(i) { i[8] > 0.5 && (i[3] / i[2] - 640.0 / 480.0).abs() < 0.01 }).map(fn(i) { rect((i[0], i[1], i[2], i[3])) })
  }
  // (pressed, it opens the file where it is kept now from this image, its thumbnail under the file now and none
  // under the file as it was)
  let drawn_b = (b_now.rect.0, b_now.rect.1, b_now.rect.2, b_now.rect.3)
  t.tap(b_now.rect.0 + b_now.rect.2 / 2.0, b_now.rect.1 + b_now.rect.3 / 2.0)
  let t0 = t.time()
  guard viewer.get() is Some(v) else { fail("乙 opened nothing") }
  assert_eq(v.file.path, "work/s-c1/kept/row-b.png")
  let now_id = v.thumb_id()
  let was_id = now_id.replace(old="work/s-c1/kept/row-b.png", new="work/s-c1/row-b.png")
  assert_true(was_id != now_id, msg=now_id)
  let th = match thumb_of(t.ctx(), now_id) {
    Some(th) => th
    None => fail("no thumbnail of 乙 where it is kept now")
  }
  assert_eq(rect((th.x, th.y, th.w, th.h)), rect(drawn_b), msg="乙's thumbnail where 乙 is drawn")
  assert_true(thumb_of(t.ctx(), was_id) is None && !pv_thumbs.contains(was_id), msg="乙's thumbnail where it was let go")
  assert_true(v.flies && !v.fly_back, msg="the preview flies out")
  // (each frame: while the preview's picture flies, it alone is drawn of 乙's proportion and 乙 is hidden; once it
  // is in, 乙 shown under the stage again)
  let look = fn(at : String) raise {
    let ups = upright()
    if (v.flies && !v.fly_back) || pv_leaving.get() is Some(_) {
      assert_eq(pv_hidden.get(), now_id, msg="\{at}: 乙 hidden while the preview's picture flies")
      assert_eq(ups.length(), 1, msg="\{at}: \{ups}")
    } else {
      assert_eq(pv_hidden.get(), "", msg="\{at}: 乙 shown")
    }
  }
  let through = fn(from : Double, to : Double) raise {
    for f in frames {
      if f > from && f < to {
        t.frame_at(t0 + f)
        look("\{f} ms")
      }
    }
  }
  // (the one picture of 乙's proportion drawn, between `a` and `b`: its width between theirs, its middle between
  // theirs)
  let between = fn(at : String, a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) raise {
    let ups = t.drawn_images().filter(fn(i) { i[8] > 0.5 && (i[3] / i[2] - 640.0 / 480.0).abs() < 0.01 })
    assert_eq(ups.length(), 1, msg="\{at}: \{ups.map(fn(i) { (i[0], i[1], i[2], i[3]) })}")
    let i = ups[0]
    let within = fn(v : Double, p : Double, q : Double) { v > dmin(p, q) + 0.5 && v < dmax(p, q) - 0.5 }
    assert_true(
      within(i[2], a.2, b.2) && within(i[0] + i[2] / 2.0, a.0 + a.2 / 2.0, b.0 + b.2 / 2.0) &&
      within(i[1] + i[3] / 2.0, a.1 + a.3 / 2.0, b.1 + b.3 / 2.0),
      msg="\{at}: \{(i[0], i[1], i[2], i[3])} not between \{a} and \{b}",
    )
  }
  let seen : Array[String] = []
  let half = @ui.move_most_ms / 2.0
  let open = @ui.move_most_ms * 1.5
  let close = @ui.move_most_ms * 2.0
  let landed = close + @ui.move_most_ms
  look("pressed")
  through(0.0, half)
  t.frame_at(t0 + half)
  look("halfway out")
  let to = v.zoom.rect().unwrap()
  // (halfway out still flying: its picture between 乙 and its place on the stage, in size and in place)
  assert_true(v.flies && !v.fly_back && pv_hidden.get() == now_id, msg="halfway out: not flying")
  between("halfway out", (th.x, th.y, th.w, th.h), to)
  seen.push("halfway out: \{upright()}, hidden \{pv_hidden.get() == now_id}")
  through(half, open)
  t.frame_at(t0 + open)
  look("in")
  assert_true(drawn_at(t, to), msg="in: \{to}")
  seen.push("in: \{rect(to)}, \{upright()}, hidden \{pv_hidden.get() == now_id}")
  through(open, close)
  t.advance(t0 + close - t.time())
  // (closed: back into 乙 where it is drawn then, then 乙 itself again, the same image)
  t.back()
  assert_true(v.fly_back, msg="the preview flies back")
  look("closed")
  through(close, close + half)
  t.frame_at(t0 + close + half)
  look("halfway back")
  // (halfway back still flying: its picture between its place on the stage and where 乙 is)
  let at_b = match thumb_of(t.ctx(), now_id) {
    Some(h) => (h.x, h.y, h.w, h.h)
    None => fail("halfway back: no thumbnail of 乙")
  }
  assert_true(pv_leaving.get() is Some(_) && pv_hidden.get() == now_id, msg="halfway back: not flying")
  between("halfway back", to, at_b)
  seen.push("halfway back: \{upright()}, hidden \{pv_hidden.get() == now_id}")
  through(close + half, landed)
  t.frame_at(t0 + landed)
  look("landed")
  assert_true(pv_leaving.get() is None && viewer.get() is None)
  let home = image_of("row-b.png")
  let home_r = (home.rect.0, home.rect.1, home.rect.2, home.rect.3)
  assert_true(drawn_at(t, home_r), msg="landed: \{home_r} \{t.drawn_images()}")
  assert_eq(home.id, b.id, msg="乙 the same image after the preview")
  seen.push("landed: 乙 \{rect(home_r)} (pressed at \{rect(drawn_b)}), \{upright()}, hidden \{pv_hidden.get() == now_id}")
  // (pressed again, the same file from the same place)
  t.tap(home.rect.0 + home.rect.2 / 2.0, home.rect.1 + home.rect.3 / 2.0)
  let again = viewer.get().map(fn(v) { (v.file.path, v.thumb_id() == now_id) })
  viewer.set(None)
  pv_hidden.set("")
  seen.push("pressed again: \{again}")
  seen
}

///|
test "an image told again at another path, pressed: the preview flies out of it and back into it where it is, the image hidden while it flies, the same image after; the same at 60 Hz, 120 Hz or in one jump" {
  let hz = fn(period : Double) {
    Array::makei(((@ui.move_most_ms * 3.0) / period).to_int(), fn(i) { (i + 1).to_double() * period })
  }
  let one = row_told_preview([])
  let at60 = row_told_preview(hz(1000.0 / 60.0))
  let at120 = row_told_preview(hz(1000.0 / 120.0))
  assert_eq(at60, one)
  assert_eq(at120, one)
}

///|
/// The pictures drawn whole between `a` and `b`: their width between theirs, their middle between theirs either way.
fn drawn_between(
  t : @ui.Tester,
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
) -> Array[(Double, Double, Double, Double)] {
  let within = fn(v : Double, p : Double, q : Double) { v > dmin(p, q) + 0.5 && v < dmax(p, q) - 0.5 }
  t
  .drawn_images()
  .filter(fn(i) {
    i[8] > 0.5 &&
    within(i[2], a.2, b.2) &&
    within(i[0] + i[2] / 2.0, a.0 + a.2 / 2.0, b.0 + b.2 / 2.0) &&
    within(i[1] + i[3] / 2.0, a.1 + a.3 / 2.0, b.1 + b.3 / 2.0)
  })
  .map(fn(i) { (i[0], i[1], i[2], i[3]) })
}

///|
/// 乙 (row_told's, as first told) pressed, told again at its other path `told_at` ms after (on the way out, or after
/// the preview is closed on its way back), the preview closed when it is in; each of `frames` (ms from the press)
/// drawn and looked at on the way: what is seen at the moments said, the same whichever frames are drawn between.
fn row_told_while_open(told_at : Double, frames : Array[Double]) -> Array[String] raise {
  let (t, image_of, _, b, told) = row_told(again=false)
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let rect = fn(r : (Double, Double, Double, Double)) { (r2(r.0), r2(r.1), r2(r.2), r2(r.3)) }
  t.tap(b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
  let t0 = t.time()
  guard viewer.get() is Some(v) else { fail("乙 opened nothing") }
  assert_eq(v.file.path, "work/s-c1/row-b.png")
  let was_id = v.thumb_id()
  let now_id = was_id.replace(old="work/s-c1/row-b.png", new="work/s-c1/kept/row-b.png")
  let from = match thumb_of(t.ctx(), was_id) {
    Some(th) => (th.x, th.y, th.w, th.h)
    None => fail("no thumbnail of 乙")
  }
  // (the id 乙's thumbnail is under now, and where it is)
  let held = fn() {
    if thumb_of(t.ctx(), now_id) is Some(_) {
      "now"
    } else if thumb_of(t.ctx(), was_id) is Some(_) {
      "was"
    } else {
      "none"
    }
  }
  let held_at = fn() raise {
    match thumb_of(t.ctx(), if held() == "now" { now_id } else { was_id }) {
      Some(th) => (th.x, th.y, th.w, th.h)
      None => fail("no thumbnail of 乙")
    }
  }
  let named = fn(id : String) { if id == now_id { "now" } else if id == was_id { "was" } else { id } }
  // (each frame: while the preview's picture flies out or back, the thumbnail it flies from or to is 乙's and it is
  // the one hidden; else none hidden)
  let look = fn(at : String) raise {
    if (v.flies && !v.fly_back) || pv_leaving.get() is Some(_) {
      assert_eq(named(v.thumb_id()), held(), msg="\{at}: the preview's thumbnail is 乙's")
      assert_eq(named(pv_hidden.get()), held(), msg="\{at}: 乙 hidden while the preview's picture flies")
    } else {
      assert_eq(pv_hidden.get(), "", msg="\{at}: 乙 shown")
    }
  }
  let seen : Array[String] = []
  let last = Ref(0.0)
  // (to `ms` after the press, each of `frames` before it drawn and looked at)
  let reach = fn(ms : Double, at : String) raise {
    for f in frames {
      if f > last.val && f < ms {
        t.frame_at(t0 + f)
        look("\{f} ms")
      }
    }
    t.frame_at(t0 + ms)
    look(at)
    last.val = ms
  }
  let tell = fn() raise {
    reach(told_at, "told at \{told_at}")
    // (its message tells it again, upright where it is kept now)
    told.set(2)
    t.frames_owed()
    look("told again")
    seen.push("told again: thumbnail \{held()}, preview's \{named(v.thumb_id())}, hidden \{named(pv_hidden.get())}")
  }
  let half = @ui.move_most_ms / 2.0
  let open = @ui.move_most_ms * 1.5
  let close = @ui.move_most_ms * 2.0
  let landed = close + @ui.move_most_ms
  look("pressed")
  if told_at < half {
    tell()
  }
  reach(half, "halfway out")
  let to = v.zoom.rect().unwrap()
  // (halfway out still flying: its one picture between where 乙 was pressed and its place on the stage)
  assert_true(v.flies && !v.fly_back, msg="halfway out: not flying")
  let out = drawn_between(t, from, to)
  assert_eq(out.length(), 1, msg="halfway out between \{from} and \{to}: \{out}")
  seen.push("halfway out: \{out.map(rect)}")
  reach(open, "in")
  assert_true(drawn_at(t, to), msg="in: \{to}")
  for f in frames {
    if f > last.val && f < close {
      t.frame_at(t0 + f)
      look("\{f} ms")
    }
  }
  t.advance(t0 + close - t.time())
  last.val = close
  t.back()
  look("closed")
  assert_true(v.fly_back, msg="the preview flies back into 乙, not faded out")
  if told_at > close {
    tell()
  }
  reach(close + half, "halfway back")
  // (halfway back still flying: its one picture between its place on the stage and where 乙 is now)
  let home_at = held_at()
  assert_true(pv_leaving.get() is Some(_), msg="halfway back: not flying")
  let back = drawn_between(t, to, home_at)
  assert_eq(back.length(), 1, msg="halfway back between \{to} and \{home_at}: \{back}")
  seen.push("halfway back: \{back.map(rect)} towards \{held()} \{rect(home_at)}")
  reach(landed, "landed")
  assert_true(pv_leaving.get() is None && viewer.get() is None)
  let home = image_of("row-b.png")
  let home_r = (home.rect.0, home.rect.1, home.rect.2, home.rect.3)
  assert_true(drawn_at(t, home_r), msg="landed: \{home_r} \{t.drawn_images()}")
  assert_eq(home.id, b.id, msg="乙 the same image after the preview")
  seen.push("landed: 乙 \{rect(home_r)}, thumbnail \{held()}, preview's file \{v.file.path}")
  seen
}

///|
test "an image opened, then told again at another path while its preview flies out or back: the preview flies on from it and back into it where it is now, it hidden while the picture flies; the same at 60 Hz, 120 Hz or in one jump" {
  let hz = fn(period : Double) {
    Array::makei(((@ui.move_most_ms * 3.0) / period).to_int(), fn(i) { (i + 1).to_double() * period })
  }
  for told_at in [@ui.move_most_ms / 4.0, @ui.move_most_ms * 2.25] {
    let one = row_told_while_open(told_at, [])
    let at60 = row_told_while_open(told_at, hz(1000.0 / 60.0))
    let at120 = row_told_while_open(told_at, hz(1000.0 / 120.0))
    assert_eq(at60, one, msg="told at \{told_at}")
    assert_eq(at120, one, msg="told at \{told_at}")
  }
}
