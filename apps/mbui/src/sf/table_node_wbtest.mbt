// A table as nodes (table_node) asking the core to read its Markdown: once for all who read the same text, its answer
// told to every one of them, the one that asked gone or not, at once or late; a made-up one's asked of nobody.

///|
let tn_text : String = "| 模型 | 输入 |\n| --- | --- |\n| Opus 5.5 | $15 |"

///|
/// The core's reading of a table of two columns, its head `head` and its row `row` (tn_text's: 模型 输入, Opus 5.5 $15).
fn tn_tree(head? : (String, String) = ("模型", "输入"), row? : (String, String) = ("Opus 5.5", "$15")) -> Json {
  let cell = fn(s : String) { Json::array([Json::string("td"), Json::array([Json::string(s)])]) }
  let line = fn(p : (String, String)) { Json::array([Json::string("tr"), Json::array([cell(p.0), cell(p.1)])]) }
  // (and as the core writes it to copy: markdown.ts tableMarkdown, tableCsv)
  let md = "| \{head.0} | \{head.1} |\n| --- | --- |\n| \{row.0} | \{row.1} |"
  let csv = "\{head.0},\{head.1}\n\{row.0},\{row.1}"
  Json::array([
    Json::array([
      Json::string("table"),
      Json::array([line(head), line(row)]),
      Json::object({ "md": Json::string(md), "csv": Json::string(csv) }),
    ]),
  ])
}

///|
/// Two tables of tn_text (the first while `first` says), and a made-up one where `sample`, in a window 390 wide; the
/// core asked as `read` says.
fn tn_tester(
  first : @signals.Signal[Bool],
  read : (String, (Json?) -> Unit) -> Unit,
  sample? : Bool = false,
  platform? : Int = 0,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=400.0, platform~)
  // (said once the Tester has begun: its start puts it back to none)
  markdown_read.val = Some(read)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.show(at_once=true, fn() { first.get() }, fn(a) { table_node(a, fn() { tn_text }) })
    root.box(fn(b) { table_node(b, fn() { tn_text }) }) |> ignore
    @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
    if sample {
      root.box(fn(s) { table_node(s, fn() { "| a | b |\n| --- | --- |\n| c | d |" }, tree=fn() { Some(tn_tree(head=("a", "b"), row=("c", "d"))) }) }) |> ignore
    }
  })
  t.draw()
  t
}

///|
/// How many times the words `w` are drawn now.
fn tn_drawn(w : String) -> Int {
  @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == w }).length()
}

///|
test "two tables of the same words, the core answering late, the one that asked gone first: the other told its answer" {
  let asked = []
  let first = @signals.signal(true)
  let t = tn_tester(first, fn(text, done) { asked.push((text, done)) })
  let before = (asked.length(), tn_drawn("Opus 5.5"))
  first.set(false)
  t.draw()
  (asked[0].1)(Some(tn_tree()))
  t.draw()
  t.draw()
  markdown_read.val = None
  assert_eq((before, asked.length(), tn_drawn("Opus 5.5")), ((1, 0), 1, 1))
}

///|
test "two tables of the same words, the core answering at once: both told, asked once; a made-up one's asked of nobody" {
  let asked = []
  let first = @signals.signal(true)
  let t = tn_tester(
    first,
    fn(text, done) {
      asked.push(text)
      done(Some(tn_tree()))
    },
    sample=true,
  )
  t.draw()
  markdown_read.val = None
  assert_eq((asked, tn_drawn("Opus 5.5"), tn_drawn("c")), ([tn_text], 2, 1))
}

///|
test "an old view's markdown asking first for the same words, a table of the tree reading them after, the core answering late: the table told" {
  let asked = []
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      // (read once the core is said: the Tester's start puts it back to none, and a build before then reads what is
      // kept of the core's answers)
      if markdown_read.val is Some(_) {
        markdown(c, tn_text) |> ignore
      }
    },
    w=390.0,
    h=400.0,
  )
  markdown_read.val = Some(fn(text, done) { asked.push((text, done)) })
  t.draw()
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(b) { table_node(b, fn() { tn_text }) }) |> ignore
  })
  t.draw()
  let before = (asked.length(), tn_drawn("Opus 5.5"))
  (asked[0].1)(Some(tn_tree()))
  t.draw()
  t.draw()
  markdown_read.val = None
  assert_eq((before, asked.length(), tn_drawn("Opus 5.5")), ((1, 0), 1, 1))
}

///|
/// A table of five columns, wider than a window 300 wide: as Markdown, and as the core reads it.
let tn_wide : String = "| 模型 | 输入 | 输出 | 缓存读 | 缓存写 |\n| --- | --- | --- | --- | --- |\n| Opus 5.5 | $15 | $75 | $1.5 | $18.75 |"

