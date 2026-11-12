///|
/// The order as it is now (made again from what changed, Tree::order_again) against all of it made again: where they
/// differ, each said.
fn order_differs(t : Tree) -> Array[String] {
  let order = t.order.copy()
  let holder = t.order_holder.copy()
  let end = t.order_end.copy()
  let of = t.order_of.copy()
  let tops = t.tops.copy()
  t.order_whole = true
  t.order_again()
  let out = []
  if order != t.order {
    out.push("order \{Repr(order)} against \{Repr(t.order)}")
  }
  if holder != t.order_holder {
    out.push("holders \{Repr(holder)} against \{Repr(t.order_holder)}")
  }
  if end != t.order_end {
    out.push("ends \{Repr(end)} against \{Repr(t.order_end)}")
  }
  for i, n in t.nodes {
    if n.live && (of[i] != t.order_of[i] || tops[i] != t.tops[i]) {
      out.push("node \{i}: at \{of[i]} top \{tops[i]} against at \{t.order_of[i]} top \{t.tops[i]}")
    }
  }
  out
}

///|
test "the order made again from what holds what changed is the order made whole: rows come, go and move, what shows in a row, layers at the root, indexes given back and made again" {
  let keys = @signals.signal([1, 2, 3, 4], same=fn(a, b) { a == b })
  let open = @signals.signal(-1, same=fn(a, b) { a == b })
  let sheet = @signals.signal(false, same=fn(a, b) { a == b })
  let t = Tree::new(
    fn(root) {
      root.box(fn(top) { top.box(fn(_) {  }) |> ignore }) |> ignore
      root.box(fn(page) {
        page.box(fn(list) {
          list.each(fn() { keys.get() }, fn(k) { k }, fn(row, k) {
            row.box(fn(line) {
              line.box(fn(_) {  }) |> ignore
              line.show(fn() { open.get() == k.get() }, fn(s) {
                s.box(fn(w) { w.box(fn(_) {  }) |> ignore }) |> ignore
              })
            })
            |> ignore
            row.box(fn(_) {  }) |> ignore
          })
        })
        |> ignore
        page.box(fn(_) {  }) |> ignore
      })
      |> ignore
      root.show(fn() { sheet.get() }, fn(s) { s.box(fn(w) { w.box(fn(_) {  }) |> ignore }).stacked(Is(2)) |> ignore })
      root.box(fn(_) {  }).stacked(Is(1)) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(order_differs(t), [])
  let steps : Array[() -> Unit] = [
    fn() { keys.set([1, 2, 3, 4, 5]) },
    fn() { keys.set([0, 1, 2, 3, 4, 5]) },
    fn() { keys.set([0, 2, 4, 5]) },
    fn() { open.set(2) },
    fn() { keys.set([4, 2, 0, 5, 6]) },
    fn() {
      open.set(6)
      keys.set([4, 2, 7, 6])
    },
    fn() { sheet.set(true) },
    fn() {
      keys.set([8, 9])
      open.set(9)
    },
    fn() {
      sheet.set(false)
      keys.set([])
    },
    fn() { keys.set([1, 2, 3, 4, 5, 6, 7, 8]) },
  ]
  for step in steps {
    step()
    t.frame(390.0, 844.0) |> ignore
    assert_eq(order_differs(t), [])
  }
}

///|
test "the order made again from what changed is the order made whole, change after change of lists and what shows in their rows changed at once, indexes let go of in one made again in another" {
  // (each list's keys, which rows show what they hold, all set at once in each frame: from a seed, the same each run)
  let lists = @signals.signal([[1, 2, 3], [4, 5], [6, 7, 8]], same=fn(a, b) { a == b })
  let open = @signals.signal([2, 5], same=fn(a, b) { a == b })
  let list = fn(v : View, i : Int) {
    v.box(fn(l) {
      l.each(fn() { lists.get()[i] }, fn(k) { k }, fn(row, k) {
        row.box(fn(line) {
          line.show(fn() { open.get().contains(k.get()) }, fn(s) { s.box(fn(w) { w.box(fn(_) {  }) |> ignore }) |> ignore })
        })
        |> ignore
      })
    })
    |> ignore
  }
  let t = Tree::new(
    fn(root) {
      root.box(fn(page) {
        list(page, 0)
        page.box(fn(mid) { list(mid, 1) }) |> ignore
        list(page, 2)
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(order_differs(t), [])
  let mut seed = 12345
  let next = fn(n : Int) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed / 65536 % n
  }
  // (the changes, each what the lists hold and which rows show what they hold after it)
  let changes : Array[(Array[Array[Int]], Array[Int]?)] = []
  let mut ls = lists.get()
  let mut key = 100
  while changes.length() < 300 {
    ls = ls.map(fn(l) { l.copy() })
    // (one to three lists changed: a row gone, one come, two moved)
    for _ in 0..<(1 + next(3)) {
      let l = ls[next(3)]
      match next(3) {
        0 => if l.length() > 0 { l.remove(next(l.length())) |> ignore }
        1 => {
          key = key + 1
          l.insert(next(l.length() + 1), key)
        }
        _ => if l.length() > 1 {
          let a = l.remove(next(l.length()))
          l.insert(next(l.length() + 1), a)
        }
      }
    }
    let all : Array[Int] = []
    for l in ls {
      all.append(l)
    }
    let shown = if next(2) == 0 || all.is_empty() { None } else { Some([all[next(all.length())], all[next(all.length())]]) }
    changes.push((ls, shown))
  }
  for i, c in changes {
    lists.set(c.0)
    match c.1 {
      Some(o) => open.set(o)
      None => ()
    }
    t.frame(390.0, 844.0) |> ignore
    assert_eq(order_differs(t), [], msg="change \{i}")
  }
}
