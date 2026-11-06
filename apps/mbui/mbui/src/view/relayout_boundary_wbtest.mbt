// A change under a box whose size is its own alone lays out that box alone (retained.md rule 3: layout goes up to the
// first box that does not read what it holds), not the column holding it nor the window: the same work with 30 rows
// beside it and with 3000 (rule 14).

///|
/// A column of `rows` rows each 40 high, each holding words; the words of one changed: the sizes the layout worked out
/// or found kept (@flex's counters), the nodes laid out again (Work's laid), and the places laid out from (Work's relayouts), for that change; and
/// where the row's words and the next row stand after it.
fn boundary_cost(rows : Int) -> (Int, Int, Int, (Double, Double)) raise {
  let said = @signals.signal("一", same=fn(a, b) { a == b })
  let words : Ref[View?] = Ref(None)
  let next : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.box(fn(col) {
        for i in 0..<rows {
          let row = col.box(fn(r) {
            r.box(fn(w) {
              if i == 1 {
                words.val = Some(w)
                w.words(By(fn() { said.get() })) |> ignore
              } else {
                w.words(Is("行")) |> ignore
              }
            })
            |> ignore
          })
          row.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore
          if i == 2 {
            next.val = Some(row)
          }
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  t.frame(390.0, 844.0) |> ignore
  let sized0 = @flex.counters[0] + @flex.counters[1]
  let w0 = t.work()
  said.set("一二三四五六七八九十")
  t.frame(390.0, 844.0) |> ignore
  let w1 = t.work()
  let sized = @flex.counters[0] + @flex.counters[1] - sized0
  let drawn = t.drawn_of(words.val.unwrap().id()).unwrap()
  let below = t.drawn_of(next.val.unwrap().id()).unwrap()
  assert_true(drawn.w > 40.0, msg="the words laid out anew: \{drawn.w}")
  (sized, w1.laid - w0.laid, w1.relayouts - w0.relayouts, (below.y, drawn.y))
}

///|
test "relayout boundary: words changed in a row of a size its own are laid out in it alone, 30 rows or 3000" {
  let short = boundary_cost(30)
  let long = boundary_cost(3000)
  assert_eq(long, short)
  // (the row holding the words, laid out from there alone (its size its own: asked the same), nothing that holds it)
  assert_true(short.1 <= 2, msg="laid out again: \{short.1}")
  assert_eq(short.2, 1)
  assert_eq(short.3, (80.0, 40.0))
}

///|
test "relayout boundary: a box sized by what it holds is no boundary; its holder laid out again, the rows under it moved" {
  let tall = @signals.signal(20.0, same=fn(a, b) { a == b })
  let next : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.box(fn(r) { r.box(fn(w) { w.height(By(fn() { Some(tall.get()) })) |> ignore }) |> ignore }) |> ignore
        next.val = Some(col.box(fn(r) { r.height(Is(Some(40.0))) |> ignore }))
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.drawn_of(next.val.unwrap().id()).map(fn(d) { d.y }), Some(20.0))
  tall.set(50.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.drawn_of(next.val.unwrap().id()).map(fn(d) { d.y }), Some(50.0))
}

///|
/// A chat's page: a window-high column of a bar, a list (as tall as the room left: grown into it, never taller) that
/// makes and lays out only the rows in sight from its foot up (a layout of its own: Layout::child, as a lazy list), of
/// `rows` rows, and a composer; the last row made taller. What was laid out again for it (Work's laid, relayouts,
/// @flex's sizes) and whether the page, the window or the bar was.
fn page_cost(rows : Int) -> (Int, Int, Int, Bool) raise {
  let tall = @signals.signal(40.0, same=fn(a, b) { a == b })
  let page : Ref[View?] = Ref(None)
  let bar : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      page.val = Some(
        root.box(fn(p) {
          p.grow(Is(1.0)) |> ignore
          bar.val = Some(p.box(fn(b) { b.height(Is(Some(50.0))) |> ignore }))
          p.box(fn(v) {
            v.grow(Is(1.0)).min_height(Is(Some(0.0))).basis(Is(Some(0.0))) |> ignore
            v.layout_box(Is(rows), fn(l, n) {
              let mut y = l.height
              let mut k = n - 1
              while k >= 0 && y > 0.0 {
                let last = k == n - 1
                let row = l.child("\{k}", fn(r) {
                  if last {
                    r.height(By(fn() { Some(tall.get()) })) |> ignore
                  } else {
                    r.height(Is(Some(40.0))) |> ignore
                  }
                })
                let size = l.measure(row, l.width)
                y = y - size.1
                l.place(row, 0.0, y)
                k = k - 1
              }
            })
            |> ignore
          })
          |> ignore
          p.box(fn(c) { c.height(Is(Some(60.0))) |> ignore }) |> ignore
        }),
      )
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0, now=0.0) |> ignore
  t.frame(390.0, 844.0, now=10.0) |> ignore
  let g = @flex.computes() + 1
  let sized0 = @flex.counters[0] + @flex.counters[1]
  let w0 = t.work()
  tall.set(80.0)
  t.frame(390.0, 844.0, now=20.0) |> ignore
  let w1 = t.work()
  let sized = @flex.counters[0] + @flex.counters[1] - sized0
  let above = t.nodes[0].flex.laid_out_at() >= g ||
    t.nodes[page.val.unwrap().at].flex.laid_out_at() >= g ||
    t.nodes[bar.val.unwrap().at].flex.laid_out_at() >= g
  (sized, w1.laid - w0.laid, w1.relayouts - w0.relayouts, above)
}

///|
test "relayout boundary: a row of a chat's list made taller lays out the list, not the page, the bar or the window, 30 rows or 3000" {
  let short = page_cost(30)
  let long = page_cost(3000)
  assert_false(short.3, msg="laid out past the list: \{short}")
  assert_eq(long, short)
}

///|
test "relayout boundary: laid out again as it was given, the same size, but what its holder measured of it answered otherwise: its holder laid out again" {
  // (a column 100 high, two that grow from what they hold: the first's content 10 high, the second's 20; the room left
  // shared out from their bases, so the first's base read by the column decides where the second is)
  let inner = @signals.signal(10.0, same=fn(a, b) { a == b })
  let first : Ref[View?] = Ref(None)
  let second : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.height(Is(Some(100.0))) |> ignore
        first.val = Some(
          col.box(fn(b) {
            b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            b.box(fn(c) { c.height(By(fn() { Some(inner.get()) })) |> ignore }) |> ignore
          }),
        )
        second.val = Some(
          col.box(fn(b) {
            b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            b.box(fn(c) { c.height(Is(Some(20.0))) |> ignore }) |> ignore
          }),
        )
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let h = fn(v : Ref[View?]) { t.nodes[v.val.unwrap().at].flex.height }
  assert_eq((h(first), h(second)), (45.0, 55.0))
  inner.set(30.0)
  t.frame(390.0, 844.0) |> ignore
  // (laid out alone as the column gave it, 45 high, it is as big as it was; its base, which the column read, is not)
  assert_eq((h(first), h(second)), (55.0, 45.0))
}
