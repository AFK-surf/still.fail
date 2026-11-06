// An external file's paths can change layout in their recipient. Finding any other file target after that callback
// must not advance the new motion inside the same event.

///|
test "external files: a path recipient keeps its growing box at the drop's moment" {
  let duration = 200.0
  let height = @signals.signal(40.0)
  let minimum = @signals.signal(0.0)
  let box : Ref[@view.View?] = Ref(None)
  let group : Ref[MoveGroup?] = Ref(None)
  let held = Ref(0.0)
  let t = @ui.Tester::new(fn(_) {}, w=200.0, h=300.0, platform=0, stable=false)
  @ui.set_view_app(fn(root) {
    root.lies_along(Is(End)) |> ignore
    root.box(fn(v) {
      box.val = Some(v)
      v.width(Is(Some(100.0))).height(By(fn() { Some(height.get()) })).min_height(By(fn() { Some(minimum.get()) })) |> ignore
      let g = moves_together(v, fn() { (height.get(), minimum.get()) }, spec=tween(duration, ease=Linear))
      group.val = Some(g)
      g.add(v, reshapes=true)
      let editor = @ui.field(v, @ui.Field::new(), placeholder="drop paths")
      @ui.words_into_node(v, editor, paths=fn(_) {
        held.val = v.placed_now().3 + g.ground_of(v).3
        minimum.set(held.val)
        height.set(40.0)
        true
      })
      @ui.files_into_node(v, fn(_) {}) |> ignore
    }) |> ignore
  })
  t.draw()
  height.set(140.0)
  t.run_for(duration / 2.0)
  let (x, y, _, h) = t.rect_of("drop paths").unwrap()
  t.drop_files(x + 1.0, y + h / 2.0, [("file", b"x")], paths=["/tmp/file"])
  t.draw()
  assert_eq(held.val, 90.0)
  t.run_for(duration / 4.0)
  let b = box.val.unwrap()
  assert_eq(b.placed_now().3 + group.val.unwrap().ground_of(b).3, held.val)
}
