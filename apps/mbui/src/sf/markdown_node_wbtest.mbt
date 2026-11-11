// Markdown as nodes (markdown_node) drawn as an old view's markdown draws the same words read the same way: each block,
// its words where they are, every instance the window draws.

///|
/// The core's reading of mn_text (its tree as markdown.ts writes it: blocks, their words in strings).
fn mn_tree() -> Json {
  let p = fn(xs : Array[Json]) { Json::array([Json::string("p"), Json::array(xs)]) }
  let s = fn(x : String) { Json::string(x) }
  let el = fn(name : String, kids : Array[Json]) { Json::array([Json::string(name), Json::array(kids)]) }
  let li = fn(kids : Array[Json], a : Json) { Json::array([Json::string("li"), Json::array(kids), a]) }
  Json::array([
    Json::array([s("h"), Json::array([s("今天的进度")]), Json::object({ "depth": Json::number(2.0) })]),
    p([s("改好了 "), el("b", [s("布局")]), s(" 和 "), el("i", [s("动画")]), s("，见 "), Json::array([s("a"), Json::array([s("说明")]), Json::object({ "href": s("https://example.com/notes") })]), s("。")]),
    Json::array([
      s("list"),
      Json::array([
        li([s("第一项，"), Json::array([s("code"), Json::array([]), Json::object({ "content": s("inline code") })])], Json::object({})),
        li([s("第二项"), Json::array([s("list"), Json::array([li([s("nested one")], Json::object({}))]), Json::object({ "ordered": Json::boolean(true), "start": Json::number(1.0) })])], Json::object({})),
        li([s("做完的事")], Json::object({ "checked": Json::boolean(true) })),
      ]),
      Json::object({}),
    ]),
    el("quote", [p([s("引用里的一句话")])]),
    Json::array([s("pre"), Json::array([]), Json::object({ "code": s("moon test --target native src/sf/markdown_node_wbtest.mbt"), "lang": s("sh"), "ink": s("") })]),
    el("hr", []),
    p([s("最后一段。")]),
  ])
}

///|
let mn_text : String = "（mn_tree 的原文）"

///|
/// The words drawn now, each with where it is, in one order.
fn mn_words(t : @ui.Tester) -> Array[String] {
  let all = t.words().map(fn(w) { "\{w.0} at \{(w.1 * 100.0).round() / 100.0},\{(w.2 * 100.0).round() / 100.0}" })
  all.sort()
  all
}

