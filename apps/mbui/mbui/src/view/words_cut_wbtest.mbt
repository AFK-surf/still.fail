// Whether a node's words show cut short as of a change's moment (View::words_cut_now): read there, laid out once as of
// that moment and placed by in the frame after, never read in a binding.

///|
/// A tree of a box `w` wide (as it changes) holding one line of ten characters (70 wide as a test's tree measures them),
/// cut to the box where it is narrower: the tree and the box.
fn cut_tree(w : @signals.Signal[Double]) -> (Tree, View) {
  let held : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.box(fn(b) {
        held.val = Some(b)
        b.width(By(fn() { Some(w.get()) })) |> ignore
        b.box(fn(n) { n.words(Is("一二三四五六七八九十")).words_look(Is({ ..words_plain, wrap: false })) |> ignore }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  (t, held.val.unwrap())
}

///|
test "words cut short as of a change's moment: in what holds them too; read in the change that narrowed them, as of it" {
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let (t, b) = cut_tree(w)
  assert_false(b.words_cut_now())
  let cut = Ref(false)
  t.event(10.0, fn() {
    w.set(40.0)
    cut.val = b.words_cut_now()
  })
  assert_true(cut.val, msg="as of the change that narrowed them")
  t.frame(400.0, 300.0) |> ignore
  assert_true(b.words_cut_now())
  t.event(20.0, fn() {
    w.set(70.0)
    cut.val = b.words_cut_now()
  })
  assert_false(cut.val, msg="as wide as they are: whole")
}

///|
test "words_cut_now at a change's moment lays out once, as of it, and the frame after places by that layout: no more than the change lays out unread; read where nothing changed, none" {
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let (t, b) = cut_tree(w)
  let laid = fn() { t.work().computes }
  let c0 = laid()
  // (nothing told since the last frame: nothing laid out to read it, nor in the frame after)
  b.words_cut_now() |> ignore
  t.frame(400.0, 300.0) |> ignore
  assert_eq(laid() - c0, 0)
  // (read in the change: once, then, the frame after laying out nothing more)
  t.event(10.0, fn() {
    w.set(40.0)
    b.words_cut_now() |> ignore
  })
  assert_eq(laid() - c0, 1, msg="laid out as of the change")
  t.frame(400.0, 300.0) |> ignore
  assert_eq(laid() - c0, 1, msg="the frame after: placed by it")
  // (the same change not read: laid out once, in its frame)
  t.event(20.0, fn() { w.set(400.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(laid() - c0, 2)
}

///|
test "words_cut_now read in a binding is said a fault, where its node was made; read where a change is taken, none" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let in_binding : Ref[String?] = Ref(None)
  let in_handler : Ref[String?] = Ref(Some(""))
  let t = Tree::new(
    fn(root) {
      root.box(fn(b) {
        b
        .words(Is("一二三"))
        .width(By(fn() {
          if on.get() {
            in_binding.val = b.tree.cut_read_said()
          }
          Some(100.0)
        }))
        |> ignore
        b.reacts(fn() { on.get() }, fn(_) { in_handler.val = b.tree.cut_read_said() })
      })
      |> ignore
    },
    time=fn() { 0.0 },
    sources=true,
  )
  t.frame(400.0, 300.0) |> ignore
  t.event(10.0, fn() { on.set(true) })
  t.frame(400.0, 300.0) |> ignore
  guard in_binding.val is Some(said) else { fail("not said in a binding") }
  assert_true(
    said.has_prefix("WORDSCUT words_cut_now read in a binding of a node made at ") &&
    said.contains("src/view/words_cut_wbtest.mbt:") &&
    said.contains("read only at a change's moment"),
    msg=said,
  )
  assert_eq(in_handler.val, None)
}
