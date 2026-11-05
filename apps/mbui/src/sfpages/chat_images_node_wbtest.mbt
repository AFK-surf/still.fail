///|
test "a picture's progress does not work out another picture's retained nodes" {
  let images = @sfbase.ChatImages::new()
  let heard_b : Ref[(Json) -> Unit] = Ref(fn(_) {  })
  let (reads_a, reads_b) = (Ref(0), Ref(0))
  let picture_a = fn() -> MediaPicture {
    reads_a.val += 1
    let key = images.get("s", "a", "mem:a", fn(_, _) {  })
    { kind: "image", key, hash: "", sent: false, held: images.held("a"), unreached: images.unreached("a") }
  }
  let picture_b = fn() -> MediaPicture {
    reads_b.val += 1
    let key = images.get("s", "b", "mem:b", fn(heard, _) { heard_b.val = heard })
    { kind: "image", key, hash: "", sent: false, held: images.held("b"), unreached: images.unreached("b") }
  }
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=400.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    media_content_node(root, picture_a, fn() { 160.0 }, fn() { 120.0 }, FitCover, fn() { 8.0 })
    media_content_node(root, picture_b, fn() { 160.0 }, fn() { 120.0 }, FitCover, fn() { 8.0 })
  })
  t.draw()
  t.frame()
  t.frame()
  let (a_before, b_before) = (reads_a.val, reads_b.val)
  assert_true(a_before > 0 && b_before > 0)
  (heard_b.val)({ "loaded": 5.0, "total": 10.0 })
  t.frame()
  assert_true(reads_b.val > b_before, msg="b's nodes follow b's progress")
  assert_eq(reads_a.val, a_before, msg="b's progress must leave a's nodes alone")
}
