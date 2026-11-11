// A box of a height said that holds a line of words (words_box.mbt's box_at): its own style at the default size of
// words, the very one, kept; as high as its words' line where the system's size of words draws that higher.

///|
test "at the default size of words a fill chip's, a tag's and a video capsule's box is its own style, the very object, asked twice" {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) { root.box(fn(_b) {  }) |> ignore })
  t.draw()
  for _ in 0..<2 {
    assert_true(physical_equal(chip_box_at(1.0, false), chip_box))
    assert_true(physical_equal(chip_box_at(1.0, true), chip_box_small))
    assert_true(physical_equal(box_at(tag_kept, tag_box, tag_h, tag_words, 1.0), tag_box))
    assert_true(
      physical_equal(
        box_at(video_capsule_kept, video_capsule_box, video_capsule_h, video_capsule_words, 1.0),
        video_capsule_box,
      ),
    )
  }
}

///|
test "at 1.3 a tag's box is another, the same one asked again; at 1 its own again" {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) { root.box(fn(_b) {  }) |> ignore })
  t.draw()
  let large = box_at(tag_kept, tag_box, tag_h, tag_words, 1.3)
  assert_true(!physical_equal(large, tag_box))
  assert_true(physical_equal(box_at(tag_kept, tag_box, tag_h, tag_words, 1.3), large))
  assert_true(physical_equal(box_at(tag_kept, tag_box, tag_h, tag_words, 1.0), tag_box))
}

///|
test "a tag 18 high at the default size of words; at 1.3 as high as its words' line, holding them" {
  let tag : Ref[@view.View?] = Ref(None)
  let made = fn(scale : Double) {
    let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) {
      root.box(fn(row) {
        row.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
        row.box(fn(g) {
          tag.val = Some(g)
          tag_node(g, fn() { "CC" })
        })
        |> ignore
      })
      |> ignore
    })
    t.set_font_scale(scale)
    t.draw()
    let h = tag.val.unwrap().laid_size().1
    let f = t.fixed_outgrown()
    t.set_font_scale(1.0)
    (h, f)
  }
  let (h1, f1) = made(1.0)
  assert_eq(h1, tag_h)
  assert_eq(f1, [])
  let (h13, f13) = made(1.3)
  assert_eq(h13, @ui.sp_at(1.3, 16.0))
  assert_true(h13 > tag_h)
  assert_eq(f13, [])
}
