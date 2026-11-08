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