///|
fn tn_wide_tree() -> Json {
  let cell = fn(s : String) { Json::array([Json::string("td"), Json::array([Json::string(s)])]) }
  let line = fn(cs : Array[String]) { Json::array([Json::string("tr"), Json::array(cs.map(cell))]) }
  Json::array([
    Json::array([
      Json::string("table"),
      Json::array([line(["模型", "输入", "输出", "缓存读", "缓存写"]), line(["Opus 5.5", "$15", "$75", "$1.5", "$18.75"])]),
      Json::object({
        "md": Json::string(tn_wide),
        "csv": Json::string("模型,输入,输出,缓存读,缓存写\nOpus 5.5,$15,$75,$1.5,$18.75"),
      }),
    ]),
  ])
}

///|
/// tn_wide's table 300 wide with keyboard and mouse, an old view's (`tree` false) or a node's, the pointer over it, its
/// key pressed and each of its menu's in turn: what each put on the clipboard (Markdown, CSV), the picture's bytes and
/// the words its shot drew.
fn tn_copied(tree : Bool) -> (String, String, Int?, Array[Array[String]], Array[((Int, Int), Array[String])]) raise {
  let tt = if tree {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=300.0, h=400.0, platform=0)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          // (once the core is said: a build before then reads what is kept of its answers)
          if markdown_read.val is Some(_) {
            markdown(c, tn_wide) |> ignore
          }
          // (its menu, as what presents it draws it)
          presented(c)
        })
      },
      w=300.0,
      h=400.0,
      platform=0,
    )
  }
  markdown_read.val = Some(fn(_, done) { done(Some(tn_wide_tree())) })
  if tree {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(b) { table_node(b, fn() { tn_wide }) }) |> ignore
      // (its menu, as what presents it draws it)
      @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
      presented_nodes(root)
    })
  }
  tt.draw()
  tt.draw()
  tt.move_to(20.0, 15.0)
  tt.run_for(@ui.move_most_ms)
  let pick = fn(item : String) raise {
    tt.act(Button, Activate, label=t("web-main.prose.copyTable"))
    tt.run_for(@ui.move_most_ms)
    tt.act(Button, Activate, label=item)
    tt.run_for(@ui.move_most_ms)
  }
  pick(t("web-main.prose.copyMarkdown"))
  let md = tt.clipboard()
  tt.run_for(copied_ms)
  pick(t("web-main.prose.copyCsv"))
  let csv = tt.clipboard()
  tt.run_for(copied_ms)
  pick(picture_out_way().0)
  tt.run_for(@ui.move_most_ms)
  markdown_read.val = None
  (md, csv, tt.clipboard_image(), tt.shots(), tt.shot_drawn())
}

///|
test "a table's copy key as nodes: its menu's Markdown, CSV and picture as an old view's table's, the picture of all of it, past what shows" {
  let old = tn_copied(false)
  let made = tn_copied(true)
  assert_eq(made, old)
  // (each said: Markdown and CSV words; the picture of some size, all of it drawn, past what shows of it: its PNG none,
  // the Tester's host reading nothing drawn back, as for the old view)
  let ((w, h), drawn) = made.4[0]
  assert_true(
    old.0 != "" && old.1 != "" && made.4.length() == 1 && w > 300 && h > 0 && drawn.length() > 10,
    msg="\{old.0} \{old.1} \{Repr(old.2)} \{w}x\{h} \{drawn.length()}",
  )
  assert_true(made.3.length() == 1 && made.3[0].contains("$18.75"), msg="\{Repr(made.3)}")
}

///|
test "two tables of the same words with a finger: one's key copied says so, the other's not; the first let go, the other's key as it was" {
  let first = @signals.signal(true)
  let tt = tn_tester(first, fn(_, done) { done(Some(tn_tree())) }, platform=2)
  tt.draw()
  let keys = fn() { tt.semantics().filter(fn(n) { n.role == Button && n.label == t("web-main.prose.copyTable") }).length() }
  let copied = fn() { tt.semantics().filter(fn(n) { n.role == Button && n.label == t("common.copied") }).length() }
  let both = (keys(), copied())
  // (the first's key)
  tt.act_on(tt.all(Button, label=t("web-main.prose.copyTable"))[0], Activate)
  tt.run_for(@ui.move_most_ms)
  tt.act(Button, Activate, label=t("web-main.prose.copyMarkdown"))
  tt.run_for(@ui.move_most_ms)
  let one = (keys(), copied())
  first.set(false)
  tt.draw()
  let left = (keys(), copied())
  tt.run_for(copied_ms)
  markdown_read.val = None
  assert_eq((both, one, left, (keys(), copied())), ((2, 0), (1, 1), (1, 0), (1, 0)))
}

