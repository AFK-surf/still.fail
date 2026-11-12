// A row's note coming in between its title and what is wrong with it (link_row_node's `note` over its `trouble`, words
// said on the very node its show makes): as it opens its way, the red line under it moving down with it, its words no
// further than its way has got, never over that line (mbui's Content::clips_self; till 2026-11-11 drawn whole over it
// on the way).

///|
/// The moments looked at after the note is said and after it is taken back (ms).
let note_way_moments : Array[Double] = [8.0, 17.0, 33.0, 50.0, 100.0, 200.0, 400.0]

///|
test "a row's note coming in and going over the red line of what is wrong: never over that line on its way" {
  let note = @signals.signal("", same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=600.0, platform=2)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(col) {
      col.width(Is(Some(390.0))) |> ignore
      link_row_node(col, fn() { "性能记录" }, fn() {  }, note=fn() { note.get() }, trouble=fn() { "上次保存没有成功" })
      link_row_node(col, fn() { "下一行" }, fn() {  })
    })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  for said in ["保存在本机，不会上传到任何地方", ""] {
    let asked = t.time()
    note.set(said)
    for m in note_way_moments {
      t.run_for(asked + m - t.time())
      let over = t.words_over_now()
      assert_true(over.is_empty(), msg="\{if said != "" { "coming in" } else { "going" }} at \{m}: \{Repr(over)}")
    }
  }
}
