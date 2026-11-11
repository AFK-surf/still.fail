// narrow_retry_node and narrow_empty_node beside the old view's narrow_retry and narrow_empty, in one window: the old at
// its left (hosted in a node: @ui.old), the node at its right, each in a column as wide; what each draws, where and how
// big, and what a press on each does, with touch and with keyboard and mouse.

///|
/// A window of `platform` holding `old` (an old view's) in a column at its left and `node` 400 further across, each 360
/// wide; at rest.
fn narrow_beside(platform : Int, old : (@ui.Ctx) -> Unit, node : (@view.View) -> Unit) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=400.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(360.0))).height(Is(Some(400.0))) |> ignore
      @ui.old(h, old).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(40.0))) |> ignore }) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(360.0))).height(Is(Some(400.0))) |> ignore
      node(h)
    })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What is drawn in the column from `x0`, each its kind, where it stands in the column's terms and its size, to a
/// hundredth, in one order; and its words, each where it stands and how big.
fn narrow_drawn(t : @ui.Tester, x0 : Double) -> (Array[String], Array[String]) {
  let r = fn(x : Double) { ((x * 100.0).round() / 100.0).to_string() }
  let drawn = t.drawn_instances()
    // (not a shape's pieces, kind 12: not in the window's terms, drawn_instances_keyed's)
    .filter(fn(a) { a[5] != 12.0 && a[0] >= x0 - 0.5 && a[0] < x0 + 399.5 && a[2] > 0.0 && a[3] > 0.0 })
    .map(fn(a) { "\{a[5]}@\{r(a[0] - x0)},\{r(a[1])} \{r(a[2])}x\{r(a[3])}" })
  drawn.sort()
  let words = t.words()
    .filter(fn(w) { w.1 >= x0 - 0.5 && w.1 < x0 + 399.5 && w.5 > 0.0 })
    .map(fn(w) { "\{w.0}@\{r(w.1 - x0)},\{r(w.2)} \{r(w.3)}x\{r(w.4)}" })
  words.sort()
  (drawn, words)
}

///|
/// Presses the words `words` in the column from `x0`, in their middle.
fn narrow_press(t : @ui.Tester, x0 : Double, words : String) -> Unit {
  let w = t.words().filter(fn(w) { w.0 == words && w.1 >= x0 - 0.5 && w.1 < x0 + 399.5 })
  guard w.length() == 1 else { @halt.saying("\{words} from \{x0}: \{w.length()}") }
  t.tap(w[0].1 + w[0].3 / 2.0, w[0].2 + w[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
}

///|
test "narrow_retry_node: what could not be read and 重试 drawn where the old one's are, as big; 重试 pressed, retried" {
  let words = "无法读取这个文件夹：权限不足，请到 station 上查看它的设置后再试一次"
  for platform in [2, 0] {
    let tried : Array[String] = []
    let t = narrow_beside(
      platform,
      fn(c) { narrow_retry(c, words, narrow_failed_words, fn() { tried.push("old") }) },
      fn(v) { narrow_retry_node(v, fn() { words }, narrow_failed_words, fn() { tried.push("new") }) },
    )
    let (old, new) = (narrow_drawn(t, 0.0), narrow_drawn(t, 400.0))
    assert_eq(new.1, old.1, msg="\{platform}: words")
    assert_eq(new.0, old.0, msg="\{platform}: drawn")
    narrow_press(t, 0.0, @sf.t("web-pages.drive.retry"))
    narrow_press(t, 400.0, @sf.t("web-pages.drive.retry"))
    assert_eq(tried, ["old", "new"], msg="\{platform}")
  }
}

///|
test "narrow_empty_node: nothing here, with what can be done about it and without, drawn where the old one's is, as big; its button pressed, done" {
  let words = @sf.t("web-main.rail.filesNone")
  for platform in [2, 0] {
    for act in [false, true] {
      let done : Array[String] = []
      let t = narrow_beside(
        platform,
        fn(c) {
          narrow_empty(c, words, if act { Some(("刷新", fn() { done.push("old") })) } else { None })
        },
        fn(v) {
          narrow_empty_node(v, fn() { words }, if act { Some((fn() { "刷新" }, fn() { done.push("new") })) } else { None })
        },
      )
      let (old, new) = (narrow_drawn(t, 0.0), narrow_drawn(t, 400.0))
      assert_eq(new.1, old.1, msg="\{platform} \{act}: words new \{new.1} old \{old.1}")
      assert_eq(new.0, old.0, msg="\{platform} \{act}: drawn new \{new.0.filter(fn(x) { !old.0.contains(x) })} old \{old.0.filter(fn(x) { !new.0.contains(x) })}")
      if act {
        narrow_press(t, 0.0, "刷新")
        narrow_press(t, 400.0, "刷新")
        assert_eq(done, ["old", "new"], msg="\{platform}")
      }
    }
  }
}
