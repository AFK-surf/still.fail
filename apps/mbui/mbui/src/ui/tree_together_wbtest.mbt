// One node of the window's tree drawing a picture (View::picture), left out of its row where the row has not the room
// (View::drops) and turned (View::turn): each of the three as its own says, none of them doing anything of another's.

///|
/// The picture's pieces drawn in the last frame (kind 11): where and how big, and how far turned.
fn picture_pieces(t : Tester) -> Array[(Double, Double, Double, Double, Double)] {
  t.drawn_instances().filter(fn(i) { i[5] == 11.0 }).map(fn(i) { (i[0], i[1], i[2], i[3], i[32]) })
}

///|
/// A row as wide as `w` says holding a box 200 wide and, after it, a node 56 across drawing `picture` turned as `turn`
/// says, the first its row leaves out (the node given back in `it`).
fn together_row(
  w : @signals.Signal[Double],
  turn : @signals.Signal[Double],
  picture : @signals.Signal[@pixels.Vector?],
  it : Ref[@view.View?],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).fits(Is(true)).width(By(fn() { Some(w.get()) })).height(Is(Some(56.0))) |> ignore
      row.box(fn(g) { g.width(Is(Some(200.0))) |> ignore }) |> ignore
      it.val = Some(
        row.box(fn(v) {
          v
          .width(Is(Some(56.0)))
          .height(Is(Some(56.0)))
          .picture(By(fn() { picture.get() }))
          .drops(Is(1))
          .turn(By(fn() { turn.get() }))
          |> ignore
        }),
      )
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a node with a picture, left out of its row and turned: turned, its picture not cut again nor anything laid out; another picture, turned as it was; left out, none of it drawn, turned meanwhile; back, the new picture where it was, turned as said meanwhile" {
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let turn = @signals.signal(0.0, same=fn(a, b) { a == b })
  let picture : @signals.Signal[@pixels.Vector?] = @signals.signal(Some(round_picture))
  let it : Ref[@view.View?] = Ref(None)
  let t = together_row(w, turn, picture, it)
  let v = it.val.unwrap()
  let at_rest = picture_pieces(t)
  let rects = fn(ps : Array[(Double, Double, Double, Double, Double)]) { ps.map(fn(p) { (p.0, p.1, p.2, p.3) }) }
  let turns = fn(ps : Array[(Double, Double, Double, Double, Double)]) {
    ps.fold(init=[], fn(rs : Array[Double], p) { if rs.contains(p.4) { rs } else { rs + [p.4] } })
  }
  // turned: its picture's pieces where they were, turned; nothing cut again, nothing laid out
  let cut = view_pictures_cut.val
  let laid = view_tree().unwrap().work().laid
  turn.set(quarter)
  t.frame()
  let turned = picture_pieces(t)
  let turned_said = (
    rects(turned) == rects(at_rest),
    turns(turned),
    view_pictures_cut.val - cut,
    view_tree().unwrap().work().laid - laid,
    v.left_out(),
  )
  // another picture: drawn turned as the node was
  picture.set(Some(small_picture))
  t.frame()
  let other = picture_pieces(t)
  let other_said = (other.length() > 0, other.length() != at_rest.length(), turns(other), v.left_out())
  // left out: none of it drawn; turned meanwhile
  w.set(240.0)
  t.frame()
  let out_said = (picture_pieces(t).length(), v.left_out())
  turn.set(0.5)
  t.frame()
  let out_turned = picture_pieces(t).length()
  // back: the other picture where it was, turned as said while it was out
  w.set(400.0)
  t.frame()
  let back = picture_pieces(t)
  assert_eq(
    (turns(at_rest), turned_said, other_said, out_said, out_turned, rects(back) == rects(other), turns(back), v.left_out()),
    ([0.0], (true, [quarter], 0, 0, false), (true, true, [quarter], false), (0, true), 0, true, [0.5], false),
  )
}
