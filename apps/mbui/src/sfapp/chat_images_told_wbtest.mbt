// A chat's picture as a node of the window's tree reads it (sfbase's chat_images.mbt): told as it comes, nothing else
// needed to draw it.

///|
test "a chat's picture in its things' tile (a node) shows once it is here, nothing else drawing the page again" {
  for platform in [0, 2] {
    let images = @sfbase.ChatImages::new()
    // (each ask: the picture's name, and its answer)
    let answers : Array[(String, (Result[(Json, Bytes?), Json]) -> Unit)] = []
    let src : Ref[Source?] = Ref(None)
    // (made as the window's tree is first made, as the screens' sweep makes it: squeeze_wbtest.mbt's screen_in)
    let made = fn() {
      match src.val {
        Some(s) => s
        None => {
          reset()
          let base = @sffixture.fixture("chat-things")
          let s : Source = {
            ..base,
            file: fn(station, key, name) {
              images.get(station, @sfbase.file_image_id(station, key, name), "mem:told/" + name, fn(_, done) {
                answers.push((name, done))
              })
            },
            images,
          }
          open_fixture_over("chat-things", s)
          src.val = Some(s)
          s
        }
      }
    }
    let t = @ui.Tester::new(
      fn(c) { view(c, made()) },
      tree=fn(root) { app_tree(made())(root) },
      w=if platform == 0 { 1280.0 } else { 390.0 },
      h=844.0,
      platform~,
    )
    t.run_for(squeeze_opening)
    let told = fn() { t.drawlist_images().filter(fn(i) { i.1.has_prefix("mem:told/") }).map(fn(i) { i.1 }) }
    assert_true(answers.length() > 0, msg="\{platform}: its tiles ask for their pictures")
    assert_eq(told().length(), 0, msg="\{platform}")
    // (each asked once: a list may ask ahead of what shows, never twice)
    let asked = answers.map(fn(a) { a.0 })
    for a in asked {
      assert_eq(asked.filter(fn(b) { b == a }).length(), 1, msg="\{platform}: \{a} asked twice: \{Repr(asked)}")
    }
    // (each comes, nothing else changed)
    for a in answers {
      (a.1)(Ok((Json::object({}), Some(png_head()))))
    }
    t.run_for(@ui.move_most_ms)
    // each tile on the screen (as a screen reader has it, 查看 …) drawn with its picture, nothing else drawn
    let (ww, wh) = t.size()
    let shown = asked.filter(fn(a) {
      t.all(Button, label=tr("web-main.file.view", args=[("name", a)])).iter().any(fn(s) {
        let (x, y, w, h) = s.rect
        x < ww && x + w > 0.0 && y < wh && y + h > 0.0
      })
    })
    assert_true(shown.length() > 0, msg="\{platform}: a tile on the screen")
    let drawn = told()
    drawn.sort()
    let want = shown.map(fn(a) { "mem:told/" + a })
    want.sort()
    assert_eq(drawn, want, msg="\{platform}: each tile's picture drawn once it is here")
  }
}
