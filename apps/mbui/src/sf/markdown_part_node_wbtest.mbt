// Reader parts use the core's offsets into the whole book, while their nodes and lifecycle belong to a visible row.

///|
let mp_text : String = "Alpha first\n\nTitle\n\nBeta second link\nhttps://example.org"

///|
fn mp_range(a : Int, b : Int) -> Json {
  Json::array([Json::number(a.to_double()), Json::number(b.to_double())])
}

///|
fn mp_parts() -> Array[Array[Json]] {
  let s = fn(x : String) { Json::string(x) }
  [
    [Json::array([s("p"), Json::array([mp_range(0, 11)])])],
    [
      Json::array([s("h"), Json::array([mp_range(13, 18)]), Json::object({ "depth": Json::number(1.0) })]),
      Json::array([
        s("p"),
        Json::array([
          mp_range(20, 32),
          Json::array([s("a"), Json::array([mp_range(32, 36)]), Json::object({ "href": mp_range(37, 56) })]),
        ]),
      ]),
    ],
  ]
}

///|
fn mp_drawn(words : String) -> @view.Drawn raise {
  let all = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == words })
  guard all is [one] else { fail("expected one node for \{words}, got \{all.length()}") }
  one
}

///|
test "Markdown part: full-text offsets, independent parts, spacing and link without a core request" {
  let parts = mp_parts()
  let asked : Array[String] = []
  let led : Array[String] = []
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=400.0, platform=2)
  markdown_read.val = Some(fn(s, _) { asked.push(s) })
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_part_node(root, mp_text, parts[0], size=fn() { 16.0 }, line=fn() { 1.5 }, document=true) |> ignore
    markdown_part_node(root, mp_text, parts[1], apart=true, size=fn() { 16.0 }, line=fn() { 1.5 }, document=true, on_link=fn(s) { led.push(s) }) |> ignore
  })
  t.draw()
  let first = mp_drawn("Alpha first")
  let title = mp_drawn("Title")
  let last = mp_drawn("Beta second link")
  assert_eq((first.words_look.size, title.words_look.size, last.words_look.size), (16.0, 24.0, 16.0))
  assert_eq(title.y - (first.y + first.h), 24.0)
  assert_eq(last.y - (title.y + title.h), 12.0)
  assert_eq(asked, [])
  t.tap_run("link")
  assert_eq(led, ["https://example.org"])
  markdown_read.val = None
}

///|
test "Markdown part: size, line, face, ink and found change on the existing nodes" {
  let parts = mp_parts()
  let size = @signals.signal(16.0)
  let line = @signals.signal(1.5)
  let serif = @signals.signal(false)
  let ink = @signals.signal(0x112233FFL)
  let found : @signals.Signal[Array[String]] = @signals.signal([])
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=400.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_part_node(
      root, mp_text, parts[1], apart=true, document=true,
      size=fn() { size.get() }, line=fn() { line.get() }, serif=fn() { serif.get() }, ink=fn() { ink.get() },
      found=fn() { found.get() },
    ) |> ignore
  })
  t.draw()
  let before = mp_drawn("Beta second link")
  assert_eq((before.words_look.size, before.words_look.line, before.ink), (16.0, 24.0, 0x112233FFL))
  assert_true(before.runs.iter().all(fn(r) { !r.serif }))
  size.set(20.0)
  line.set(2.0)
  serif.set(true)
  ink.set(0x445566FFL)
  found.set(["second"])
  t.draw()
  let after = mp_drawn("Beta second link")
  assert_eq(after.id, before.id)
  assert_eq((after.words_look.size, after.words_look.line, after.ink), (20.0, 40.0, 0x445566FFL))
  assert_true(after.runs.iter().all(fn(r) { r.serif }))
  assert_true(after.runs.iter().any(fn(r) { r.text == "second" && r.weight == 600 }))
  assert_eq(mp_drawn("Title").words_look.size, 30.0)
}

