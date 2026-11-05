// A source whose indexed keys stay constant under a page arriving at either end. Count the keys the list asks for,
// including those it uses to retain and place rows, instead of counting only the views made.

///|
priv struct IndexedCase {
  tree : @view.Tree
  first : Ref[Int]
  count : Ref[Int]
  revision : @signals.Signal[Int]
  reads : Ref[Int]
  checks : Ref[Int]
  gone : Array[(Int, Int)]
  lost : Ref[Bool]
  live : Map[Int, @view.View]
  put : @signals.Signal[(Int, Double)?]
}

///|
fn indexed_case(n : Int) -> IndexedCase {
  let first = Ref(0)
  let count = Ref(n)
  let revision = @signals.signal(0)
  let reads = Ref(0)
  let checks = Ref(0)
  let gone : Array[(Int, Int)] = []
  let lost = Ref(false)
  let live : Map[Int, @view.View] = {}
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(None)
  let contains = fn(k : Int) {
    checks.val += 1
    k >= first.val && k < first.val + count.val
  }
  let source : @view.AnchoredSource[Int] = {
    snapshot: fn() { (revision.get(), count.val) },
    key: fn(i) { reads.val += 1; first.val + i },
    find: fn(k, _) { if contains(k) { Some(k - first.val) } else { None } },
    removed_since: fn(v) {
      if lost.val { None } else { Some(gone.filter(fn(g) { g.0 > v }).map(fn(g) { g.1 })) }
    },
    contains,
  }
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      v.scrolls_anchored(scroll, fn() { [] }, indexed=source, ahead=0.0, put~, fn(row, k) {
        live[k] = row
        row.owns(fn() { live.remove(k) }) |> ignore
        row.height(Is(Some(40.0))) |> ignore
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  { tree, first, count, revision, reads, checks, gone, lost, live, put }
}

///|
test "an indexed anchored list reads only its window on arrival and prepend" {
  let work = fn(n : Int) -> (Int, Int) raise {
    let c = indexed_case(n)
    assert_true(c.live.contains(n - 1))
    let before = c.reads.val
    let checks = c.checks.val
    c.count.val += 1
    c.revision.set(1)
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    assert_true(c.live.contains(n))
    let newest = c.live[n].rect().1
    c.first.val -= 10
    c.count.val += 10
    c.revision.set(2)
    c.tree.frame(390.0, 844.0, now=20.0) |> ignore
    assert_eq(c.live[n].rect().1, newest, msg="history above does not move what is shown")
    let result = (c.reads.val - before, c.checks.val - checks)
    c.tree.dispose()
    result
  }
  assert_eq(work(30), work(3000))
}

///|
test "an indexed anchored list forgets a removed row's identity and can place it again when reinserted" {
  let c = indexed_case(100)
  let id = c.live[99].row_place().0
  c.count.val -= 1
  c.gone.push((1, 99))
  c.revision.set(1)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_false(c.live.contains(99))
  // The reinserted row has another row below it, so the requested top does not leave empty space at the end.
  c.count.val += 2
  c.revision.set(2)
  c.put.set(Some((99, 20.0)))
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_true(c.live[99].row_place().0 != id)
  assert_eq(c.live[99].rect().1, 20.0)
  c.tree.dispose()
}

///|
test "an indexed list keeps a key removed and restored within one change" {
  let c = indexed_case(100)
  let id = c.live[99].row_place().0
  c.gone.push((1, 99))
  c.revision.set(2)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq(c.live[99].row_place().0, id)
  c.tree.dispose()
}

///|
test "an indexed list forgets removed keys even when its change history was lost" {
  let c = indexed_case(100)
  let id = c.live[99].row_place().0
  c.count.val -= 1
  c.lost.val = true
  c.revision.set(1)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  c.count.val += 1
  c.lost.val = false
  c.revision.set(2)
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_true(c.live[99].row_place().0 != id)
  c.tree.dispose()
}

///|
test "an indexed list whose change history was lost checks the rows it knows, as few for 3000 rows as for 30" {
  let checks = fn(n : Int) {
    let c = indexed_case(n)
    c.count.val -= 1
    c.lost.val = true
    c.checks.val = 0
    c.revision.set(1)
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    let k = c.checks.val
    c.tree.dispose()
    k
  }
  assert_eq(checks(3000), checks(30))
}
