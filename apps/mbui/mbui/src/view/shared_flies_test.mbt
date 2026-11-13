// Whether a shared node flies (View::flies), followed: what draws by it made again as its flight begins and as it ends,
// in the frame of each, the same whatever reads it first, at 60, 120, 24 and 7 a second.

///|
/// A thumbnail that stays (View::shared's `stays`) and, while `open` is said, a picture by its id that moves, then a
/// box drawn half seen while that picture flies, whole once it does not (what reads View::flies in a binding). The
/// tree, open, the picture, the box.
fn flies_scene() -> (@view.Tree, @signals.Signal[Bool], Ref[@view.View?], Ref[@view.View?]) {
  let open = @signals.signal(false)
  let big : Ref[@view.View?] = Ref(None)
  let reader : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)) |> ignore
      p.box(fn(t) {
        t.width(Is(Some(40.0))).height(Is(Some(40.0))).ground(Is(red)).shared(Is("a"), straight, stays=true) |> ignore
      })
      |> ignore
      p.show(fn() { open.get() }, fn(o) {
        o.over(Is(true)) |> ignore
        o.box(fn(b) {
          big.val = Some(b)
          b
          .offset(Is((50.0, 300.0)))
          .width(Is(Some(300.0)))
          .height(Is(Some(200.0)))
          .ground(Is(blue))
          .shared(Is("a"), straight, with_stays=true)
          |> ignore
        })
        |> ignore
        o.box(fn(r) {
          reader.val = Some(r)
          r
          .width(Is(Some(20.0)))
          .height(Is(Some(20.0)))
          .ground(Is(green))
          .alpha(By(fn() {
            match big.val {
              Some(b) => if b.flies() { 0.5 } else { 1.0 }
              None => 1.0
            }
          }))
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  (tree, open, big, reader)
}

///|
test "View::flies followed: what draws by it half seen from the frame its flight sets out in, whole from the frame at its end, the same as it is read, at every rate" {
  for fps in [60.0, 120.0, 24.0, 7.0] {
    let (tree, open, big, reader) = flies_scene()
    tree.frame(400.0, 800.0, now=0.0) |> ignore
    tree.event(1000.0, fn() { open.set(true) })
    tree.frame(400.0, 800.0, now=1000.0) |> ignore
    let b = big.val.unwrap()
    let r = reader.val.unwrap()
    let end = match tree.flight_ends_at("a") {
      Some(e) => e
      None => fail("\{fps}: no flight")
    }
    assert_true(b.flies(), msg="\{fps}: flies as it sets out")
    let mut now = 1000.0
    while now < end + 400.0 {
      // (read the other way about every frame: what the box drew, then whether it flies, the same)
      let drawn = alpha_of(tree, r)
      let flies = b.flies()
      assert_eq(drawn, if flies { 0.5 } else { 1.0 }, msg="\{fps} at \{now}: drawn \{drawn}, flies \{flies}")
      assert_eq(flies, now < end, msg="\{fps} at \{now}: flies \{flies}, its end \{end}")
      now = now + 1000.0 / fps
      tree.frame(400.0, 800.0, now~) |> ignore
    }
  }
}
