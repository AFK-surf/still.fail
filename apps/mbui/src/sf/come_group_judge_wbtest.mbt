// What comes or goes down one column at one moment with what was on its way there (mbui's ComeGroup), judged frame by
// frame (sizes steady, at a rate's frames under MBUI_TEST_MOTION): rows coming called back as another comes in their
// place, the whole going on or turned back.

///|
/// A column of rows by `keys` on grounds of their own, 下 under them: 处理中 (`first` tall) comes, and `after` ms on
/// the rows are `then`; walked a frame of 60 a second at a time to the end of it all.
fn come_group_case(first : Double, after : Double, then : Array[String]) -> Unit {
  let keys = @signals.signal(["头"], same=fn(a, b) { a == b })
  let tall : Map[String, Double] = { "头": 20.0, "处理中": first, "回复": 71.1, "另": 30.0 }
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=600.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(col) {
      col.each(fn() { keys.get() }, fn(k) { k }, fn(row, k) {
        row.width(Is(Some(200.0))).height(Is(Some(tall[k.get()]))).ground(Is(0x336699FFL)) |> ignore
      })
      col.box(fn(b) { b.width(Is(Some(200.0))).height(Is(Some(20.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  keys.set(["头", "处理中"])
  t.run_for(after)
  keys.set(then)
  t.run_for(@ui.move_most_ms + 200.0)
}

///|
/// How long 处理中 has been opening when one of 100 comes under it: all but open.
let cg_all_but_open : Double = 200.0

///|
/// How long that one has been opening fast when 处理中 is called back: two frames of 60 a second.
let cg_two_frames : Double = 33.3

///|
test "come group, judged: 处理中 all but open (42.65 of 44) called back, the answer in its place" {
  come_group_case(44.0, 183.3, ["头", "回复"])
}

///|
test "come group, judged: 处理中 most of the way open (40.5 of 44) called back, the answer in its place" {
  come_group_case(44.0, 133.3, ["头", "回复"])
}

///|
test "come group, judged: one of 100 a third of the way open called back, one of 30 in its place: the whole turned back" {
  come_group_case(100.0, 50.0, ["头", "另"])
}

///|
test "come group, judged: one of 100 most of the way open called back, one of 30 in its place: the whole turned back" {
  come_group_case(100.0, 150.0, ["头", "另"])
}

///|
test "come group, judged: 处理中 all but open called back as one of 100 is opening fast: the whole going on, 处理中 with it" {
  let keys = @signals.signal(["头"], same=fn(a, b) { a == b })
  let tall : Map[String, Double] = { "头": 20.0, "处理中": 44.0, "长": 100.0 }
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=600.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(col) {
      col.each(fn() { keys.get() }, fn(k) { k }, fn(row, k) {
        row.width(Is(Some(200.0))).height(Is(Some(tall[k.get()]))).ground(Is(0x336699FFL)) |> ignore
      })
      col.box(fn(b) { b.width(Is(Some(200.0))).height(Is(Some(20.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  keys.set(["头", "处理中"])
  t.run_for(cg_all_but_open)
  keys.set(["头", "处理中", "长"])
  t.run_for(cg_two_frames)
  keys.set(["头", "长"])
  t.run_for(@ui.move_most_ms + 200.0)
}
