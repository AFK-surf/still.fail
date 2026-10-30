// An island in an island (kept_nodes.mbt's part_nodes, RowNodes' `holder` and `inner`): what holds it built again,
// it put back among its nodes as it was where nothing it read changed; it told, what holds it built again with it.

///|
test "an island in an island: kept as the outer is built again, built again with it as what it read changes" {
  let outer_word = @signals.signal("a")
  let inner_word = @signals.signal("x")
  let builds = [0, 0]
  let t = Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.kept_part(
          c.id("outer"),
          "",
          fn() {
            // (not the Tester's build of each frame keeping none, to compare with: rows_check_begin)
            if !nodes_run.whole {
              builds[0] = builds[0] + 1
            }
            c.box(pad=8.0, gap=4.0, fn() {
              c.text("outer \{outer_word.get()}") |> ignore
              c.kept_part(
                c.id("inner"),
                "",
                fn() {
                  if !nodes_run.whole {
                    builds[1] = builds[1] + 1
                  }
                  c.box(pad=4.0, fn() { c.text("inner \{inner_word.get()}") |> ignore }) |> ignore
                },
                own=true,
              )
              c.text("after") |> ignore
            })
            |> ignore
          },
          own=true,
        )
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  t.clock_frame()
  let (o, i) = (builds[0], builds[1])
  // nothing read changed: both kept
  t.clock_frame()
  assert_eq(builds[0], o)
  assert_eq(builds[1], i)
  // the outer's word: the outer built again, the inner put back among its nodes
  outer_word.set("b")
  t.clock_frame()
  assert_true(t.find("outer b") is Some(_))
  assert_true(t.find("inner x") is Some(_))
  assert_true(t.find("after") is Some(_))
  assert_true(builds[0] > o)
  assert_eq(builds[1], i)
  // kept both again, the inner's nodes among the outer's
  let o2 = builds[0]
  t.clock_frame()
  t.clock_frame()
  assert_eq(builds[0], o2)
  assert_true(t.find("inner x") is Some(_))
  // the inner's word: both built again, the inner's words new
  inner_word.set("y")
  t.clock_frame()
  assert_true(t.find("inner y") is Some(_))
  assert_true(t.find("outer b") is Some(_))
  assert_true(builds[1] > i)
  // the outer built again once more: the inner as it was last built, put back
  let i2 = builds[1]
  outer_word.set("c")
  t.clock_frame()
  assert_true(t.find("outer c") is Some(_))
  assert_true(t.find("inner y") is Some(_))
  assert_eq(builds[1], i2)
}
