// A link's card and a file's peek whose values name pictures (their tokens: the bytes come beside a call's answer,
// @sfbase.link_picture, file_peek_picture) show whole from the first frame they show, never first without the pictures
// and then with them: the pictures asked as the value is read, before the card opens; where they are not here as it
// opens, the card shows as it does while its topic is read till they are.

///|
/// The made-up station's cards (fixture_link_preview, fixture_file_peek) with their pictures' calls kept in `asked`, to
/// be answered when the test says (peek_pictures_answer), as the core answers them from outside.
fn peek_pictures_source(asked : Array[(String, Json, (Result[(Json, Bytes), Json]) -> Unit)]) -> Source {
  let made = @sfbase.made_source()
  {
    ..made,
    topic_read: fn(name, params) {
      let p = Some(Json::object(params))
      match name {
        "linkPreview" => { value: Some(@sffixture.fixture_link_preview(text(p, "url"))), error: None, version: 1 }
        "filePeek" => { value: Some(@sffixture.fixture_file_peek(text(p, "path"))), error: None, version: 1 }
        _ => made.topic(name, params).get().snapshot()
      }
    },
    read_bytes: fn(name, params, done) { asked.push((name, params, done)) },
  }
}

///|
/// What was asked of the pictures, answered now as the made-up core has them.
fn peek_pictures_answer(asked : Array[(String, Json, (Result[(Json, Bytes), Json]) -> Unit)]) -> Unit {
  let now = asked.copy()
  asked.clear()
  for a in now {
    (a.2)(@sffixture.fixture_peek_picture(a.0, a.1).unwrap_or(Err({ "code": "unknown_call", "message": "" })))
  }
  @ui.came_from_outside()
}

///|
/// A window `w` wide (窄排法 at 390, 宽排法 at 1280) with a link 截图 drawn and `card` its card (given the link's id).
fn peek_pictures_tester(w : Double, card : (@ui.Ctx, Int) -> Unit) -> @ui.Tester {
  @sfbase.reset()
  @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.column(pad=40.0, fn() {
          let link = @kit.button(c, "截图", key="shot", variant=Ghost)
          card(c, link.id)
        })
        |> ignore
      })
    },
    w~,
    h=800.0,
    native=Mouse,
    pointing=Mouse,
  )
}

///|
/// The pointer rested on the link, frame by frame till its card has opened and come to rest, the pictures answered
/// after frame `answer_at`: in each frame, where the words `title` are laid out (None: not shown) and the sizes of the
/// images built.
fn peek_pictures_frames(
  t : @ui.Tester,
  asked : Array[(String, Json, (Result[(Json, Bytes), Json]) -> Unit)],
  title : String,
  answer_at : Int,
) -> Array[((Double, Double, Double, Double)?, Array[(Double, Double)])] raise {
  t.draw()
  let (x, y, w, h) = t.get(@ui.Role::Button, label="截图").rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  let seen = []
  let frames = ((hover_open_ms + @ui.move_most_ms) / @ui.first_frame_ms).to_int() + answer_at + 4
  for i in 0..<frames {
    t.frame()
    if i == answer_at {
      peek_pictures_answer(asked)
    }
    seen.push((t.rect_of(title), t.image_nodes().map(fn(n) { (n.1, n.2) })))
  }
  seen
}

///|
/// Whether every frame showing `title` built `images` images, and from the first of them on it was laid out where it
/// is in the last (the card's box the same from the first frame it shows); and that some did.
fn peek_pictures_whole(seen : Array[((Double, Double, Double, Double)?, Array[(Double, Double)])], images : Int) -> String {
  let shown = seen.filter(fn(f) { f.0 is Some(_) })
  guard shown.last() is Some((Some(last), last_images)) else { return "never shown" }
  for i, f in shown {
    if f.1.length() != images {
      return "frame \{i} of those shown: \{f.1.length()} images, not \{images}"
    }
    if f.0 != Some(last) || f.1 != last_images {
      return "frame \{i} of those shown: at \{Repr(f.0)}, images \{Repr(f.1)}; at rest at \{Repr(last)}, \{Repr(last_images)}"
    }
  }
  ""
}

