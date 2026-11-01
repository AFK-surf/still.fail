///|
test "two identical Mermaid blocks in one message have separate views" {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("chat-viz")
  let chat = (src.topic)("chat", { "station": "ws1/st1", "session": "s-c1" }).value.unwrap()
  let view = @sfbase.chat_view_made(chat)
  let original = view.messages[view.messages.length() - 1]
  let block : Json = ["pre", { "code": "graph TD; A-->B", "lang": "mermaid" }]
  let message = { ..original, text: "two charts", md: Some(Json::array([block, block])), attachments: [], placed: [] }
  let here : MessageHere = { station: "ws1/st1", session: "s-c1", view, go: None, inline: false, gutter: 0.0, list: None, core: None }
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() { prose_with_files(c, src, here, message, []) })
  }, w=390.0, h=700.0, platform=1)
  t.check_looks(false)
  t.draw()
  let opened = t.views().filter(fn(line) {
    let parts = line.split(" ").collect()
    parts.length() >= 3 && parts[0] == "open" && parts[2] == "2"
  })
  assert_eq(opened.length(), 2, msg="each block has its own native view")
}

///|
test "a mermaid chart the core makes is drawn as a picture in the theme's colours, no page for it" {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let fixture = @sffixture.fixture("chat-viz")
  let asked : Array[Json] = []
  let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 100\"><rect width=\"200\" height=\"100\"/></svg>"
  let src = {
    ..fixture,
    call: fn(name, params, done) {
      if name == "mermaid.chart" {
        asked.push(params)
        done(Ok({ "svg": svg.to_json(), "width": 200.0.to_json(), "height": 100.0.to_json() }))
      } else {
        (fixture.call)(name, params, done)
      }
    },
  }
  let chat = (src.topic)("chat", { "station": "ws1/st1", "session": "s-c1" }).value.unwrap()
  let view = @sfbase.chat_view_made(chat)
  let original = view.messages[view.messages.length() - 1]
  let block : Json = ["pre", { "code": "graph TD; A-->B", "lang": "mermaid" }]
  let message = { ..original, text: "a chart", md: Some(Json::array([block])), attachments: [], placed: [] }
  let here : MessageHere = { station: "ws1/st1", session: "s-c1", view, go: None, inline: false, gutter: 0.0, list: None, core: None }
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() { prose_with_files(c, src, here, message, []) })
  }, w=390.0, h=700.0, platform=1)
  t.check_looks(false)
  t.draw()
  t.frames_owed()
  // asked once, its code and the theme's colours, each #rrggbb
  assert_eq(asked.length(), 1)
  match asked[0] {
    { "code": String(code), "colours": Object(colours), "width": Number(_, ..), .. } => {
      assert_eq(code, "graph TD; A-->B")
      assert_eq(colours.length(), 8)
      for _, v in colours {
        guard v is String(hex) && hex.length() == 7 && hex.has_prefix("#") else { fail("a colour as #rrggbb: \{v}") }
      }
    }
    _ => fail("asked \{asked[0]}")
  }
  // drawn as a picture at its size as written (200 wide, in a column wider than that), and no page opened for it
  assert_true(t.image_loads().length() > 0)
  let opened = t.views().filter(fn(line) { line.has_prefix("open ") })
  assert_eq(opened.length(), 0)
}