///|
/// Every instance the window drew last, each its numbers to a hundredth, in one order (read at once: the Tester's are
/// what the window last drew); a glyph's place in its atlas left out (where the order glyphs were first drawn in put
/// it), which atlas kept.
fn mn_instances(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances_keyed().map(fn(a) {
    a
    .mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
/// mn_tree's words in a column 16 in from a window `w` wide, drawn by an old view's markdown or as nodes (`node`).
fn mn_tester(node : Bool, w : Double, platform : Int) -> @ui.Tester {
  let tree = mn_tree()
  let t = if node {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=900.0, platform~)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          c.column(w=Fill(1.0), pad=16.0, fn() { markdown(c, mn_text, tree=Some(tree)) |> ignore }) |> ignore
        })
      },
      w~,
      h=900.0,
      platform~,
    )
  }
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.lines_up(Is(None)) |> ignore
      root.box(fn(b) {
        b.padding(Is((16.0, 16.0, 16.0, 16.0))) |> ignore
        markdown_node(b, fn() { mn_text }, tree=fn() { Some(tree) }) |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  t
}

///|
test "Markdown as nodes: its blocks' words where an old view's markdown draws them, with a finger and with a mouse" {
  for case in [(390.0, 2), (800.0, 0)] {
    let (w, platform) = case
    let old_t = mn_tester(false, w, platform)
    let old = mn_words(old_t)
    let old_drawn = mn_instances(old_t)
    let made_t = mn_tester(true, w, platform)
    let made = mn_words(made_t)
    let made_drawn = mn_instances(made_t)
    // (each block's words drawn, the heading's to the last paragraph's)
    assert_true(old.iter().any(fn(w) { w.has_prefix("今天的进度") }) && old.iter().any(fn(w) { w.has_prefix("最后一段。") }), msg="\{Repr(case)}: \{Repr(old)}")
    assert_eq(made, old, msg="\{Repr(case)}:\nmade \{Repr(made)}\nold  \{Repr(old)}")
    // (and every instance the window draws: grounds, bars, keys, glyphs, where each is cut)
    let only_made = made_drawn.filter(fn(x) { !old_drawn.contains(x) })
    let only_old = old_drawn.filter(fn(x) { !made_drawn.contains(x) })
    assert_true(
      made_drawn == old_drawn,
      msg="\{Repr(case)}: \{made_drawn.length()} drawn, \{old_drawn.length()} old;\nonly made \{Repr(only_made.iter().take(8).collect())}\nonly old  \{Repr(only_old.iter().take(8).collect())}",
    )
  }
}

///|
/// A Markdown node of `text` read as `tree` says (as it changes) at `size`, its code blocks of language `a` and `b` and
/// the files it names drawn as words saying which, a .jpg an image `ratio` wide over its height saying the width it is
/// given; in a window 390 wide. What the tree draws, its words.
fn mn_live(text : () -> String, tree : () -> Json?, size : () -> Double, ratio? : () -> Double = fn() { 1.0 }) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=900.0, platform=2)
  let said = fn(v : @view.View, words : () -> String) { v.words(By(words)) |> ignore }
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    markdown_node(
      root,
      text,
      tree~,
      size~,
      code=fn(lang) {
        match lang {
          "a" | "b" => Some(fn(v, code) { said(v, fn() { lang + ":" + code() }) })
          _ => None
        }
      },
      files=fn(name) {
        if name.has_suffix(".png") {
          Some({ draw: fn(v) { said(v, fn() { "file:" + name }) }, image: None })
        } else if name.has_suffix(".jpg") {
          Some({
            draw: fn(v) { said(v, fn() { "file:" + name }) },
            image: Some((ratio(), fn(v, width) { said(v, fn() { "img:" + name + ":" + width().to_string() }) })),
          })
        } else {
          None
        }
      },
    )
    |> ignore
  })
  t.draw()
  t
}

///|
/// The words of the window's tree drawn now and the size each is set at.
fn mn_drawn() -> Array[(String, Double)] {
  @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words != "" }).map(fn(d) { (d.words, d.words_look.size) })
}

///|
test "Markdown as nodes: a code block's language changed draws it as the new one's; its code changed, as it is now" {
  let lang = @signals.signal("a")
  let code = @signals.signal("x")
  let tree = fn() {
    Some(Json::array([Json::array([Json::string("pre"), Json::array([]), Json::object({ "code": Json::string(code.get()), "lang": Json::string(lang.get()) })])]))
  }
  // (its text as it is read: what a reading is kept by, as a message's words are)
  let t = mn_live(fn() { "```" + lang.get() + "\n" + code.get() + "\n```" }, tree, fn() { 15.0 })
  assert_true(mn_drawn().iter().any(fn(d) { d.0 == "a:x" }), msg="\{Repr(mn_drawn())}")
  code.set("y")
  t.draw()
  assert_true(mn_drawn().iter().any(fn(d) { d.0 == "a:y" }), msg="\{Repr(mn_drawn())}")
  lang.set("b")
  t.draw()
  assert_true(mn_drawn().iter().any(fn(d) { d.0 == "b:y" }), msg="\{Repr(mn_drawn())}")
  assert_true(!mn_drawn().iter().any(fn(d) { d.0.has_prefix("a:") }), msg="\{Repr(mn_drawn())}")
}

///|
test "Markdown as nodes: a paragraph of only a link to a file the message places draws that file; the link to another, the other" {
  let href = @signals.signal("x.png")
  let tree = fn() {
    Some(
      Json::array([
        Json::array([
          Json::string("p"),
          Json::array([Json::array([Json::string("a"), Json::array([Json::string("图")]), Json::object({ "href": Json::string(href.get()) })])]),
        ]),
      ]),
    )
  }
  let t = mn_live(fn() { "[图](" + href.get() + ")" }, tree, fn() { 15.0 })
  assert_true(mn_drawn().iter().any(fn(d) { d.0 == "file:x.png" }), msg="\{Repr(mn_drawn())}")
  href.set("y.png")
  t.draw()
  assert_true(mn_drawn().iter().any(fn(d) { d.0 == "file:y.png" }), msg="\{Repr(mn_drawn())}")
  assert_true(!mn_drawn().iter().any(fn(d) { d.0 == "file:x.png" }), msg="\{Repr(mn_drawn())}")
}

