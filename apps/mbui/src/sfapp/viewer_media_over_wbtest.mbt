// What a film's thumbnail draws over its picture (its capsule), carried by its still as it flies: an old view of its
// own (viewer_tree.mbt's viewer_player) that reads what its chat registered last (Viewer::thumb_over), told as what
// decides it changes (note_thumb's `said`, thumbs_said); none of the thumbnail's place read, so that the thumbnail
// moving alone builds it not again. A made-up chat registers the thumbnail: its words what a signal says, its place
// where another puts it.

///|
/// The viewer of 演示录屏.mp4 (1280 by 720) over a made-up chat whose thumbnail of it (`y` from the top) draws `word`
/// over its picture (its builds counted in `built`), the viewer's node beside the chat, as the shells have it, 390 wide:
/// the thumbnail as big as the player draws its picture there (390 by 219.375), so that its flight moves it alone, as
/// big all the way. What draws its words says how big it is drawn in, each time, in `sizes`; the display's frames 60
/// a second, said before it flies (its flight's frames the same at any MBUI_TEST_FPS).
fn over_tester(
  word : @signals.Signal[String],
  y : @signals.Signal[Double],
  built : Ref[Int],
  sizes? : Array[(Double, Double)] = [],
) -> @ui.Tester {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, _) { "" } }
  let id = "ws1/st1/s-c1/uploads/fx/演示录屏.mp4"
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(root) {
      root.box(fn(v) {
        v.grow(Is(1.0)) |> ignore
        @ui.old(v, fn(c) {
          // (what decides what it draws over its picture said with it, the words captured as they are now)
          let w = word.get()
          c.box(style=@ui.style(w=Full, h=Full), fn() {
            c.box(style=@ui.style(h=Fixed(y.get())), fn() {  }) |> ignore
            let b = c.box(style=@ui.style(w=Fixed(390.0), h=Fixed(390.0 * 720.0 / 1280.0)), fn() {  })
            @sfbase.note_thumb(c, id, b, 12.0, picture="", over=fn(_) {
              built.val += 1
              sizes.push((c.width, c.height))
              c.text(w) |> ignore
            }, said=w)
          })
          |> ignore
        })
        .over(Is(true))
        |> ignore
        @sfbase.viewer_node(v, src, fn() { v.window() })
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  t.set_frame_period(1000.0 / 60.0)
  t.draw()
  t
}

///|
/// 演示录屏.mp4 opened over the made-up chat (as its thumbnail's press opens it).
fn over_open() -> Unit {
  let a : Attachment = {
    name: "演示录屏.mp4",
    path: "uploads/fx/演示录屏.mp4",
    size: 5242880.0,
    width: 1280.0,
    height: 720.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  @sfbase.open_preview("ws1/st1", "s-c1", a)
}

///|
/// What draws a thumbnail's words drawn in as big each time from build `from` on (the last as the clock's own frames
/// began) as then.
fn over_sized(sizes : Array[(Double, Double)], from : Int) -> Unit raise {
  guard from >= 0 && sizes.get(from) is Some(at) && at.0 > 0.0 else { fail("what draws its words never built: \{Repr(sizes)}") }
  for k in from..<sizes.length() {
    assert_true(sizes[k] == at, msg="drawn in as big each time from \{from}: \{Repr(sizes)}")
  }
}

///|
/// Where `word` is drawn now, seen (x, y, w, h), its alpha above nothing.
fn over_word(t : @ui.Tester, word : String) -> Array[(Double, Double, Double, Double)] {
  t.words().filter(fn(w) { w.0 == word && w.5 > 0.0 }).map(fn(w) { (w.1, w.2, w.3, w.4) })
}

///|
test "a film flying in (its still as big all the way), its thumbnail's words changed as it flies (between frames, the clock's alone): what its still carries says them from the next frame, built again as it is told" {
  let word = @signals.signal("一", same=fn(a, b) { a == b })
  let y = @signals.signal(200.0, same=fn(a, b) { a == b })
  let built = Ref(0)
  let sizes : Array[(Double, Double)] = []
  let t = over_tester(word, y, built, sizes~)
  over_open()
  t.draw()
  let v = viewer.get().unwrap()
  // (past the frames the test's steps build whole: the clock's own frames from here)
  t.frame_at(t.next_frame_time())
  assert_true(v.flies && !v.fly_back && v.fly.goes_at(t.ctx().moment()), msg="flying in")
  guard over_word(t, "一") is [(_, _, w0, h0)] else { fail("its words over its still: \{Repr(over_word(t, "一"))}") }
  let from = sizes.length() - 1
  word.set("二")
  t.frame_at(t.next_frame_time())
  assert_true(v.flies && v.fly.goes_at(t.ctx().moment()), msg="still flying")
  assert_true(over_word(t, "一").is_empty(), msg="its words gone")
  guard over_word(t, "二") is [(_, _, w1, h1)] else { fail("its new words over its still: \{Repr(over_word(t, "二"))}") }
  assert_true(h1 == h0 && w1 > 0.0 && w0 > 0.0, msg="as high")
  // (what draws them as big each time it was drawn from its first frame of the clock's on: built again as it was told,
  // not as it was resized)
  over_sized(sizes, from)
}

///|
/// A film flying in over the made-up chat, three of the clock's frames past its first, its thumbnail moved down 60 at
/// the second of them (`moved`) or not: where its words are drawn at the last, and how many times what draws them was
/// built after the first.
fn over_moving(moved : Bool) -> ((Double, Double, Double, Double), Int) raise {
  let word = @signals.signal("一", same=fn(a, b) { a == b })
  let y = @signals.signal(200.0, same=fn(a, b) { a == b })
  let built = Ref(0)
  let sizes : Array[(Double, Double)] = []
  let t = over_tester(word, y, built, sizes~)
  // (its builds counted alone: what the default check builds again besides, none)
  t.check_looks(false)
  over_open()
  t.draw()
  let v = viewer.get().unwrap()
  t.frame_at(t.next_frame_time())
  guard over_word(t, "一") is [_] else { fail("its words over its still: \{Repr(over_word(t, "一"))}") }
  let base = built.val
  let from = sizes.length() - 1
  t.frame_at(t.next_frame_time())
  if moved {
    y.set(260.0)
  }
  t.frame_at(t.next_frame_time())
  t.frame_at(t.next_frame_time())
  assert_true(v.flies && !v.fly_back && v.fly.goes_at(t.ctx().moment()), msg="still flying in")
  guard over_word(t, "一") is [at] else { fail("its words over its still: \{Repr(over_word(t, "一"))}") }
  over_sized(sizes, from)
  (at, built.val - base)
}

///|
test "a film flying in (its still as big all the way), its thumbnail moved alone as it flies (its words, its size the same): what its still carries moved with it, not built again" {
  let (still, built_still) = over_moving(false)
  let (moved, built_moved) = over_moving(true)
  assert_eq((built_still, built_moved), (0, 0), msg="not built again")
  assert_true(moved.1 > still.1 + 1.0 && moved.2 == still.2 && moved.3 == still.3, msg="moved down with it, as big: \{Repr(moved)}, not moved \{Repr(still)}")
}
