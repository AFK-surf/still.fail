// A list's rows, built as the list is laid out, built on the page's time on top it is on (Ctx::page_stint: what a
// picture is asked for on), as what is built beside the list is; one kept showing only what it read built again as its
// page is put on top anew; what is built after them, off the page, on none.

///|
test "a list's rows built on their page's time on top: kept ones built again as it is put on top anew, what is built after them on none" {
  let nav = Nav::new(0)
  // (what each row of page 0's list was built on, and the row of a list off the stack; what its first row was built on
  // where rows are kept (not the Tester's build of each frame keeping none, to compare with: rows_check_begin))
  let seen : Map[Int, Int] = Map([])
  let kept_built : Ref[Int?] = Ref(None)
  let beside = Ref(-1)
  let t = Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      c.column(w=Fill(1.0), h=Px(300.0), fn() {
        c.nav(
          nav,
          fn(p) {
            if p == 0 {
              c.list("rows", 3, 40.0, rows_read=true, fn(i) {
                seen[i] = c.page_stint()
                if i == 0 && !nodes_run.whole {
                  kept_built.val = Some(c.page_stint())
                }
                c.text("row \{i}", wrap=false) |> ignore
              })
              |> ignore
            } else {
              c.text("page \{p}", wrap=false) |> ignore
            }
          },
          bg=0xFFFFFFFFL,
        )
        |> ignore
      })
      |> ignore
      c.list("beside", 1, 40.0, fn(_) {
        beside.val = c.page_stint()
        c.text("beside", wrap=false) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.set_rows_on_pixels(true)
  t.draw()
  let first = nav.pages[0].stint
  let built_first = (seen.get(0), beside.val)
  // (another page over it, and back to it while that still slides in: it built all along, on top anew, its time on top
  // a new one)
  nav.push(1)
  let part = move_ms(t.w) / 4.0
  t.run_for(part)
  nav.pop() |> ignore
  t.run_for(move_ms(t.w))
  t.draw()
  let again = nav.pages[0].stint
  assert_true(again != first)
  assert_eq((built_first, seen.get(0), kept_built.val, beside.val), ((Some(first), 0), Some(again), Some(again), 0))
}
