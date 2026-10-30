// A chat's picture that could not be had (sfbase's chat_images.mbt): for want of its station, said so and asked again
// when pressed, when its chat comes into view again, when its station is reached again; the station having none, not.

///|
/// What the box says (加载失败，点按重试, 暂时无法预览), as the words' tables in force say it.
fn load_again() -> String {
  @sf.t("web-main.file.loadAgain")
}

///|
fn no_preview() -> String {
  @sf.t("web-main.file.noPreview")
}

///|
/// A message with picture line.png (800 × 600), its picture asked through `images`, each asking answered by `answer` (by how many
/// times it was asked: from 1), counted in `asked`.
fn image_tester(images : @sfbase.ChatImages, asked : Ref[Int], answer : (Int) -> Result[(Json, Bytes?), Json]) -> @ui.Tester {
  image_tester_asking(images, fn(_, done) {
    asked.val += 1
    done(answer(asked.val))
  })
}

///|
/// The same, its picture asked by `ask` (told how far it has come, then its answer, when the test says).
fn image_tester_asking(
  images : @sfbase.ChatImages,
  ask : ((Json) -> Unit, (Result[(Json, Bytes?), Json]) -> Unit) -> Unit,
) -> @ui.Tester {
  reset()
  let src : Source = {
    ..fixture("chat"),
    file: fn(station, key, name) { images.get(station, @sfbase.file_image_id(station, key, name), "mem:test/" + name, ask) },
    images,
  }
  let m = message_of({
    "seq": 3,
    "ts": "3",
    "authorKind": "person",
    "author": "Mia",
    "text": "",
    "attachments": [attachment_json({ ..strip("line.png"), width: 800.0, height: 600.0 }, "s-c1")],
  })
  @ui.Tester::new(
    fn(c) {
      let here : @sfpages.MessageHere = {
        station: "ws1/st1",
        session: "s-c1",
        view: chat_view_made(Json::object({})),
        go: None,
        inline: true,
        gutter: 0.0,
        list: None,
        core: None,
      }
      @sfpages.message_row(c, src, here, m)
    },
    w=760.0,
    h=600.0,
  )
}

///|
test "a chat's picture its station could not be reached for: 加载失败，点按重试, asked again when pressed" {
  let images = @sfbase.ChatImages::new()
  let asked = Ref::new(0)
  let t = image_tester(images, asked, fn(n) {
    if n == 1 {
      Err({ "code": "mesh", "message": "unreachable" })
    } else {
      Ok((Json::object({}), Some(png_head())))
    }
  })
  t.draw()
  t.draw()
  assert_eq(asked.val, 1)
  assert_true(t.find(load_again()) is Some(_))
  assert_true(t.find(no_preview()) is None)
  t.tap_text(load_again())
  t.draw()
  t.draw()
  assert_eq(asked.val, 2)
  assert_true(t.find(load_again()) is None)
}

///|
test "a chat's picture its station has none of: 暂时无法预览, not asked again" {
  let images = @sfbase.ChatImages::new()
  let asked = Ref::new(0)
  let t = image_tester(images, asked, fn(_) { Err({ "code": "http_404", "message": "not found", "status": 404 }) })
  t.draw()
  t.draw()
  assert_true(t.find(no_preview()) is Some(_))
  assert_true(t.find(load_again()) is None)
  images.again("ws1/st1")
  images.seen("ws1/st1", false)
  images.seen("ws1/st1", true)
  t.draw()
  t.draw()
  assert_eq(asked.val, 1)
}

///|
test "the pictures that failed for want of a station asked again once it is reached again, not while it stays so" {
  let images = @sfbase.ChatImages::new()
  let asked = Ref::new(0)
  let t = image_tester(images, asked, fn(_) { Err({ "code": "timeout", "message": "slow" }) })
  t.draw()
  t.draw()
  assert_eq(asked.val, 1)
  // reached all along: nothing asked again
  images.seen("ws1/st1", true)
  t.draw()
  assert_eq(asked.val, 1)
  // away, then reached again: asked again
  images.seen("ws1/st1", false)
  t.draw()
  assert_eq(asked.val, 1)
  images.seen("ws1/st1", true)
  t.draw()
  t.draw()
  assert_eq(asked.val, 2)
}