///|
test "Markdown as nodes: its words' size changed, its paragraphs and headings set at the new one, the same nodes" {
  let size = @signals.signal(15.0)
  let tree = fn() {
    Some(
      Json::array([
        Json::array([Json::string("h"), Json::array([Json::string("标题")]), Json::object({ "depth": Json::number(1.0) })]),
        Json::array([Json::string("p"), Json::array([Json::string("一段话")])]),
      ]),
    )
  }
  let t = mn_live(fn() { "size" }, tree, fn() { size.get() })
  let size_of = fn(w : String) {
    match mn_drawn().search_by(fn(d) { d.0 == w }) {
      Some(i) => mn_drawn()[i].1
      None => -1.0
    }
  }
  assert_eq((size_of("标题"), size_of("一段话")), (15.0, 15.0))
  size.set(20.0)
  t.draw()
  assert_eq((size_of("标题"), size_of("一段话")), (20.0, 20.0))
}

///|
test "Markdown as nodes: a row of images, one of them twice, each drawn at the width it has as the window and their widths change" {
  let ratio = @signals.signal(1.0)
  let img = fn(src : String) { Json::array([Json::string("img"), Json::array([]), Json::object({ "src": Json::string(src), "alt": Json::string("") })]) }
  let tree = fn() { Some(Json::array([Json::array([Json::string("p"), Json::array([img("a.jpg"), img("a.jpg"), img("b.jpg")])])])) }
  let t = mn_live(fn() { "images" }, tree, fn() { 15.0 }, ratio=fn() { ratio.get() })
  // (each image's words and the width it says, with the width it is drawn at)
  let images = fn() {
    @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words.has_prefix("img:") }).map(fn(d) { (d.words, d.w) })
  }
  let said_as_drawn = fn() {
    images().iter().all(fn(d) { d.0.has_suffix(":" + d.1.to_string()) })
  }
  let first = images()
  assert_eq(first.filter(fn(d) { d.0.has_prefix("img:a.jpg:") }).length(), 2, msg="\{Repr(first)}")
  assert_eq(first.filter(fn(d) { d.0.has_prefix("img:b.jpg:") }).length(), 1, msg="\{Repr(first)}")
  assert_true(said_as_drawn(), msg="\{Repr(first)}")
  t.resize(600.0, 900.0)
  t.draw()
  let wider = images()
  assert_true(said_as_drawn(), msg="\{Repr(wider)}")
  assert_true(wider[0].1 > first[0].1, msg="\{Repr(first)} \{Repr(wider)}")
  ratio.set(0.5)
  t.draw()
  let narrower = images()
  assert_eq(narrower.length(), 3, msg="\{Repr(narrower)}")
  assert_true(said_as_drawn(), msg="\{Repr(narrower)}")
  assert_true(narrower[0].1 < wider[0].1, msg="\{Repr(wider)} \{Repr(narrower)}")
}

