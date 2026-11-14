// A card's pictures read by nodes of the window's tree (sfbase's peek_pictures.mbt: link_picture_told,
// file_peek_picture_told): nothing asked of the core as a binding runs, only as something reacts (link_pictures_ask,
// file_peek_picture_ask); each picture told as it comes to what reads it, in the first frame after it came, and to
// nothing else; the old views' reads as they were.

///|
/// Two nodes in a window, each reading one picture by `read` (its words the key it reads), how many times each is
/// worked out counted in `runs`; drawn once.
fn told_pictures_tester(read : Array[() -> String], runs : Array[Int]) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      for k, r in read {
        root.box(fn(b) {
          b
          .words(By(fn() {
            runs[k] = runs[k] + 1
            "[" + r() + "]"
          }))
          |> ignore
        })
        |> ignore
      }
    },
    w=400.0,
    h=400.0,
  )
  t.draw()
  t
}

///|
test "a link card's pictures read by nodes: none asked as they are drawn; asked as one reacts; each told as it comes to the node reading it alone, in the first frame after" {
  @sfbase.reset()
  let asked = []
  let src = peek_pictures_source(asked)
  let url = "https://example.com/bench/shot"
  let page = Some(@sffixture.fixture_link_preview(url))
  let runs = [0, 0]
  let t = told_pictures_tester(
    [
      fn() { @sfbase.link_picture_told(src, "ws1/st1", url, page, "icon") },
      fn() { @sfbase.link_picture_told(src, "ws1/st1", url, page, "image") },
    ],
    runs,
  )
  assert_eq(asked.length(), 0, msg="nothing asked as they are drawn")
  assert_true(t.find("[]") is Some(_), msg="neither here")
  assert_false(@sfbase.link_pictures_here_told(src, "ws1/st1", url, page))
  assert_eq(asked.length(), 0, msg="nor as whether they are here is read")
  // (asked as something reacts to the value read: each once)
  @sfbase.link_pictures_ask(src, "ws1/st1", url, page)
  @sfbase.link_pictures_ask(src, "ws1/st1", url, page)
  assert_eq(asked.map(fn(a) { text(Some(a.1), "which") }), ["icon", "image"])
  t.draw()
  let before = runs.copy()
  assert_eq(before, [1, 1], msg="asking tells none")
  // (the icon's answer, between frames: its node alone, in the next frame)
  let icon = asked.iter().find_first(fn(a) { text(Some(a.1), "which") == "icon" }).unwrap()
  (icon.2)(@sffixture.fixture_peek_picture(icon.0, icon.1).unwrap())
  @ui.came_from_outside()
  assert_eq(runs, before, msg="nothing worked out before the frame")
  t.draw()
  assert_eq(runs, [before[0] + 1, before[1]])
  let key = @sfbase.link_picture_told(src, "ws1/st1", url, page, "icon")
  assert_true(key != "" && key != "!", msg=key)
  assert_true(t.find("[" + key + "]") is Some(_))
  assert_false(@sfbase.link_pictures_here_told(src, "ws1/st1", url, page), msg="the image still coming")
  t.draw()
  assert_eq(runs, [before[0] + 1, before[1]], msg="nothing again")
}

///|
test "a file peek's picture read by a node: none asked as it is drawn; told as it comes; the old views' read asks as it did" {
  @sfbase.reset()
  let asked = []
  let src = peek_pictures_source(asked)
  let peek = Some(@sffixture.fixture_file_peek("shots/list.png"))
  let runs = [0]
  let t = told_pictures_tester([fn() { @sfbase.file_peek_picture_told(src, "ws1/st1", "s-c1", "shots/list.png", None, peek) }], runs)
  assert_eq(asked.length(), 0)
  @sfbase.file_peek_picture_ask(src, "ws1/st1", "s-c1", "shots/list.png", None, peek)
  assert_eq(asked.map(fn(a) { a.0 }), ["file.peek.picture"])
  peek_pictures_answer(asked)
  t.draw()
  assert_eq(runs, [2])
  let shot = @sfbase.file_peek_picture_told(src, "ws1/st1", "s-c1", "shots/list.png", None, peek)
  assert_true(shot != "" && shot != "!", msg=shot)
  // (the old views' read: the same key, asked no more)
  assert_eq(@sfbase.file_peek_picture(src, "ws1/st1", "s-c1", "shots/list.png", None, peek), shot)
  assert_eq(asked.length(), 0)
  // (a picture its value names none of: none, asked of nothing)
  assert_eq(@sfbase.file_peek_picture_told(src, "ws1/st1", "s-c1", "a.txt", None, Some({ "kind": "text" })), "!")
}
