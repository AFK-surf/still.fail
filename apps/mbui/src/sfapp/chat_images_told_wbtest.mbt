// A chat's picture as a node of the window's tree reads it (sfbase's chat_images.mbt): told as it comes, nothing else
// needed to draw it.

///|
test "a chat's picture in its things' tile (a node) shows once it is here, nothing else drawing the page again" {
  for platform in [0, 2] {
    let images = @sfbase.ChatImages::new()
    let answers : Array[(Result[(Json, Bytes?), Json]) -> Unit] = []
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
                answers.push(done)
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
    let told = fn() { t.drawlist_images().filter(fn(i) { i.1.has_prefix("mem:told/") }).length() }
    assert_true(answers.length() > 0, msg="\{platform}: its tiles ask for their pictures")
    assert_eq(told(), 0, msg="\{platform}")
    // (each comes, nothing else changed)
    let n = answers.length()
    for done in answers {
      done(Ok((Json::object({}), Some(png_head()))))
    }
    t.run_for(@ui.move_most_ms)
    assert_eq(told(), n, msg="\{platform}: each tile's picture drawn once it is here")
  }
}