///|
test "a link's card naming an icon and a picture shows whole from its first frame, 窄排法 and 宽排法: its pictures asked as it is read, before it opens" {
  for w in [390.0, 1280.0] {
    let asked = []
    let src = peek_pictures_source(asked)
    let t = peek_pictures_tester(w, fn(c, id) { web_peek(c, src, "ws1/st1", "https://example.com/bench/shot", "截图", id) })
    // (answered a frame after the pointer came onto the link: before its card opens, as the core's memory answers)
    let seen = peek_pictures_frames(t, asked, "列表滚动截图", 1)
    assert_eq(peek_pictures_whole(seen, 2), "", msg="width \{w}")
  }
}

///|
test "a picture file's peek shows whole from its first frame, 窄排法 and 宽排法: its picture asked as it is read, before it opens" {
  for w in [390.0, 1280.0] {
    let asked = []
    let src = peek_pictures_source(asked)
    let t = peek_pictures_tester(w, fn(c, id) { file_peek(c, src, "ws1/st1", "s-c1", "shots/list.png", None, id) })
    let seen = peek_pictures_frames(t, asked, "list.png", 1)
    assert_eq(peek_pictures_whole(seen, 1), "", msg="width \{w}")
    assert_true(asked.length() == 0, msg="width \{w}: asked once")
  }
}

///|
test "what a card shows waits for the pictures its value names: not here while one comes, here once each has come or failed, each asked once" {
  @sfbase.reset()
  let asked = []
  let src = peek_pictures_source(asked)
  let url = "https://example.com/bench/shot"
  let page = Some(@sffixture.fixture_link_preview(url))
  let peek = Some(@sffixture.fixture_file_peek("shots/list.png"))
  // (a picture of each kind coming: what shows them waits, as it does while their topic is read)
  assert_false(@sfbase.link_pictures_here(src, "ws1/st1", url, page))
  assert_eq(@sfbase.file_peek_picture(src, "ws1/st1", "s-c1", "shots/list.png", None, peek), "")
  assert_false(@sfbase.link_pictures_here(src, "ws1/st1", url, page), msg="still coming")
  assert_eq(asked.map(fn(a) { a.0 }), ["link.preview.picture", "link.preview.picture", "file.peek.picture"], msg="each asked once")
  peek_pictures_answer(asked)
  assert_true(@sfbase.link_pictures_here(src, "ws1/st1", url, page))
  let icon = @sfbase.link_picture(src, "ws1/st1", url, page, "icon")
  let image = @sfbase.link_picture(src, "ws1/st1", url, page, "image")
  assert_true(icon != "" && icon != "!" && image != "" && image != "!" && icon != image, msg="\{icon} \{image}")
  assert_eq(@sfbase.link_picture(src, "ws1/st1", url, page, "avatar"), "!", msg="none named")
  let shot = @sfbase.file_peek_picture(src, "ws1/st1", "s-c1", "shots/list.png", None, peek)
  assert_true(shot != "" && shot != "!", msg=shot)
  // (another picture named, by another token: asked anew)
  let other = page.map(fn(v) {
    match v {
      Object(m) => {
        let o = m.copy()
        o["image"] = Json::string("fix-image-2")
        Json::object(o)
      }
      _ => v
    }
  })
  assert_false(@sfbase.link_pictures_here(src, "ws1/st1", url, other))
  assert_eq(asked.length(), 1)
  peek_pictures_answer(asked)
  // (come: here again)
  assert_true(@sfbase.link_pictures_here(src, "ws1/st1", url, other))
  assert_eq(asked.length(), 0)
}

///|
test "a card's picture the core has none of shows the card without it, asked once" {
  let asked = []
  let src = peek_pictures_source(asked)
  // (a token the made-up core has no bytes of: its error)
  let v : Json = { "kind": "page", "url": "https://example.com/gone", "title": "没有图", "image": "fix-gone" }
  let src = {
    ..src,
    topic_read: fn(name, params) {
      if name == "linkPreview" {
        { value: Some(v), error: None, version: 1 }
      } else {
        (src.topic_read)(name, params)
      }
    },
  }
  let t = peek_pictures_tester(390.0, fn(c, id) { web_peek(c, src, "ws1/st1", "https://example.com/gone", "截图", id) })
  let seen = peek_pictures_frames(t, asked, "没有图", 1)
  assert_eq(peek_pictures_whole(seen, 0), "")
  assert_eq(@sfbase.link_picture(src, "ws1/st1", "https://example.com/gone", Some(v), "image"), "!")
  assert_eq(asked.length(), 0)
}
