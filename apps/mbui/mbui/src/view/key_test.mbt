// A key a node's (View::on_key): asked of those that may take input, the one drawn last first, each as it was asked
// (its node and what it said then): one let go, or its place another's since, or said anew, asked nothing of this key;
// a node let go holds nothing of what it said.

///|
test "keys: the one drawn last first, each as of the key's moment: one under it let go and its place made another's by what the one over it does, asked as it was then (the change it said committed with the key's, whole), the new one not; the next key, the new one's turn" {
  let told : Array[String] = []
  let b_on = @signals.signal(true, same=fn(a, b) { a == b })
  let c_on = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @view.Tree::new(
    fn(root) {
      // (B under, then C where B was once B is let go, then A over all of it)
      root.show(fn() { b_on.get() }, fn(v) {
        v.on_key(fn(_k) {
          told.push("B")
          false
        })
        |> ignore
      })
      root.show(fn() { c_on.get() }, fn(v) {
        v.on_key(fn(_k) {
          told.push("C")
          false
        })
        |> ignore
      })
      root.box(fn(a) {
        a.on_key(fn(_k) {
          told.push("A")
          // (B let go, C made in its place, by what the key does here)
          b_on.set(false)
          c_on.set(true)
          false
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.key_at(1, 0, 10.0), false)
  assert_eq(told.copy(), ["A", "B"])
  // the next key: C's turn, under A
  told.clear()
  assert_eq(t.key_at(1, 0, 20.0), false)
  assert_eq(told.copy(), ["A", "C"])
}

///|
test "keys: a node let go holds nothing of what it said; the tree let go asks none" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let told : Array[Int] = []
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v.on_key(fn(k) {
          told.push(k.code)
          true
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.key_at(5, 0, 10.0), true)
  there.set(false)
  assert_eq(t.key_at(6, 0, 20.0), false)
  there.set(true)
  t.dispose()
  assert_eq(t.key_at(7, 0, 30.0), false)
  assert_eq(told.copy(), [5])
}

///|
test "keys: what a node under said a key does said anew by the one over it as this key goes (the same function): the key not asked of it as said anew" {
  let told : Array[String] = []
  let b_view : Ref[@view.View?] = Ref(None)
  let b_key = fn(_k : @view.Key) {
    told.push("B")
    false
  }
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b_view.val = Some(b)
        b.on_key(b_key) |> ignore
      })
      |> ignore
      root.box(fn(a) {
        a.on_key(fn(_k) {
          told.push("A")
          match b_view.val {
            Some(b) => b.on_key(b_key) |> ignore
            None => ()
          }
          false
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.key_at(1, 0, 10.0), false)
  assert_eq(told.copy(), ["A"])
}
