// What is let go on the window's tree from outside (drop.mbt's "words" and "drop" with paths): on a node that takes
// them for its field (@ui.words_into: a composer's capsule), beside the field, into it at its caret as a paste's, the
// field taking the focus; files with their paths on one that takes them so (@ui.paths_into), given where they are, not
// read; each as the frame that takes it begins. On what takes neither, nothing.

///|
/// A node 300 wide, 40 in round a field of the tree's holding `f` ("the field", 10 high), that takes words let go on it
/// for its field and, where `paths`, files by their paths (what it is given put in `taken`); under it a node taking
/// nothing ("beside it", 40 high). The Tester.
fn tree_drops_tester(f : @ui.Field, taken : Array[String], paths : Bool) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=300.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      col.box(fn(cap) {
        cap.padding(Is((40.0, 40.0, 40.0, 40.0))).on_press(fn() { f.focus() }) |> ignore
        @ui.field(cap, f, placeholder="the field", font_size=10.0, max_lines=1) |> ignore
        @ui.words_into(cap, f) |> ignore
        if paths {
          @ui.paths_into(cap, f, fn(ps) {
            for p in ps {
              taken.push(p.path)
            }
          })
          |> ignore
        }
      })
      |> ignore
      col.box(fn(b) { b.height(Is(Some(40.0))).on_press(fn() {  }) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "words let go on a node of the tree's beside the field it takes them for (words_into): at its caret, as a paste's, the field taking the focus; beside it on what takes none, nothing" {
  let f = @ui.Field::new(text="ab")
  let t = tree_drops_tester(f, [], false)
  let (ex, ey, _, _) = t.rect_of("the field").unwrap()
  let before = f.focused()
  // (on the node, well over its field)
  t.drop_words(ex + 50.0, ey - 30.0, "cd")
  t.frame()
  let (taken, focused) = (f.text(), f.focused())
  // (on the node under it, which takes none: nothing)
  t.drop_words(ex + 50.0, ey + 70.0, "zz")
  t.frame()
  assert_eq((before, taken, f.selection(), focused, f.text()), (false, "abcd", (4, 4), true, "abcd"))
}

///|
test "files let go with their paths on a node of the tree's that takes them so (paths_into), beside its field: given where they are, not read, the field as it was; on one that takes only words for its field, their paths there as words" {
  let f = @ui.Field::new(text="ab")
  let taken : Array[String] = []
  let t = tree_drops_tester(f, taken, true)
  let (ex, ey, _, _) = t.rect_of("the field").unwrap()
  t.drop_files(ex + 50.0, ey - 30.0, [("a.txt", b"x")], paths=["/Users/me/a.txt"])
  t.frame()
  let by_paths = (taken.copy(), f.text())
  // (one taking only words for its field: their paths as its words, at its caret)
  let g = @ui.Field::new(text="ab")
  let none : Array[String] = []
  let u = tree_drops_tester(g, none, false)
  let (gx, gy, _, _) = u.rect_of("the field").unwrap()
  u.drop_files(gx + 50.0, gy - 30.0, [("a.txt", b"x")], paths=["/Users/me/a.txt"])
  u.frame()
  assert_eq((by_paths, none, g.text()), ((["/Users/me/a.txt"], "ab"), [], "ab/Users/me/a.txt"))
}

///|
test "words and files' paths let go on a field of the tree's itself: in where they were let go, a paste's, the field taking the focus" {
  let f = @ui.Field::new(text="ab")
  let t = tree_drops_tester(f, [], false)
  let (ex, ey, _, eh) = t.rect_of("the field").unwrap()
  // (Latin 5 across at 10 high: between its `a` and its `b`)
  t.drop_words(ex + 5.0, ey + eh / 2.0, "cd")
  t.frame()
  let words = (f.text(), f.selection(), f.focused())
  t.drop_files(ex + 1.0, ey + eh / 2.0, [("a.txt", b"x")], paths=["/a.txt"])
  t.frame()
  assert_eq((words, f.text()), (("acdb", (3, 3), true), "/a.txtacdb"))
}

///|
/// A window 300 by 300 whose whole is an old view's (as the app's shell under its pages), a box of it taking files let
/// go on it (what it is given counted in `old`); over its top 150 a page of the tree's (`page`: shown as it says) whose
/// words take no press, the page taking files by their paths (put in `taken`); a modal layer of the tree's at the foot,
/// 20 high, as `modal` says. The Tester.
fn drops_over_old(
  taken : Array[String],
  old : Ref[Int],
  page : @signals.Signal[Bool],
  modal : @signals.Signal[Bool],
) -> @ui.Tester {
  let f = @ui.Field::new(text="")
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=300.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      @ui.old(b, fn(c) {
        let here = c.id("old box")
        c.on_files(here, held=fn(_) {  }, take=fn(_, _) { Some(fn(_) { old.val = old.val + 1 }) })
        c.box(id=here, w=Fill(1.0), h=Fill(1.0), taps=false, points=true, fn() { c.text("old words") |> ignore }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { page.get() }, at_once=true, fn(s) {
      s.box(fn(p) {
        p.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(150.0))).ground(Is(0xFFFFFFFFL)) |> ignore
        p.box(fn(w) { w.words(Is("a message")).height(Is(Some(20.0))) |> ignore }) |> ignore
        @ui.paths_into(p, f, fn(ps) {
          for x in ps {
            taken.push(x.path)
          }
        })
        |> ignore
      })
      |> ignore
    })
    root.show(fn() { modal.get() }, at_once=true, fn(s) {
      s.box(fn(m) {
        m.over(Is(true)).offset(Is((0.0, 280.0))).width(Is(Some(300.0))).height(Is(Some(20.0))).modal(Is(true)) |> ignore
      })
      |> ignore
    })
  })
  t.draw()
  t
}

