// What a Way said makes built again says who said it: the line that sent it (Way::go) or put it (Way::put), never
// way.mbt's own, which every Way's motion shared, so a hang report's `why` (ui's journal: the places in built_why)
// named `motion/way.mbt:132` for any of them and none could be found from it (a 中屏 phone's hangs, 2026-11-14).

///|
#callsite(autofill(loc))
fn way_told_place(loc~ : SourceLoc) -> String {
  // (this file and line, as a SourceLoc says it: `path:line:col`, the column left off)
  let parts = loc.to_string().split(":").take(2).map(fn(v) { v.to_owned() }).collect()
  "\{parts[0]}:\{parts[1]}:"
}

///|
test "a frame built again for a Way gone on or put names the line that said it, not way.mbt" {
  let way = Way::new(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      // (in a part kept, as a page's are: built again alone for what it read, the frame saying where it was set)
      c.kept_part(c.id("part"), "", fn() {
        way.said()
        c.text("way", size=12.0) |> ignore
      })
    },
    w=200.0,
    h=200.0,
  )
  t.check_looks(false)
  t.draw()
  t.frame()
  let went = way_told_place(); way.go(1.0, lift_spring, at=t.time())
  t.frame()
  let why_go = t.built_why()
  // (put while it goes: there at once, from any moment)
  let put = way_told_place(); way.put(0.0)
  t.frame()
  let why_put = t.built_why()
  assert_true(why_go.contains(", set at \{went}"), msg=why_go)
  assert_false(why_go.contains("motion/way.mbt:"), msg=why_go)
  assert_true(why_put.contains(", set at \{put}"), msg=why_put)
  assert_false(why_put.contains("motion/way.mbt:"), msg=why_put)
}
