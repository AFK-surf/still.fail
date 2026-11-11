// A plain column alone, for scripts/instrbench.sh's col scenes (MBUI_FIXTURE=col:N): what one child put in or taken out
// of a column costs as it holds 17 or 170, as mbui's src/ui/column_change_wbtest.mbt counts it. N rows 20 tall
// (View::each, each made at once), each a press with words; a spinner over the column turning all along, so that frames
// are drawn while it rests. At its own moments, from as it is made: a row put in at its middle at 1000 ms, taken out
// again at 2000 ms (col.drive).

///|
/// The rows a col scene holds: 17, or 170 where it says so.
fn col_scene_rows(mode : String) -> Int {
  if mode == "col:170" {
    170
  } else {
    17
  }
}

///|
/// The scene in `root`: the spinner's bar over the column, which takes the rest.
fn col_scene(root : @view.View, n : Int) -> Unit {
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  root.box(fn(top) {
    top.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    top.box(fn(bar) {
      bar.height(Is(Some(44.0))).padding(Is((15.0, 15.0, 15.0, 15.0))) |> ignore
      @sf.spinner_node(bar) |> ignore
    })
    |> ignore
    top.box(fn(col) {
      col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      col.each(fn() { keys.get() }, fn(k) { k }, fn(row, item) {
        row
        .height(Is(Some(20.0)))
        .words(By(fn() { "row \{item.get()}" }))
        .on_press(fn() {  })
        .says(By(fn() { Some(@view.said(Button, label="row \{item.get()}")) }))
        |> ignore
      }, at_once=true)
      let at = col.cause_at()
      col.at_moment(at + 1000.0, fn() {
        let ks = keys.untracked().copy()
        ks.insert(n / 2, 100000)
        keys.set(ks)
      })
      |> ignore
      col.at_moment(at + 2000.0, fn() { keys.set(keys.untracked().filter(fn(k) { k != 100000 })) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}