///|
test "a table's menu open, its words changed and not read yet: its picture the table as the menu opened on it, with its own columns' widths" {
  let words = @signals.signal(tn_text)
  let tt = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=400.0, platform=0)
  // (the first read at once; what comes after, never)
  markdown_read.val = Some(fn(text, done) { if text == tn_text { done(Some(tn_tree())) } })
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(b) { table_node(b, fn() { words.get() }) }) |> ignore
    @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  tt.draw()
  tt.move_to(20.0, 15.0)
  tt.run_for(@ui.move_most_ms)
  tt.act(Button, Activate, label=t("web-main.prose.copyTable"))
  tt.run_for(@ui.move_most_ms)
  words.set("| 另一张 | 表 |\n| --- | --- |\n| 未 | 读 |")
  tt.draw()
  tt.act(Button, Activate, label=picture_out_way().0)
  tt.run_for(@ui.move_most_ms)
  markdown_read.val = None
  let shots = tt.shots()
  let drawn = tt.shot_drawn()
  assert_true(
    shots.length() == 1 && shots[0].contains("Opus 5.5") && drawn.length() == 1 && (drawn[0].0).0 > 0 && drawn[0].1.length() > 4,
    msg="\{Repr(shots)} \{Repr(drawn.map(fn(d) { (d.0, d.1.length()) }))}",
  )
}

///|
test "a table's copy key with keyboard and mouse, as the app's host follows the pointer: none at first; the pointer over its words, there; away, gone once faded" {
  let first = @signals.signal(true)
  let tt = tn_tester(first, fn(_, done) { done(Some(tn_tree())) })
  tt.draw()
  let keys = fn() { tt.all(Button, label=t("web-main.prose.copyTable")).length() }
  let none = keys()
  // (over the first table's words: its key alone)
  tt.move_to(20.0, 15.0)
  tt.run_for(@ui.move_most_ms)
  let over = keys()
  tt.move_to(380.0, 390.0)
  tt.run_for(@ui.move_most_ms)
  markdown_read.val = None
  assert_eq((none, over, keys()), (0, 1, 0))
}

///|
let tn_rich : String = "| 样式 | 写法 |\n| --- | --- |\n| *斜体* | `code` |\n| ~~删去~~ | **粗** 与 *斜* |\n| [链接](https://still.fail) | 甲 |"

///|
/// The core's reading of tn_rich: its cells italic, code, struck through, bold beside italic, a link.
fn tn_rich_tree() -> Json {
  let s = fn(w : String) { Json::string(w) }
  let el = fn(name : String, kids : Array[Json]) { Json::array([s(name), Json::array(kids)]) }
  let td = fn(kids : Array[Json]) { el("td", kids) }
  let code = Json::array([s("code"), Json::array([]), Json::object({ "content": s("code") })])
  Json::array([
    el("table", [
      el("tr", [td([s("样式")]), td([s("写法")])]),
      el("tr", [td([el("i", [s("斜体")])]), td([code])]),
      el("tr", [td([el("s", [s("删去")])]), td([el("b", [s("粗")]), s(" 与 "), el("i", [s("斜")])])]),
      el("tr", [
        td([Json::array([s("a"), Json::array([s("链接")]), Json::object({ "href": s("https://still.fail") })])]),
        td([s("甲")]),
      ]),
    ]),
  ])
}

///|
/// tn_rich's table 300 wide, an old view's (`tree` false) or a node's: the glyphs drawn (where, in what ink), from
/// the corner of all of them.
fn tn_rich_drawn(tree : Bool) -> Array[(Double, Double, Int64)] {
  let tt = if tree {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=300.0, h=400.0, platform=0)
  } else {
    @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        // (once the core is said: a build before then reads what is kept of its answers)
        if markdown_read.val is Some(_) {
          c.with_theme(ui_theme(), fn() { markdown(c, tn_rich) |> ignore })
        }
      },
      w=300.0,
      h=400.0,
      platform=0,
    )
  }
  markdown_read.val = Some(fn(_, done) { done(Some(tn_rich_tree())) })
  if tree {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(b) { table_node(b, fn() { tn_rich }, copy=false) }) |> ignore
    })
  }
  tt.draw()
  tt.draw()
  markdown_read.val = None
  let glyphs = tt.drawn_glyphs()
  let x0 = glyphs.fold(init=1.0e9, fn(m, g) { if g.0 < m { g.0 } else { m } })
  let y0 = glyphs.fold(init=1.0e9, fn(m, g) { if g.1 < m { g.1 } else { m } })
  glyphs.map(fn(g) { (g.0 - x0, g.1 - y0, g.2) })
}

