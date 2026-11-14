///|
/// Each node whose taking input is followed (View::takes_input) told as it is when all of it is asked anew: where it
/// differs, each said.
fn inputs_differ(t : Tree) -> Array[String] {
  let out = []
  for i, n in t.nodes {
    match n.input_cell {
      Some(s) if n.live => {
        let told = s.untracked()
        let now = !t.pressless_at(i)
        if told != now {
          out.push("node \{i}: told \{told}, takes \{now}")
        }
      }
      _ => ()
    }
  }
  out
}

///|
test "whether each takes input, told where rows come, go, move and are said to take no press, is what all of it asked anew says" {
  // (each list's keys and the rows said to take no press, all set at once in each frame: from a seed, the same each run)
  let lists = @signals.signal([[1, 2, 3], [4, 5]], same=fn(a, b) { a == b })
  let off = @signals.signal([2], same=fn(a, b) { a == b })
  let list = fn(v : View, i : Int) {
    v.box(fn(l) {
      l.each(fn() { lists.get()[i] }, fn(k) { k }, fn(row, k) {
        row.presses(By(fn() { !off.get().contains(k.get()) })) |> ignore
        row.box(fn(line) {
          line.box(fn(w) { @signals.untracked(fn() { w.takes_input() }) |> ignore }) |> ignore
          @signals.untracked(fn() { line.takes_input() }) |> ignore
        })
        |> ignore
        @signals.untracked(fn() { row.takes_input() }) |> ignore
      })
    })
    |> ignore
  }
  let t = Tree::new(
    fn(root) {
      root.box(fn(page) {
        list(page, 0)
        page.box(fn(mid) { list(mid, 1) }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(inputs_differ(t), [])
  let mut seed = 4242
  let next = fn(n : Int) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed / 65536 % n
  }
  // (the changes, each what the lists hold and the row said to take no press after it, if another)
  let changes : Array[(Array[Array[Int]], Array[Int]?)] = []
  let mut ls = lists.get()
  let mut key = 100
  while changes.length() < 200 {
    ls = ls.map(fn(l) { l.copy() })
    let l = ls[next(2)]
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
    let all : Array[Int] = []
    for l in ls {
      all.append(l)
    }
    let none = if next(2) == 0 && !all.is_empty() { Some([all[next(all.length())]]) } else { None }
    changes.push((ls, none))
  }
  for i, c in changes {
    lists.set(c.0)
    match c.1 {
      Some(o) => off.set(o)
      None => ()
    }
    t.frame(390.0, 844.0) |> ignore
    assert_eq(inputs_differ(t), [], msg="change \{i}")
  }
}
