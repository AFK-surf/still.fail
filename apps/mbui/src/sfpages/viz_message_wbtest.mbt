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