///|
test "a chat's pictures that failed for want of its station asked again as the chat is opened again" {
  reset()
  let images = @sfbase.ChatImages::new()
  let asked = Ref::new(0)
  let src : Source = {
    ..fixture("chat"),
    file: fn(station, key, name) {
      images.get(station, @sfbase.file_image_id(station, key, name), "mem:test/" + name, fn(_, done) {
        asked.val += 1
        done(Err({ "code": "mesh", "message": "unreachable" }))
      })
    },
    images,
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // (tall enough for the whole chat, its pictures with it)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=6000.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let first = asked.val
  assert_true(first > 0)
  // drawn on: not asked again
  t.draw()
  t.draw()
  assert_eq(asked.val, first)
  // left, and opened again: asked again
  t.back()
  t.run_for(@ui.move_most_ms)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.run_for(@ui.move_most_ms)
  assert_true(asked.val > first, msg="asked \{asked.val} times, \{first} the first time")
}

///|
test "a chat's picture slow to come: how far it has come at its foot once it has waited 300 ms, gone once it is here" {
  let images = @sfbase.ChatImages::new()
  let heard : Ref[(Json) -> Unit] = Ref(fn(_) {  })
  let answer : Ref[(Result[(Json, Bytes?), Json]) -> Unit] = Ref(fn(_) {  })
  let t = image_tester_asking(images, fn(h, done) {
    heard.val = h
    answer.val = done
  })
  t.draw()
  (heard.val)({ "loaded": 350.0, "total": 1000.0 })
  t.run_for(@sfpages.coming_after_ms / 2.0)
  // (one that comes at once never flashes it)
  assert_true(t.find("35%") is None)
  t.run_for(@sfpages.coming_after_ms + @sfpages.coming_in_ms)
  assert_true(t.find("35%") is Some(_))
  // (its pill in the picture's corner concentric with it: 8 in, its ends were rounder than the corner left room for)
  assert_eq(t.corner_faults(), [])
  (heard.val)({ "loaded": 800.0, "total": 1000.0 })
  t.draw()
  assert_true(t.find("80%") is Some(_))
  (answer.val)(Ok((Json::object({}), Some(png_head()))))
  t.draw()
  t.draw()
  assert_true(t.find("80%") is None)
}

///|
test "a chat's picture slow to come whose size is not known: the bytes here so far" {
  let images = @sfbase.ChatImages::new()
  let heard : Ref[(Json) -> Unit] = Ref(fn(_) {  })
  let t = image_tester_asking(images, fn(h, _) { heard.val = h })
  t.draw()
  (heard.val)({ "loaded": 300000.0 })
  t.run_for(@sfpages.coming_after_ms + @sfpages.coming_in_ms)
  assert_true(t.find(@sf.file_size(300000.0)) is Some(_))
  assert_true(t.find("%") is None)
}

///|
test "a chat's picture slow to come: the whole of what stands in for it breathing, no pill until it is heard of, still once it is here" {
  let images = @sfbase.ChatImages::new()
  let answer : Ref[(Result[(Json, Bytes?), Json]) -> Unit] = Ref(fn(_) {  })
  let t = image_tester_asking(images, fn(_, done) { answer.val = done })
  t.draw()
  t.run_for(@sfpages.coming_after_ms + @sfpages.coming_in_ms)
  let shade = match @sf.video_shade {
    Data(v) => v
    _ => abort("video_shade is a colour")
  }
  let breathing = fn() { t.cycles().filter(fn(s) { s.has_prefix("\{@sf.breath_ms.to_int()} ms") }).length() }
  // (nothing heard of it: no spinner over it in a pill of its own, which looked like a switch; it breathes)
  assert_eq(t.drawn_rect_corners().filter(fn(r) { r.4 == shade }).length(), 0)
  assert_eq(breathing(), 1)
  (answer.val)(Ok((Json::object({}), Some(png_head()))))
  // (the frame it is here on, then back to whole over dur_ms)
  t.draw()
  t.run_for(@sf.dur_ms)
  t.draw()
  assert_eq(breathing(), 0)
}
