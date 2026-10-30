// A view made once does only the work a change asks for (docs/retained.md, the model): counted as work done or not
// (Tree::work), never by how long it took.

///|
/// A page: a title, a row of a count and a button that adds to it, under them a line whose look goes with the clock.
priv struct Page {
  tree : @view.Tree
  title : @signals.Signal[String]
  ground : @signals.Signal[Int64]
  count : @signals.Signal[Int]
  /// how many times the page's own making ran (it never runs again)
  made : Ref[Int]
  title_view : Ref[@view.View?]
  button : Ref[@view.View?]
}

///|
fn page() -> Page {
  let title = @signals.signal("今日", same=fn(a, b) { a == b })
  let ground = @signals.signal(0xFFEEEEEEL, same=fn(a, b) { a == b })
  let count = @signals.signal(0, same=fn(a, b) { a == b })
  let made = Ref(0)
  let title_view : Ref[@view.View?] = Ref(None)
  let button : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    made.val = made.val + 1
    root.pad(Is(8.0)) |> ignore
    title_view.val = Some(root.box(fn(t) { t.words(By(fn() { title.get() })).ground(By(fn() { ground.get() })) |> ignore }))
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(n) { n.words(By(fn() { "共 \{count.get()} 项" })) |> ignore }) |> ignore
      button.val = Some(
        r.box(fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(20.0))).on_press(fn() { count.set(count.get() + 1) }) |> ignore
        }),
      )
    })
    |> ignore
    // (its look by the clock: how opaque, from the time now)
    root.box(fn(l) {
      l.height(Is(Some(2.0))).alpha(By(fn() { if l.now() >= 1000.0 { 1.0 } else { l.now() / 1000.0 } })) |> ignore
    })
    |> ignore
  })
  { tree, title, ground, count, made, title_view, button }
}

///|
test "made once: what it shows changed many times, its nodes are the same nodes" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let made = p.tree.work().made
  let t = p.title_view.val.unwrap()
  for i in 0..<5 {
    p.title.set("第 \{i} 天")
    p.count.set(i)
    p.tree.frame(390.0, 844.0) |> ignore
  }
  assert_eq(p.made.val, 1)
  assert_eq(p.tree.work().made, made)
  // (the title the root holds first is the node made at the start, alive: the same index, the same making)
  assert_eq(p.tree.root().kids()[0].id(), t.id())
  assert_true(t.alive())
}

///|
test "its words changed: that binding alone runs, its node laid out again, nothing made" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let before = p.tree.work()
  p.title.set("明日待办")
  p.tree.frame(390.0, 844.0) |> ignore
  let after = p.tree.work()
  assert_eq(after.bound - before.bound, 1)
  assert_eq(after.made - before.made, 0)
  assert_eq(after.structure - before.structure, 0)
  assert_eq(after.computes - before.computes, 1)
  // its words measured again, its instance alone made again (its size the same: nothing else drawn elsewhere)
  assert_true(after.measured - before.measured >= 1)
  assert_eq(after.instances - before.instances, 1)
  assert_eq(after.changes - before.changes, 1)
  assert_true(p.tree.drawn().iter().any(fn(d) { d.words == "明日待办" }))
}

///|
test "its ground changed: painted again alone, nothing laid out" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let before = p.tree.work()
  p.ground.set(0xFFDDEEFFL)
  p.tree.frame(390.0, 844.0) |> ignore
  let after = p.tree.work()
  assert_eq(after.bound - before.bound, 1)
  assert_eq(after.computes - before.computes, 0)
  assert_eq(after.measured - before.measured, 0)
  assert_eq(after.instances - before.instances, 1)
}

///|
test "the clock alone going on: what reads it painted again, nothing built, nothing laid out" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let before = p.tree.work()
  p.tree.at(500.0)
  p.tree.frame(390.0, 844.0) |> ignore
  let drawn = p.tree.drawn()
  let after = p.tree.work()
  assert_eq(p.made.val, 1)
  assert_eq(after.made - before.made, 0)
  assert_eq(after.structure - before.structure, 0)
  assert_eq(after.computes - before.computes, 0)
  assert_eq(after.bound - before.bound, 1)
  assert_eq(after.measured - before.measured, 0)
  // (faded: composed again, nothing it draws made again)
  assert_eq(after.instances - before.instances, 0)
  assert_eq(after.composed - before.composed, 1)
  assert_true(drawn.iter().any(fn(d) { d.alpha == 0.5 }))
}

