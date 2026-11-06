// Lent's lenders kept by their nodes' places (lent.mbt): nodes of two trees at the same place, and a place made again
// in one tree, each finding its own lender's value, none another's; what is let go gone from the place's bucket.

///|
/// A tree whose node under its root lends `value` of `kind`, and a node under that reads it into `found`.
fn lending_tree(kind : Lent[String], value : String, found : Ref[String?], lender : Ref[View?]) -> Tree {
  Tree::new(fn(root) {
    root.box(fn(a) {
      lender.val = Some(a)
      a.lends(kind, value) |> ignore
      a.box(fn(b) { found.val = b.lent(kind) }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
}

///|
test "lent: two trees lending at the same place each find their own; one let go, the other's still found" {
  let kind : Lent[String] = Lent::new()
  let (fa, fb) = (Ref(None), Ref(None))
  let (la, lb) = (Ref(None), Ref(None))
  let a = lending_tree(kind, "a", fa, la)
  let b = lending_tree(kind, "b", fb, lb)
  a.frame(400.0, 300.0) |> ignore
  b.frame(400.0, 300.0) |> ignore
  assert_eq(la.val.unwrap().at, lb.val.unwrap().at, msg="the same place in both")
  assert_eq((fa.val, fb.val), (Some("a"), Some("b")))
  assert_eq(kind.lenders.get(la.val.unwrap().at).map(fn(e) { e.length() }), Some(2))
  a.dispose()
  assert_eq(la.val.unwrap().lent(kind), None, msg="the let go tree's finds none")
  assert_eq(lb.val.unwrap().lent(kind), Some("b"))
  assert_eq(kind.lenders.get(lb.val.unwrap().at).map(fn(e) { e.length() }), Some(1))
  b.dispose()
  assert_true(kind.lenders.is_empty(), msg="every bucket gone")
}

///|
test "lent: a place made again in the same tree finds its new lender's value, the old node none" {
  let kind : Lent[String] = Lent::new()
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let value = @signals.signal("old", same=fn(a, b) { a == b })
  let lenders : Array[View] = []
  let found : Array[String?] = []
  let t = Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(s) {
      s.box(fn(a) {
        lenders.push(a)
        a.lends(kind, @signals.untracked(fn() { value.get() })) |> ignore
        a.box(fn(b) { found.push(b.lent(kind)) }) |> ignore
      }) |> ignore
    })
  }, time=fn() { 0.0 })
  t.frame(400.0, 300.0) |> ignore
  on.set(false)
  t.frame(400.0, 300.0) |> ignore
  assert_true(kind.lenders.is_empty(), msg="let go with its node")
  value.set("new")
  on.set(true)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(found, [Some("old"), Some("new")])
  let (old, made) = (lenders[0], lenders[1])
  assert_eq(old.lent(kind), None, msg="the old node, let go, finds none")
  assert_eq(made.lent(kind), Some("new"))
  // (its place made again: the same place, another making)
  assert_eq(old.at, made.at, msg="the place made again")
  assert_true(old.gen != made.gen)
  t.dispose()
  assert_true(kind.lenders.is_empty())
}
