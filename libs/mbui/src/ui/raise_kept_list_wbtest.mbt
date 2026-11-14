// A row of a page's list said to be drawn over the scrim (View::over_scrim: a row held while its press waits, lifted
// over what is put up) is drawn after the scrim whenever one is up, on a host keeping groups (every platform's but the
// web's), painted as a device paints: the list drawn whole as one from what it kept while the row was not yet over a
// scrim stood in for it, the row left under the scrim that came, till 2026-11-12 (sfapp's press_waits, the two-run
// check's baseline, #5654).

///|
/// The red row's place among the frame's instances against the scrim's (-1 where either is not drawn), for each frame
/// drawn from the scrim's coming on: the row of a page's list of three held over the scrim from the start, the list
/// drawn and kept, then a layer with a scrim put up over it.
fn raised_kept_order() -> String {
  let open = @signals.signal(false)
  let held = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  t.set_groups(true)
  t.set_rows_on_pixels(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      col.scrolls_window(@view.Scroll::list(), fn() { [0, 1, 2] }, est=40.0, follows=fn() { false }, fn(b, k) {
        b.box(fn(r) {
          r.height(Is(Some(40.0))).ground(Is(if k == 1 { raised_row } else { 0xCCCCCCFFL })) |> ignore
          if k == 1 {
            r.over_scrim(By(fn() { held.get() })) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }, around=fn(c) {
    // (the window's tree, then over it an old view's layer with a scrim, as a menu put up over a page is)
    old_views_here(c)
    if open.get() {
      c.overlay("over", modal=true, scrim=raised_scrim, fn() {
        c.box(w=Px(100.0), h=Px(40.0), bg=0x00FF00FFL, fn() {  }) |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  t.run_for(move_most_ms)
  let seen : Array[String] = []
  t.each_frame(
    Some(fn() {
      let insts = t.drawn_instances()
      // (the last instance drawn so: the red row's ground; the scrim, black over the whole window, as faded in as it is)
      let last = fn(pick : (Array[Double]) -> Bool) {
        let mut found = -1
        for i, x in insts {
          if x[5] == 0.0 && pick(x) {
            found = i
          }
        }
        found
      }
      let row = last(fn(x) { x[8] == 1.0 && x[9] == 0.0 && x[10] == 0.0 && x[11] == 1.0 })
      let scrim = last(fn(x) { x[8] == 0.0 && x[9] == 0.0 && x[10] == 0.0 && x[11] > 0.0 && x[2] >= 300.0 && x[3] >= 200.0 })
      seen.push(if row < 0 || scrim < 0 { "-" } else if row > scrim { "over" } else { "under" })
    }),
  )
  open.set(true)
  t.draw()
  t.run_for(move_most_ms)
  t.each_frame(None)
  // (each frame's, the same ones in a row said once)
  let said : Array[String] = []
  for s in seen {
    if said.last() != Some(s) {
      said.push(s)
    }
  }
  said.join(" ")
}

///|
/// The held row's ground: red, whole.
let raised_row : Int64 = 0xFF0000FFL

///|
/// The layer's scrim: black, half seen through, dark enough that what is under it shows darkened.
let raised_scrim : Int64 = 0x00000080L

///|
test "a row of a page's list said over the scrim, its list kept, is drawn over a scrim that comes" {
  inspect(raised_kept_order(), content="over")
}