///|
test "nothing changed: a frame does nothing, the host given nothing new" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let before = p.tree.work()
  // (no node visited, no instance made, none measured, nothing laid out, nothing handed over)
  assert_true(!p.tree.frame(390.0, 844.0))
  assert_eq(p.tree.work(), before)
  assert_eq(p.tree.changed(), [])
}

///|
test "pressed: its callback writes the state outside any tracking, what reads it does the rest" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let (x, y, _, _) = p.button.val.unwrap().rect()
  let before = p.tree.work()
  assert_true(p.tree.press(x + 1.0, y + 1.0))
  p.tree.frame(390.0, 844.0) |> ignore
  let drawn = p.tree.drawn()
  assert_eq(p.count.get(), 1)
  assert_true(drawn.iter().any(fn(d) { d.words == "共 1 项" }))
  // (the count's words alone: no node made, no structure run)
  let after = p.tree.work()
  assert_eq(after.bound - before.bound, 1)
  assert_eq(after.made - before.made, 0)
  assert_eq(after.structure - before.structure, 0)
}

///|
priv struct Item {
  key : String
  words : String
} derive(Eq)

///|
/// A list of rows by key, each row's making counted, each row's words by its item.
fn list_tree(items : @signals.Signal[Array[Item]], rows_made : Ref[Int]) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.each(fn() { items.get() }, fn(it) { it.key }, fn(row, item) {
      rows_made.val = rows_made.val + 1
      row.words(By(fn() { item.get().words })) |> ignore
    })
  })
}

///|
fn row_ids(t : @view.Tree) -> Array[@view.NodeId] {
  // (the slot each holds its rows in: the root's only node)
  t.root().kids()[0].kids().map(fn(v) { v.id() })
}

///|
test "rows by key: moved as the order changes, never made again" {
  let items = @signals.signal([
    { key: "a", words: "甲" },
    { key: "b", words: "乙" },
    { key: "c", words: "丙" },
  ])
  let rows_made = Ref(0)
  let t = list_tree(items, rows_made)
  t.frame(390.0, 844.0) |> ignore
  let ids = row_ids(t)
  items.set([{ key: "c", words: "丙" }, { key: "a", words: "甲" }, { key: "b", words: "乙" }])
  t.frame(390.0, 844.0) |> ignore
  let drawn = t.drawn()
  assert_eq(rows_made.val, 3)
  assert_eq(row_ids(t), [ids[2], ids[0], ids[1]])
  // drawn in the new order, from the top
  let words = drawn.filter(fn(d) { d.words != "" }).map(fn(d) { d.words })
  assert_eq(words, ["丙", "甲", "乙"])
}