///|
test "files let go on a page's words, which take no press, over an old view filling the window: the page's (paths_into), not the old view's; beside the page, the old view's; under a modal layer, nobody's" {
  let taken : Array[String] = []
  let old = Ref(0)
  let page = @signals.signal(true, same=fn(a, b) { a == b })
  let modal = @signals.signal(false, same=fn(a, b) { a == b })
  let t = drops_over_old(taken, old, page, modal)
  let (wx, wy, _, wh) = t.rect_of("a message").unwrap()
  // (on the page's words: the page takes them by their paths)
  t.drop_files(wx + 5.0, wy + wh / 2.0, [("a.txt", b"x")], paths=["/a.txt"])
  t.frame()
  t.frame()
  let on_words = (taken.copy(), old.val)
  // (on the page where it draws only its ground: the page's too)
  t.drop_files(150.0, 120.0, [("b.txt", b"x")], paths=["/b.txt"])
  t.frame()
  t.frame()
  let on_ground = (taken.copy(), old.val)
  // (below the page, on the old view: the old view's)
  t.drop_files(150.0, 220.0, [("c.txt", b"x")], paths=["/c.txt"])
  t.frame()
  t.frame()
  let on_old = (taken.copy(), old.val)
  // (a modal layer of the tree's up: the page under it takes none)
  modal.set(true)
  t.draw()
  t.drop_files(wx + 5.0, wy + wh / 2.0, [("d.txt", b"x")], paths=["/d.txt"])
  t.frame()
  t.frame()
  assert_eq((on_words, on_ground, on_old, (taken.length(), old.val)), (
    (["/a.txt"], 0),
    (["/a.txt", "/b.txt"], 0),
    (["/a.txt", "/b.txt"], 1),
    (2, 1),
  ))
}

///|
test "words let go on a page's words, which take no press, over an old view: into the field the page takes them for (words_into)" {
  let f = @ui.Field::new(text="ab")
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=300.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      @ui.old(b, fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), taps=false, points=true, fn() {  }) |> ignore }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(p) {
      p.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(150.0))) |> ignore
      p.box(fn(w) { w.words(Is("a message")).height(Is(Some(20.0))) |> ignore }) |> ignore
      @ui.field(p, f, placeholder="the field", font_size=10.0, max_lines=1) |> ignore
      @ui.words_into(p, f) |> ignore
    })
    |> ignore
  })
  t.draw()
  let (wx, wy, _, wh) = t.rect_of("a message").unwrap()
  t.drop_words(wx + 5.0, wy + wh / 2.0, "cd")
  t.frame()
  assert_eq(f.text(), "abcd")
}

///|
test "files let go on a page that takes them by their paths only while it says so: taken so then; else their paths into the field it takes words for" {
  let f = @ui.Field::new(text="")
  let by_path = @signals.signal(true, same=fn(a, b) { a == b })
  let taken : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=300.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(p) {
      p.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(150.0))) |> ignore
      p.box(fn(w) { w.words(Is("a message")).height(Is(Some(20.0))) |> ignore }) |> ignore
      @ui.field(p, f, placeholder="the field", font_size=10.0, max_lines=1) |> ignore
      @ui.paths_into(
        p,
        f,
        fn(ps) {
          for x in ps {
            taken.push(x.path)
          }
        },
        takes=fn() { by_path.get() },
      )
      |> @ui.words_into(f)
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (wx, wy, _, wh) = t.rect_of("a message").unwrap()
  t.drop_files(wx + 5.0, wy + wh / 2.0, [("a.txt", b"x")], paths=["/a.txt"])
  t.frame()
  let first = (taken.copy(), f.text())
  by_path.set(false)
  t.drop_files(wx + 5.0, wy + wh / 2.0, [("b.txt", b"x")], paths=["/b.txt"])
  t.frame()
  assert_eq((first, (taken, f.text())), ((["/a.txt"], ""), (["/a.txt"], "/b.txt")))
}