///|
test "a table's cells in pieces as nodes (italic, code, struck through, bold beside italic, a link): each glyph where an old view's table draws it, in its ink" {
  let old = tn_rich_drawn(false)
  let made = tn_rich_drawn(true)
  assert_true(old.length() > 12, msg="the old one drawn: \{old.length()}")
  assert_eq(made, old)
  // (none of it an old view's: no old view in the window but what the table is made of)
  assert_eq(@ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == "斜体" }).length(), 1)
  assert_eq(@ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).length(), 0)
}

///|
test "a table shown, its reading pushed out of the texts read lately by others: another of the same words come, asked nothing; laid out again narrower, the first gone, the other's words and copy still there; the last gone, nothing of it kept" {
  let first = @signals.signal(true)
  let second = @signals.signal(false)
  let asked = Ref(0)
  let tt = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=400.0, platform=0)
  markdown_read.val = Some(fn(_, done) {
    asked.val += 1
    done(Some(tn_tree()))
  })
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.show(at_once=true, fn() { first.get() }, fn(a) { table_node(a, fn() { tn_text }) })
    root.show(at_once=true, fn() { second.get() }, fn(b) { table_node(b, fn() { tn_text }) })
    @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  tt.draw()
  let shown = tn_drawn("Opus 5.5")
  // (as many other texts read since as the texts read lately keep: its own pushed out)
  for i in 0..=parsed_most {
    blocks_of("tn-other-\{i}", Some(Json::array([]))) |> ignore
  }
  let pushed = parsed.contains(tn_text) || core_parsed.contains(tn_text) || markdown_asked.contains(tn_text)
  // (another of the same words come: what the first holds, nothing asked)
  second.set(true)
  tt.draw()
  let both = tn_drawn("Opus 5.5")
  // (laid out again, its text the same: its columns' widths worked out anew; the first gone)
  tt.resize(320.0, 400.0)
  first.set(false)
  tt.draw()
  let other = tn_drawn("Opus 5.5")
  tt.move_to(20.0, 15.0)
  tt.run_for(@ui.move_most_ms)
  tt.act(Button, Activate, label=t("web-main.prose.copyTable"))
  tt.run_for(@ui.move_most_ms)
  tt.act(Button, Activate, label=t("web-main.prose.copyMarkdown"))
  tt.run_for(@ui.move_most_ms)
  let copied = tt.clipboard()
  tt.run_for(copied_ms)
  let held = (md_held.contains(tn_text), md_answered.contains(tn_text))
  second.set(false)
  tt.draw()
  markdown_read.val = None
  assert_eq(
    (shown, pushed, both, other, copied, asked.val, held, md_held.contains(tn_text), md_answered.contains(tn_text)),
    (1, false, 2, 1, "| 模型 | 输入 |\n| --- | --- |\n| Opus 5.5 | $15 |", 1, (true, true), false, false),
  )
}

///|
test "a table's cell with a link, as nodes: tapped on its link, where it leads told; on its other words, nothing; its words the tree's" {
  let led : Array[String] = []
  let tt = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=400.0, platform=2)
  let text = "| 名 | 址 |\n| --- | --- |\n| 文档 | 见[链接](https://still.fail)处 |"
  let s = fn(w : String) { Json::string(w) }
  let el = fn(name : String, kids : Array[Json]) { Json::array([s(name), Json::array(kids)]) }
  let link = Json::array([s("a"), Json::array([s("链接")]), Json::object({ "href": s("https://still.fail") })])
  let tree = Json::array([
    el("table", [el("tr", [el("td", [s("名")]), el("td", [s("址")])]), el("tr", [el("td", [s("文档")]), el("td", [s("见"), link, s("处")])])]),
  ])
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(a) {
      table_node(a, fn() { text }, tree=fn() { Some(tree) }, copy=false, on_link=fn(href) { led.push(href) })
    })
    |> ignore
  })
  tt.draw()
  // (the cell's words, as the tree draws them: where its link and its other words are)
  let cell = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == "见链接处" })
  guard cell is [d] else { fail("the cell's words drawn once by the tree: \{cell.length()}") }
  // (its middle line: 见 at its start, 链接 after it)
  let y = d.y + d.h / 2.0
  tt.tap(d.x + 3.0, y)
  tt.run_for(@ui.move_most_ms)
  let before = led.copy()
  tt.tap(d.x + d.w / 2.0, y)
  tt.run_for(@ui.move_most_ms)
  assert_eq((before, led), ([], ["https://still.fail"]))
}