///|
test "Markdown part: a finger selects its words, dismisses the selection and opens a link" {
  let parts = mp_parts()
  let led : Array[String] = []
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=400.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_part_node(root, mp_text, parts[1], size=fn() { 16.0 }, document=true, on_link=fn(s) { led.push(s) }) |> ignore
  })
  t.draw()
  let r = t.run_rects("Beta second")
  assert_true(r.length() > 0)
  let (x, y, _, h) = r[0]
  t.press_at(x + 4.0, y + h / 2.0)
  t.run_for(@ui.long_press_ms)
  assert_true(t.ctx().selected_text().contains("Beta"), msg="\{t.ctx().selected_text()}")
  t.release(x + 4.0, y + h / 2.0)
  // Like an old view, a tap while a finger selection is active dismisses it before links can be opened.
  t.tap_run("link")
  assert_eq(led, [])
  assert_eq(t.ctx().selected_text(), "")
  t.tap_run("link")
  assert_eq(led, ["https://example.org"])
}

///|
test "Markdown part: a virtual list makes only visible parts and can return to the first" {
  let made : Array[Int] = []
  let nodes : Array[Array[Json]] = []
  let book = StringBuilder()
  let mut at = 0
  for i in 0..<400 {
    let words = "Part \{i}"
    let run = mp_range(at, at + words.length())
    let block = if i == 0 {
      Json::array([
        Json::string("list"),
        Json::array([Json::array([Json::string("li"), Json::array([run]), Json::object({})])]),
        Json::object({}),
      ])
    } else {
      Json::array([Json::string("p"), Json::array([run])])
    }
    nodes.push([block])
    book.write_string(words + "\n")
    at += words.length() + 1
  }
  let text = book.to_string()
  let scroll = @view.Scroll::list()
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      page.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      page.scrolls_window(scroll, fn() { Array::makei(nodes.length(), fn(i) { i }) }, est=30.0, fn(row, i) {
        made.push(i)
        markdown_part_node(row, text, nodes[i], apart=i > 0, size=fn() { 16.0 }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(t.words().iter().any(fn(w) { w.0 == "Part 0" }))
  assert_true(made.length() < 40, msg="made \{made.length()} of 400 parts")
  // A list item has several Markdown levels under the virtual row. Its selection must be named by the row that is
  // recreated after scrolling, rather than by a temporary nested child.
  let first = mp_drawn("Part 0")
  t.drag(first.x + 1.0, first.y + first.h / 2.0, first.x + first.w - 1.0, first.y + first.h / 2.0)
  assert_eq(t.ctx().selected_text(), "Part 0")
  t.wheel(150.0, 100.0, 600.0)
  t.run_for(@ui.move_most_ms)
  assert_true(!t.words().iter().any(fn(w) { w.0 == "Part 0" }))
  t.wheel(150.0, 100.0, -600.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.words().iter().any(fn(w) { w.0 == "Part 0" }))
  assert_eq(mp_drawn("Part 0").runs_picked, (0, 6))
  assert_true(made.length() < 100, msg="made \{made.length()} of 400 parts")
}

///|
test "Markdown part: table cells follow the reader's line, face, ink and search" {
  let s = fn(x : String) { Json::string(x) }
  let el = fn(name : String, kids : Array[Json]) { Json::array([s(name), Json::array(kids)]) }
  let table = el("table", [
    el("tr", [el("td", [s("Heading")])]),
    el("tr", [el("td", [s("table result")])]),
  ])
  let line = @signals.signal(1.5)
  let serif = @signals.signal(false)
  let ink = @signals.signal(0x112233FFL)
  let found : @signals.Signal[Array[String]] = @signals.signal([])
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_part_node(root, "table", [table], line=fn() { line.get() }, serif=fn() { serif.get() }, ink=fn() { ink.get() }, found=fn() { found.get() }) |> ignore
  })
  t.draw()
  let before = mp_drawn("table result")
  assert_eq((before.words_look.size, before.words_look.line, before.ink), (13.0, 20.0, 0x112233FFL))
  line.set(2.0)
  serif.set(true)
  ink.set(0x445566FFL)
  found.set(["result"])
  t.draw()
  let after = mp_drawn("table result")
  assert_eq(after.id, before.id)
  assert_eq((after.words_look.size, after.words_look.line, after.ink), (13.0, 26.0, 0x445566FFL))
  assert_true(after.runs.iter().all(fn(r) { r.serif }))
  assert_true(after.runs.iter().any(fn(r) { r.text == "result" && r.weight == 600 }))
}

///|
test "Markdown part and whole: prose, inline code, tables and code blocks follow tried faces" {
  let nodes : Array[Json] = [
    ["p", ["Prose ", ["code", { "content": "inline" }]]],
    ["table", [
      ["tr", [["td", ["Heading"]]]],
      ["tr", [["td", ["Cell ", ["code", { "content": "sample" }]]]]],
    ]],
    ["pre", { "code": "const x = 1", "lang": "ts", "ink": "h6j2c2f" }],
  ]
  for part in [true, false] {
    let text_face : @signals.Signal[Int?] = @signals.signal(None)
    let code_face : @signals.Signal[Int?] = @signals.signal(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=400.0, platform=0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      if part {
        markdown_part_node(root, "font sample", nodes, text_face=fn() { text_face.get() }, code_face=fn() { code_face.get() }) |> ignore
      } else {
        markdown_node(root, fn() { "font sample" }, tree=fn() { Some(Json::array(nodes)) }, text_face=fn() { text_face.get() }, code_face=fn() { code_face.get() }) |> ignore
      }
    })
    t.draw()
    let prose = mp_drawn("Prose inline")
    let cell = mp_drawn("Cell sample")
    let block = mp_drawn("const x = 1")
    let colors = block.runs.map(fn(r) { r.color })
    assert_true(prose.runs.iter().all(fn(r) { r.face is None }))
    assert_true(cell.runs.iter().all(fn(r) { r.face is None }))
    assert_true(block.runs.iter().all(fn(r) { r.face is None }))
    // Trying the app's prose face leaves code on the chosen code face.
    text_face.set(Some(0))
    t.draw()
    let prose_now = mp_drawn("Prose inline")
    let cell_now = mp_drawn("Cell sample")
    assert_eq(prose_now.id, prose.id)
    assert_eq(cell_now.id, cell.id)
    assert_eq(prose_now.runs.map(fn(r) { r.face }), [Some(0), None])
    assert_eq(cell_now.runs.map(fn(r) { r.face }), [Some(0), None])
    assert_true(mp_drawn("const x = 1").runs.iter().all(fn(r) { r.face is None }))
    // A different prose face and the app's code face apply independently, including to highlighted code.
    text_face.set(Some(12))
    code_face.set(Some(0))
    t.draw()
    assert_eq(mp_drawn("Prose inline").runs.map(fn(r) { r.face }), [Some(12), Some(0)])
    assert_eq(mp_drawn("Cell sample").runs.map(fn(r) { r.face }), [Some(12), Some(0)])
    assert_eq(mp_drawn("const x = 1").id, block.id)
    assert_true(mp_drawn("const x = 1").runs.iter().all(fn(r) { r.face == Some(0) }))
    assert_eq(mp_drawn("const x = 1").runs.map(fn(r) { r.color }), colors)
    code_face.set(Some(15))
    t.draw()
    assert_eq(mp_drawn("Prose inline").runs.map(fn(r) { r.face }), [Some(12), Some(15)])
    assert_true(mp_drawn("const x = 1").runs.iter().all(fn(r) { r.face == Some(15) }))
    text_face.set(None)
    code_face.set(None)
    t.draw()
    assert_true(mp_drawn("Prose inline").runs.iter().all(fn(r) { r.face is None }))
    assert_true(mp_drawn("const x = 1").runs.iter().all(fn(r) { r.face is None }))
  }
}

///|
test "Markdown part: mouse selection copies with the keyboard and its words are read out" {
  let parts = mp_parts()
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_part_node(root, mp_text, parts[0], size=fn() { 16.0 }) |> ignore
  })
  t.draw()
  assert_true(t.all(@view.Text, label="Alpha first").length() > 0, msg="\{t.semantics_dump()}")
  let words = mp_drawn("Alpha first")
  t.drag(words.x + 1.0, words.y + words.h / 2.0, words.x + words.w - 1.0, words.y + words.h / 2.0)
  assert_eq(t.ctx().selected_text(), "Alpha first")
  t.key(@ui.key_code_copy, mods=@ui.mod_cmd)
  assert_eq(t.clipboard(), "Alpha first")
}
