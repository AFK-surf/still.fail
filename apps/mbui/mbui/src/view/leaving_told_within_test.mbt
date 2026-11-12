// The moment a node starts leaving (its structure lets it go: closing its room on a Move, at once, or another picked in
// its place) is told to it and to all it holds by what they said to do then (View::on_leaving), once, before what it
// binds rests; what lives with one of them (View::lives_with) goes then. What reads data in what is leaving is at rest
// (told nothing); what reads leaving() from outside it is told as ever.

///|
/// A layer over all of it holding a box that lives with `inner`; a column: words, then what `here` shows (a box `outer`
/// saying "甲", a box `inner` in it), then words, its show `at_once` or not, then words saying whether `outer` is
/// leaving. What each one's on_leaving is done
/// put in `told`; what a reaction in `outer` reading `other` is told, in `outer_read`; words outside it saying whether
/// `outer` is leaving.
fn told_leaving_tree(
  here : @signals.Signal[Bool],
  at_once : Bool,
  told : Array[String],
  other : @signals.Signal[Int],
  outer_read : Array[Int],
  kept : Ref[@view.View?],
  kept_pressed? : Ref[Int] = Ref(0),
) -> @view.Tree {
  let outer : Ref[@view.View?] = Ref(None)
  @view.Tree::new(fn(root) {
    // (a layer for what lives elsewhere, made first: there as what is shown is made)
    let layer : Ref[@view.View?] = Ref(Some(root.box(fn(l) { l.over(Is(true)) |> ignore })))
    root.box(fn(col) {
      col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("上")) |> ignore }) |> ignore
      col.show(fn() { here.get() }, at_once~, fn(a) {
        outer.val = Some(a)
        a.words(Is("甲")).on_leaving(fn() { told.push("outer") }) |> ignore
        a.reacts(fn() { other.get() }, at_start=false, fn(o) { outer_read.push(o) })
        a.box(fn(r) {
          r.height(Is(Some(40.0))).on_leaving(fn() { told.push("inner") }) |> ignore
          match layer.val {
            Some(l) =>
              kept.val = Some(
                l
                .box(fn(k) {
                  k
                  .width(Is(Some(50.0)))
                  .height(Is(Some(20.0)))
                  .words(Is("旁"))
                  .presses(Is(true))
                  .on_press(fn() { kept_pressed.val += 1 })
                  |> ignore
                })
                .lives_with(r),
              )
            None => ()
          }
        })
        |> ignore
      })
      col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("下")) |> ignore }) |> ignore
      // (outside what leaves, made after it: whether it is leaving)
      col.box(fn(b) {
        b.height(Is(Some(30.0))).words(By(fn() { if outer.val.map(fn(o) { o.leaving() }).unwrap_or(false) { "走" } else { "在" } })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Whether `words` are drawn.
fn told_drawn(t : @view.Tree, words : String) -> Bool {
  t.drawn().iter().any(fn(d) { d.words == words })
}

///|
test "closing its room on a Move: it and what it holds told once at the moment it starts leaving; what lives with what it holds gone then; what reads data in it at rest; what reads its leaving from outside told" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let other = @signals.signal(0, same=fn(a, b) { a == b })
  let (told, outer_read) = ([], [])
  let kept : Ref[@view.View?] = Ref(None)
  let t = told_leaving_tree(here, false, told, other, outer_read, kept)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  other.set(1)
  assert_eq((told_drawn(t, "旁"), outer_read), (true, [1]))
  here.set(false)
  other.set(2)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(told, ["outer", "inner"])
  assert_true(told_drawn(t, "甲"), msg="still drawn as it leaves")
  assert_true(!told_drawn(t, "旁") && !t.press(10.0, 10.0), msg="what lives with it out of sight and of reach as it starts leaving")
  assert_true(kept.val.unwrap().alive(), msg="kept till what it lives with is let go")
  assert_eq(outer_read, [1], msg="what reads data in it at rest")
  assert_true(told_drawn(t, "走"), msg="what reads its leaving from outside told")
  t.frame(390.0, 844.0, now=600.0) |> ignore
  assert_eq((told, told_drawn(t, "甲"), kept.val.unwrap().alive()), (["outer", "inner"], false, false))
}

///|
test "going at once: it and what it holds told once, then let go; what lives with what it holds gone" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let other = @signals.signal(0, same=fn(a, b) { a == b })
  let (told, outer_read) = ([], [])
  let kept : Ref[@view.View?] = Ref(None)
  let t = told_leaving_tree(here, true, told, other, outer_read, kept)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  here.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq((told, told_drawn(t, "甲"), told_drawn(t, "旁"), kept.val.unwrap().alive()), (["outer", "inner"], false, false, false))
}

///|
test "another picked in its place: the one before told once as it goes" {
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let told : Array[Int] = []
  let t = @view.Tree::new(fn(root) {
    root.pick(fn() { which.get() }, fn(v, k) { v.height(Is(Some(40.0))).on_leaving(fn() { told.push(k) }) |> ignore })
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  which.set(1)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  t.frame(390.0, 844.0, now=600.0) |> ignore
  assert_eq(told, [0])
}

///|
test "called back as it leaves: told once; what lives with what it holds back, drawn and pressed again; leaving anew, told anew" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let other = @signals.signal(0, same=fn(a, b) { a == b })
  let (told, outer_read) = ([], [])
  let kept : Ref[@view.View?] = Ref(None)
  let pressed = Ref(0)
  let t = told_leaving_tree(here, false, told, other, outer_read, kept, kept_pressed=pressed)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  here.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  assert_false(t.press(10.0, 10.0), msg="what lives with it pressed no more")
  assert_eq((told, told_drawn(t, "旁"), pressed.val), (["outer", "inner"], false, 0))
  // (shown again before it has gone: the same nodes, back)
  here.set(true)
  t.frame(390.0, 844.0, now=48.0) |> ignore
  assert_true(t.press(10.0, 10.0), msg="pressed again")
  assert_eq((told, told_drawn(t, "旁"), kept.val.unwrap().alive(), pressed.val), (["outer", "inner"], true, true, 1))
  here.set(false)
  t.frame(390.0, 844.0, now=64.0) |> ignore
  assert_eq((told, told_drawn(t, "旁")), (["outer", "inner", "outer", "inner"], false))
}