///|
/// `code` in a code block in a column 16 in from a window `w` wide (a finger's at 390, a mouse's wider), in the colours
/// `ink` says where it says them, the system's words at `scale`, wrapped at its width where `wrapped` (its wrap key
/// pressed), drawn by an old view's code_block or as nodes (`node`, code_block_node): its Tester, drawn.
fn mlines_tester(node : Bool, code : String, ink : String?, w : Double, scale : Double, wrapped : Bool) -> @ui.Tester {
  // (an old view's block wrapped by its id: none so till its key is pressed here)
  code_wrapped.clear()
  let platform = if w < 500.0 { 2 } else { 0 }
  let t = if node {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=900.0, platform~)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() { c.column(w=Fill(1.0), pad=16.0, fn() { code_block(c, code, "sh", colours=ink) }) |> ignore })
      },
      w~,
      h=900.0,
      platform~,
    )
  }
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.lines_up(Is(None)) |> ignore
      root.box(fn(b) {
        b.padding(Is((16.0, 16.0, 16.0, 16.0))) |> ignore
        b.box(fn(k) { code_block_node(k, fn() { code }, fn() { "sh" }, fn() { ink }) }) |> ignore
      })
      |> ignore
    })
  }
  t.set_font_scale(scale)
  t.draw()
  t.draw()
  if wrapped {
    t.tap_text(md_wrap_words(false))
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// Where each line of `code` is drawn in `t` (Tester::run_rects: a rectangle a line), to a hundredth, and the box of
/// the words holding its first line.
fn mlines_at(t : @ui.Tester, code : String) -> (Array[String], String) {
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let lines = code.split("\n").to_array().filter(fn(l) { l != "" }).map(fn(l) { l.to_owned() })
  let at = lines.map(fn(l) { "\{l}: \{@ui.list_text(t.run_rects(l).map(fn(r) { @ui.rect_text((r2(r.0), r2(r.1), r2(r.2), r2(r.3))) }))}" })
  let first = match t.rect_of(lines[0]) {
    Some(r) => @ui.rect_text((r2(r.0), r2(r.1), r2(r.2), r2(r.3)))
    None => "none"
  }
  (at, first)
}

///|
/// Code of more lines in a code block, wrapped at its width (`wrapped`) or on its lines as written, drawn as nodes as an old
/// view's code block draws it: each case at 760 and 390, words at 1 and 1.3.
fn mlines_alike(wrapped : Bool) -> Unit raise {
  let long = "printf '%s\\n' \"a line of a script long enough to run past a phone's width and past a desktop's at its size, on and on\""
  let cases : Array[(String, String, String?)] = [
    ("two lines", "moon test --target wasm-gc src/sf/markdown_node_wbtest.mbt\nmoon check", None),
    ("an empty line", "a = 1\n\nb = 2", None),
    ("a long line among short ones", "set -e\n" + long + "\ndone", None),
    ("a break at its end", "line one\nline two\n", None),
    ("in a language's colours", "let x = 1\n// note\nfoo(\"hi\")\n", Some("h3a1j1a1c1a1f1a1b7a1i3c1d4c1a1")),
  ]
  for case in cases {
    let (name, code, ink) = case
    for w in [760.0, 390.0] {
      for scale in [1.0, 1.3] {
        let at = "\{name}, \{w} wide, words at \{scale}\{if wrapped { ", wrapped" } else { "" }}"
        let old_t = mlines_tester(false, code, ink, w, scale, wrapped)
        let old = mn_words(old_t)
        let old_lines = mlines_at(old_t, code)
        let old_drawn = mn_instances(old_t)
        let made_t = mlines_tester(true, code, ink, w, scale, wrapped)
        let made = mn_words(made_t)
        let made_lines = mlines_at(made_t, code)
        let made_drawn = mn_instances(made_t)
        assert_eq(made_lines, old_lines, msg="\{at}:\nmade \{Repr(made_lines)}\nold  \{Repr(old_lines)}")
        assert_eq(made, old, msg="\{at}:\nmade \{Repr(made)}\nold  \{Repr(old)}")
        if !wrapped {
          // (every instance the window draws, at rest on its lines as written: grounds, keys, glyphs, where each is cut)
          let only_made = made_drawn.filter(fn(x) { !old_drawn.contains(x) })
          let only_old = old_drawn.filter(fn(x) { !made_drawn.contains(x) })
          assert_true(
            made_drawn == old_drawn,
            msg="\{at}: \{made_drawn.length()} drawn, \{old_drawn.length()} old;\nonly made \{Repr(only_made.iter().take(8).collect())}\nonly old  \{Repr(only_old.iter().take(8).collect())}",
          )
          // (each a line of its own, one under the other)
          let rows = code.split("\n").to_array().filter(fn(l) { l != "" }).map(fn(l) { made_t.run_rects(l.to_owned()) })
          assert_true(rows.iter().all(fn(r) { r.length() == 1 }), msg="\{at}: \{Repr(rows)}")
          for k in 1..<rows.length() {
            assert_true(rows[k][0].1 > rows[k - 1][0].1, msg="\{at}: \{Repr(rows)}")
          }
        }
      }
    }
  }
  code_wrapped.clear()
}

///|
test "a code block of more lines as nodes, on its lines as written: each line on a line of its own where an old view's code block draws it, at 760 and 390, words at 1 and 1.3" {
  mlines_alike(false)
}

///|
test "a code block of more lines as nodes, wrapped once its key is pressed: each line from a line of its own where an old view's code block draws it, at 760 and 390, words at 1 and 1.3" {
  mlines_alike(true)
}