///|
test "a row's item changed: its words set again, the row not made again" {
  let items = @signals.signal([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  let rows_made = Ref(0)
  let t = list_tree(items, rows_made)
  t.frame(390.0, 844.0) |> ignore
  let ids = row_ids(t)
  let before = t.work()
  items.set([{ key: "a", words: "甲改" }, { key: "b", words: "乙" }])
  t.frame(390.0, 844.0) |> ignore
  let drawn = t.drawn()
  assert_eq(rows_made.val, 2)
  assert_eq(row_ids(t), ids)
  assert_eq(t.work().made - before.made, 0)
  assert_true(drawn.iter().any(fn(d) { d.words == "甲改" }))
}

///|
test "a row gone: let go, its bindings stopped, what it read no longer runs anything of it" {
  let items = @signals.signal([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  let rows_made = Ref(0)
  let outside = @signals.signal(0)
  let t = @view.Tree::new(fn(root) {
    root.each(fn() { items.get() }, fn(it) { it.key }, fn(row, item) {
      rows_made.val = rows_made.val + 1
      // (reads something of its own besides its item: once let go, a change of it runs nothing)
      row.words(By(fn() { "\{item.get().words} \{outside.get()}" })) |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  let gone = t.root().kids()[0].kids()[1]
  items.set([{ key: "a", words: "甲" }])
  t.frame(390.0, 844.0) |> ignore
  assert_true(!gone.alive())
  assert_eq(t.work().let_go, 1)
  let before = t.work()
  outside.set(1)
  t.frame(390.0, 844.0) |> ignore
  // the row left runs its binding; the one gone none
  assert_eq(t.work().bound - before.bound, 1)
}

///|
test "shown while it holds: made as it comes, let go as it goes, its holder's other nodes untouched" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let made = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.box(fn(b) { b.words(Is("在上")) |> ignore }) |> ignore
    root.show(fn() { on.get() }, fn(v) {
      made.val = made.val + 1
      v.words(Is("出现")) |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  let first = t.root().kids()[0]
  on.set(true)
  t.frame(390.0, 844.0) |> ignore
  let drawn = t.drawn()
  assert_eq(made.val, 1)
  assert_true(drawn.iter().any(fn(d) { d.words == "出现" }))
  on.set(false)
  t.frame(390.0, 844.0) |> ignore
  let drawn = t.drawn()
  assert_true(!drawn.iter().any(fn(d) { d.words == "出现" }))
  assert_eq(t.root().kids()[0].id(), first.id())
  assert_true(first.alive())
  assert_eq(t.work().let_go, 1)
}

///|
/// What a frame draws, without who each node is: where, how big and how it looks.
fn shown(d : Array[@view.Drawn]) -> Array[String] {
  d.map(fn(x) { "\{x.x},\{x.y} \{x.w}x\{x.h} \{x.words} \{x.ground} \{x.alpha}" })
}

///|
/// A list made once and changed a little at a time (rows come, go, move, change), against the same state made fresh:
/// what a frame draws is the same.
fn rows_tree(items : @signals.Signal[Array[Item]], wide : @signals.Signal[Bool]) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.pad(Is(4.0)) |> ignore
    root.show(fn() { wide.get() }, fn(v) { v.words(Is("宽")).height(Is(Some(10.0))) |> ignore })
    root.each(fn() { items.get() }, fn(it) { it.key }, fn(row, item) {
      row.row(Is(true)).ground(By(fn() { if item.get().words.length() > 1 { 0xFF00FF00L } else { 0L } })) |> ignore
      row.box(fn(w) { w.words(By(fn() { item.get().words })) |> ignore }) |> ignore
    })
  })
}

///|
test "changed a little at a time, it draws what the same state made fresh draws" {
  let mut s = 12345U
  let next = fn(n : Int) -> Int {
    s = s * 1664525U + 1013904223U
    (s >> 8).reinterpret_as_int() % n
  }
  let items = @signals.signal([{ key: "k0", words: "零" }])
  let wide = @signals.signal(false, same=fn(a, b) { a == b })
  let t = rows_tree(items, wide)
  let mut n = 1
  for step in 0..<200 {
    let now = items.get().copy()
    match next(5) {
      0 => {
        now.insert(next(now.length() + 1), { key: "k\{n}", words: "新\{n}" })
        n = n + 1
      }
      1 => if now.length() > 0 { now.remove(next(now.length())) |> ignore }
      2 =>
        if now.length() > 1 {
          let a = now.remove(next(now.length()))
          now.insert(next(now.length() + 1), a)
        }
      3 =>
        if now.length() > 0 {
          let i = next(now.length())
          now[i] = { ..now[i], words: now[i].words + "改" }
        }
      _ => wide.set(!wide.get())
    }
    items.set(now)
    let w = (300 + next(100)).to_double()
    t.frame(w, 844.0) |> ignore
    let kept = t.drawn()
    let made_fresh = rows_tree(@signals.signal(items.get()), @signals.signal(wide.get()))
    made_fresh.frame(w, 844.0) |> ignore
    let fresh = made_fresh.drawn()
    made_fresh.dispose()
    assert_eq(shown(kept), shown(fresh), msg="step \{step} w=\{w}\nkept  \{shown(kept)}\nfresh \{shown(fresh)}")
  }
}

///|
test "what holds a button drawn off and faded: the button drawn and pressed where it is drawn, as faded" {
  let off = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let button : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(fn(root) {
    root.box(fn(card) {
      card.pad(Is(10.0)).offset(By(fn() { off.get() })).alpha(Is(0.5)) |> ignore
      button.val = Some(
        card.box(fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(20.0))).on_press(fn() { pressed.val = pressed.val + 1 }) |> ignore
        }),
      )
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  let b = button.val.unwrap()
  let (x0, y0, _, _) = b.rect()
  assert_eq((x0, y0), (10.0, 10.0))
  let before = t.work()
  off.set((100.0, 50.0))
  t.frame(390.0, 844.0) |> ignore
  let drawn = t.drawn()
  // the card composed again where it is drawn, nothing laid out, nothing of it or its button made again, the button
  // not visited (where it is in the card is the same)
  assert_eq(t.work().computes - before.computes, 0)
  assert_eq(t.work().instances - before.instances, 0)
  assert_eq(t.work().composed - before.composed, 1)
  assert_eq(t.work().visited - before.visited, 1)
  let (x, y, _, _) = b.rect()
  assert_eq((x, y), (110.0, 60.0))
  let d = drawn.iter().find_first(fn(d) { d.id == b.id() }).unwrap()
  assert_eq((d.x, d.y, d.alpha), (110.0, 60.0, 0.5))
  // pressed where it was laid out: not there; where it is drawn: there
  assert_true(!t.press(x0 + 1.0, y0 + 1.0))
  assert_true(t.press(x + 1.0, y + 1.0))
  assert_eq(pressed.val, 1)
}

///|
test "two rows, one changed: the other row's bindings run nothing, given its items again as they were" {
  let items = @signals.signal([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  let runs : Map[String, Int] = {}
  let t = @view.Tree::new(fn(root) {
    root.each(fn() { items.get() }, fn(it) { it.key }, fn(row, item) {
      let k = item.get().key
      row.words(By(fn() {
        runs[k] = runs.get(k).unwrap_or(0) + 1
        item.get().words
      }))
      |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  // the same rows in new objects: nothing runs
  items.set([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(runs, { "a": 1, "b": 1 })
  // one of them changed: its binding alone
  let before = t.work()
  items.set([{ key: "a", words: "甲改" }, { key: "b", words: "乙" }])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(runs, { "a": 2, "b": 1 })
  assert_eq(t.work().bound - before.bound, 1)
}

///|
test "a property worked out to what it was: nothing set, nothing laid out, nothing drawn again" {
  let n = @signals.signal(3, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    // (the words depend on whether it is more than 2: 3 and then 4 both say the same)
    root.box(fn(b) { b.words(By(fn() { if n.get() > 2 { "多" } else { "少" } })) |> ignore }) |> ignore
    root.box(fn(b) { b.ground(By(fn() { if n.get() > 2 { 1L } else { 2L } })) |> ignore }) |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  let before = t.work()
  n.set(4)
  let again = t.frame(390.0, 844.0)
  let after = t.work()
  assert_eq(after.bound - before.bound, 2)
  assert_eq(after.same - before.same, 2)
  assert_eq(after.computes - before.computes, 0)
  assert_eq(after.instances - before.instances, 0)
  assert_true(!again)
}

///|
test "let go, a shown part holding rows, and then the whole tree: everything it read let go of, callbacks dropped" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let items = @signals.signal([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  let outside = @signals.signal(0)
  let top = @signals.signal("顶", same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(b) { b.words(By(fn() { top.get() })) |> ignore }) |> ignore
    root.show(fn() { on.get() }, fn(part) {
      part.each(fn() { items.get() }, fn(it) { it.key }, fn(row, item) {
        row.words(By(fn() { "\{item.get().words}\{outside.get()}" })).on_press(fn() { () }) |> ignore
      })
    })
  })
  t.frame(390.0, 844.0) |> ignore
  let alive = t.alive()
  assert_true(items.watched() && outside.watched())
  // the shown part goes: its rows with it, what they and it read let go of
  on.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_true(!items.watched())
  assert_true(!outside.watched())
  // (the part, its slot of rows, its two rows)
  assert_eq(alive - t.alive(), 4)
  assert_true(on.watched() && top.watched())
  // the whole tree
  t.dispose()
  assert_eq(t.alive(), 0)
  assert_true(!on.watched())
  assert_true(!top.watched())
  assert_true(!t.press(1.0, 1.0))
}

///|
/// Two columns side by side, each of a fixed width holding `n` lines: the first's lines' grounds and words, its own
/// offset, each a signal of the test's.
priv struct Columns {
  tree : @view.Tree
  grounds : Array[@signals.Signal[Int64]]
  words : Array[@signals.Signal[String]]
  off : @signals.Signal[(Double, Double)]
  left : Ref[@view.View?]
  right : Ref[@view.View?]
}

///|
fn columns(n : Int) -> Columns {
  let grounds = Array::makei(n, fn(_) { @signals.signal(0L, same=fn(a, b) { a == b }) })
  let words = Array::makei(n, fn(i) { @signals.signal("行\{i}", same=fn(a, b) { a == b }) })
  let off = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let left : Ref[@view.View?] = Ref(None)
  let right : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.row(Is(true)) |> ignore
    left.val = Some(
      root.box(fn(c) {
        c.width(Is(Some(180.0))).offset(By(fn() { off.get() })) |> ignore
        for i in 0..<n {
          c.box(fn(l) { l.words(By(fn() { words[i].get() })).ground(By(fn() { grounds[i].get() })) |> ignore })
          |> ignore
        }
      }),
    )
    right.val = Some(
      root.box(fn(c) {
        c.width(Is(Some(180.0))) |> ignore
        for i in 0..<n {
          c.box(fn(l) { l.words(Is("右\{i}")) |> ignore }) |> ignore
        }
      }),
    )
  })
  { tree, grounds, words, off, left, right }
}

///|
/// Whether any of `ids` is one of the nodes `v` holds or `v` itself.
fn any_of(ids : Array[@view.NodeId], v : @view.View) -> Bool {
  ids.contains(v.id()) || v.kids().iter().any(fn(k) { ids.contains(k.id()) })
}

///|
test "one line's ground changed: that node alone visited and made again, the other column not visited" {
  let c = columns(20)
  c.tree.frame(390.0, 844.0) |> ignore
  let before = c.tree.work()
  c.grounds[3].set(0x112233FFL)
  assert_true(c.tree.frame(390.0, 844.0))
  let after = c.tree.work()
  assert_eq(after.visited - before.visited, 1)
  assert_eq(after.instances - before.instances, 1)
  assert_eq(after.changes - before.changes, 1)
  assert_eq(after.orders - before.orders, 0)
  assert_eq(c.tree.changed(), [c.left.val.unwrap().kids()[3].id()])
}

///|
test "a column drawn off: it alone composed again, its lines and the other column neither visited nor made again" {
  let c = columns(20)
  c.tree.frame(390.0, 844.0) |> ignore
  let before = c.tree.work()
  c.off.set((0.0, 30.0))
  c.tree.frame(390.0, 844.0) |> ignore
  let after = c.tree.work()
  assert_eq(after.visited - before.visited, 1)
  assert_eq(after.instances - before.instances, 0)
  assert_eq(after.composed - before.composed, 1)
  assert_eq(after.computes - before.computes, 0)
  assert_eq(c.tree.composed(), [c.left.val.unwrap().id()])
  // (its lines drawn 30 lower all the same: composed as the scene is gone through)
  let line = c.tree.drawn_of(c.left.val.unwrap().kids()[0].id()).unwrap()
  assert_eq(line.y, 30.0)
}

///|
test "a line's words changed: laid out again, the other column's nodes neither laid out nor visited" {
  let c = columns(20)
  c.tree.frame(390.0, 844.0) |> ignore
  let before = c.tree.work()
  c.words[0].set("第一行变长了很多字所以折成两行")
  c.tree.frame(390.0, 844.0) |> ignore
  let after = c.tree.work()
  assert_eq(after.computes - before.computes, 1)
  // (the root, the column, its 20 lines (those below moved down), the other column looked at where the root placed it
  // again: none of its lines)
  assert_true(after.visited - before.visited <= 23, msg="\{after.visited - before.visited}")
  assert_false(any_of(c.tree.changed(), c.right.val.unwrap()))
  assert_true(c.tree.changed().length() >= 1)
}

///|
test "what a node is made with is its own: an effect made there stopped, its cleanup run once, as the node goes" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let outside = @signals.signal(0)
  let runs = Ref(0)
  let cleanups = Ref(0)
  let sibling_runs = Ref(0)
  let sibling_cleanups = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.box(fn(_) {
      // (a part's own effect, made as it is made: no binding of the view's)
      @signals.effect_cleanup(fn() {
        outside.get() |> ignore
        sibling_runs.val = sibling_runs.val + 1
        fn() { sibling_cleanups.val = sibling_cleanups.val + 1 }
      })
      |> ignore
    })
    |> ignore
    root.show(fn() { on.get() }, fn(_) {
      @signals.effect_cleanup(fn() {
        outside.get() |> ignore
        runs.val = runs.val + 1
        fn() { cleanups.val = cleanups.val + 1 }
      })
      |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  outside.set(1)
  assert_eq((runs.val, cleanups.val), (2, 1))
  on.set(false)
  // (nothing let go as it is set: as the frame takes it)
  assert_eq(cleanups.val, 1)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(cleanups.val, 2)
  outside.set(2)
  // the one gone runs no more; the sibling still does
  assert_eq(runs.val, 2)
  assert_eq(cleanups.val, 2)
  assert_eq(sibling_runs.val, 3)
  assert_true(outside.watched())
  t.dispose()
  assert_eq(sibling_cleanups.val, 3)
  assert_false(outside.watched())
  outside.set(3)
  assert_eq(sibling_runs.val, 3)
}

///|
test "the structure's binding running again leaves what it shows be: its effects not stopped" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let other = @signals.signal(0)
  let outside = @signals.signal(0)
  let runs = Ref(0)
  let t = @view.Tree::new(fn(root) {
    // (the binding reads `other` too: it runs again, still shown)
    root.show(fn() { other.get() |> ignore; on.get() }, fn(_) {
      @signals.effect(fn() {
        outside.get() |> ignore
        runs.val = runs.val + 1
      })
      |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  other.set(1)
  t.frame(390.0, 844.0) |> ignore
  outside.set(1)
  assert_eq(runs.val, 2)
  t.dispose()
}

///|
test "a handle on a row let go, its index made again for another: what it sets, binds, hangs or makes does nothing" {
  let items = @signals.signal([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  let t = list_tree(items, Ref(0))
  t.frame(390.0, 844.0) |> ignore
  let old = t.root().kids()[0].kids()[1]
  items.set([{ key: "a", words: "甲" }])
  t.frame(390.0, 844.0) |> ignore
  items.set([{ key: "a", words: "甲" }, { key: "c", words: "丙" }])
  t.frame(390.0, 844.0) |> ignore
  let fresh = t.root().kids()[0].kids()[1]
  // (the same index, another making)
  assert_eq(fresh.id().at, old.id().at)
  assert_true(fresh.id() != old.id())
  let alive = t.alive()
  let read = @signals.signal("旧", same=fn(a, b) { a == b })
  let pressed = Ref(0)
  old.ground(Is(0xFF0000FFL)).words(By(fn() { read.get() })).on_press(fn() { pressed.val = pressed.val + 1 })
  |> ignore
  let made = old.box(fn(v) { v.words(Is("不该有")) |> ignore })
  t.frame(390.0, 844.0) |> ignore
  assert_false(made.alive())
  assert_eq(t.alive(), alive)
  assert_false(read.watched())
  let d = t.drawn_of(fresh.id()).unwrap()
  assert_eq((d.ground, d.words), (0L, "丙"))
  let (x, y, _, _) = fresh.rect()
  assert_false(t.press(x + 1.0, y + 1.0))
  assert_eq(pressed.val, 0)
  assert_false(old.kids().length() > 0)
}

///|
test "a binding's reads changed many times between frames: nothing worked out as they are set, once as the frame takes it" {
  let p = page()
  p.tree.frame(390.0, 844.0) |> ignore
  let before = p.tree.work()
  for i in 0..<10 {
    p.title.set("第 \{i} 稿")
  }
  // (set, nothing run: no binding, no layout)
  assert_eq(p.tree.work(), before)
  p.tree.frame(390.0, 844.0) |> ignore
  let after = p.tree.work()
  assert_eq(after.bound - before.bound, 1)
  assert_eq(after.computes - before.computes, 1)
  assert_true(p.tree.drawn().iter().any(fn(d) { d.words == "第 9 稿" }))
}

///|
test "a property bound again: the binding before it let go, what it read no longer followed" {
  let a = @signals.signal(1L, same=fn(x, y) { x == y })
  let b = @signals.signal(2L, same=fn(x, y) { x == y })
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(fn(root) {
    node.val = Some(root.box(fn(v) { v.ground(By(fn() { a.get() })) |> ignore }))
  })
  t.frame(390.0, 844.0) |> ignore
  assert_true(a.watched())
  node.val.unwrap().ground(By(fn() { b.get() })) |> ignore
  assert_false(a.watched())
  assert_true(b.watched())
  t.frame(390.0, 844.0) |> ignore
  let before = t.work()
  a.set(5L)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.work().bound - before.bound, 0)
  assert_eq(t.drawn_of(node.val.unwrap().id()).unwrap().ground, 2L)
}

///|
/// A card shown while `on` holds, leaving for 300 as it stops (faded out as it goes), pressed: `pressed`.
fn leaving_tree(on : @signals.Signal[Bool], pressed : Ref[Int], card : Ref[@view.View?]) -> @view.Tree {
  @view.Tree::new(fn(root) {
    root.box(fn(b) { b.height(Is(Some(30.0))).words(Is("上面")) |> ignore }) |> ignore
    root.show(
      fn() { on.get() },
      fn(v) {
        card.val = Some(v)
        v
        .height(Is(Some(40.0)))
        .ground(Is(0x336699FFL))
        .alpha(By(fn() { 1.0 - v.going() }))
        .on_press(fn() { pressed.val = pressed.val + 1 })
        |> ignore
      },
      leave=300.0,
    )
  })
}

///|
test "shown no more: still drawn and faded as it leaves, pressed no more, let go as its leaving ends" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let card : Ref[@view.View?] = Ref(None)
  let t = leaving_tree(on, pressed, card)
  t.frame(390.0, 844.0) |> ignore
  let c = card.val.unwrap()
  let alive = t.alive()
  on.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_true(c.alive())
  assert_true(c.leaving())
  assert_eq(t.wake(), Some(300.0))
  assert_false(t.press(10.0, 40.0))
  assert_eq(pressed.val, 0)
  t.at(150.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.drawn_of(c.id()).unwrap().alpha, 0.5)
  t.at(300.0)
  t.frame(390.0, 844.0) |> ignore
  assert_false(c.alive())
  assert_eq(t.alive(), alive - 1)
  assert_eq(t.wake(), None)
  assert_false(t.drawn().iter().any(fn(d) { d.ground == 0x336699FFL }))
}

///|
test "leaving drawn the same at 60 Hz, at 120 Hz and in one jump to the moment" {
  let at_moment = fn(step : Double) -> Array[String] {
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let t = leaving_tree(on, Ref(0), Ref(None))
    t.frame(390.0, 844.0) |> ignore
    on.set(false)
    t.frame(390.0, 844.0) |> ignore
    let mut now = 0.0
    while now < 200.0 {
      now = if now + step > 200.0 { 200.0 } else { now + step }
      t.at(now)
      t.frame(390.0, 844.0) |> ignore
    }
    let out = shown(t.drawn())
    t.dispose()
    out
  }
  let jump = at_moment(200.0)
  assert_eq(at_moment(1000.0 / 60.0), jump)
  assert_eq(at_moment(1000.0 / 120.0), jump)
}

///|
test "a row gone from the list leaves where it was, the rows after it kept below it till it has left" {
  let items = @signals.signal([
    { key: "a", words: "甲" },
    { key: "b", words: "乙" },
    { key: "c", words: "丙" },
  ])
  let t = @view.Tree::new(fn(root) {
    root.each(
      fn() { items.get() },
      fn(it) { it.key },
      fn(row, item) { row.height(Is(Some(20.0))).words(By(fn() { item.get().words })) |> ignore },
      leave=200.0,
    )
  })
  t.frame(390.0, 844.0) |> ignore
  items.set([{ key: "a", words: "甲" }, { key: "c", words: "丙" }])
  t.frame(390.0, 844.0) |> ignore
  let words = fn() { t.drawn().filter(fn(d) { d.words != "" }).map(fn(d) { (d.words, d.y) }) }
  assert_eq(words(), [("甲", 0.0), ("乙", 20.0), ("丙", 40.0)])
  t.at(200.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(words(), [("甲", 0.0), ("丙", 20.0)])
}
