// A page's list alone, for scripts/instrbench.sh's list scenes (MBUI_FIXTURE=list:N): what a frame of a windowed list
// (View::scrolls_window) runs as its keys number 30 or 1,500, nothing of the app's around it. N keys, each a block of
// words 44 or 64 tall (counted 60 till measured), the list following its foot; a spinner over it turning all along (as
// a chat's agent at work), so that frames are drawn while the list rests. At its own moments, from as it is made: a key
// appended at its foot at 1000 ms (the cause frame), asked to its first key at 6000 ms and back to its foot at 6500 ms,
// each at once (a jump from its foot to its top and back); between those, the drive's drags and fling (list.drive).
// MBUI_FIXTURE=list-sight:N: the same, what it has in sight told to a handler keeping a count (ListPlace::on_sight).

///|
/// The keys a list scene holds: 30, or 1,500 where it says so.
fn list_scene_keys(mode : String) -> Int {
  if mode == "list:1500" || mode == "list-sight:1500" {
    1500
  } else {
    30
  }
}

///|
/// The scene in `root`: the spinner's bar over the list, which takes the rest.
fn list_scene(root : @view.View, n : Int, sight? : Bool = false) -> Unit {
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  // (`sight`: what it has in sight told to a handler keeping a count of it, as one marking what is read would)
  if sight {
    let told = Ref(0)
    place.on_sight(fn(_) { told.val = told.val + 1 })
  }
  root.box(fn(col) {
    col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    col.box(fn(bar) {
      bar.height(Is(Some(44.0))).padding(Is((15.0, 15.0, 15.0, 15.0))) |> ignore
      @sf.spinner_node(bar) |> ignore
    })
    |> ignore
    col.box(fn(o) {
      o.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=60.0, follows=fn() { true }, place~, fn(b, k) {
        b.box(fn(r) {
          r
          .height(Is(Some(if k % 3 == 0 { 64.0 } else { 44.0 })))
          .words(Is("message \{k}: words as a chat's line has them, a few of them"))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      let at = o.cause_at()
      o.at_moment(at + 1000.0, fn() { keys.set(Array::makei(n + 1, fn(i) { i })) }) |> ignore
      o.at_moment(at + 6000.0, fn() { place.bring(0) }) |> ignore
      o.at_moment(at + 6500.0, fn() { place.to_end(glide=false) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}
