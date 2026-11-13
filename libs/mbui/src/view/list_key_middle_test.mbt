// What comes by its size grows about the middle of what it draws (the owner, 2026-10-31: 「有些东西就应该偏心缩放」): a
// key of a page's list coming at its foot, drawn as big as its block shows (View::scrolls_window, Pivot's
// DrawnAcross), keeps the middle across of what it draws where it is at rest all its way, whatever box its words are
// laid in: words in a node as wide as the list draw their lines, not that box (a reply's words at its left, the films of
// #6026: they slid from x 245 to 98 as they grew). A bubble as wide as its words, at the list's right, the same. At
// every look 10 ms apart, in one jump and at 60, 120, 24 and 7 a second, on no grid and on 3 pixels a point.

///|
/// The words the key's block holds.
let km_words : String = "短短的话"

///|
/// How wide `km_words` are drawn, laid out as wide as they are (a box lined up at the start of its column).
fn km_words_w() -> Double {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).lines_up(Is(Some(Start))) |> ignore
      o.box(fn(w) { w.words(Is(km_words)) |> ignore }) |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  match tree.drawn().filter(fn(d) { d.words == km_words }) {
    [d, ..] => d.w
    _ => 0.0
  }
}

///|
/// A page's list 300 by 400 on grid `g`, rows 0 to 9 (40 each), following its foot; key 72 holds `km_words`: `bubble`
/// false, in a node as wide as the list (its words at its left); true, in a bubble with a ground as wide as its words,
/// at the list's right. Drawn once, at 0.
fn km_case(g : Double, bubble : Bool) -> (@view.Tree, @signals.Signal[Array[Int]]) {
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, follows=fn() { true }, fn(b, k) {
        if k == 72 {
          if bubble {
            b.lines_up(Is(Some(End))) |> ignore
            b.box(fn(w) {
              w.ground(Is(0xDDDDDDFFL)).padding(Is((8.0, 8.0, 8.0, 8.0))).words(Is(km_words)) |> ignore
            })
            |> ignore
          } else {
            b.box(fn(w) { w.height(Is(Some(48.0))).shrink(Is(0.0)).words(Is(km_words)) |> ignore }) |> ignore
          }
        } else {
          b.height(Is(Some(40.0))).words(Is("行\{k}")) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  if g > 0.0 {
    tree.set_rows_grid(g)
  }
  tree.frame(390.0, 844.0) |> ignore
  (tree, keys)
}

///|
/// The middle across of what key 72 draws now (its words' lines, `ww` wide at their size, at the start of their box;
/// the grounds holding them), as drawn, its scale with it; rc_none where it draws nothing seen.
fn km_middle(tree : @view.Tree, ww : Double) -> Double {
  let held = tree.drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard d.words == km_words && d.alpha > 0.0 else { continue }
    let s = tree.drawn_scale(d.id)
    let mut x0 = d.x
    let mut x1 = d.x + ww * s
    let mut k = i
    while k >= 0 {
      let (c, up, _) = held[k]
      if c.clips {
        break
      }
      if (c.ground & 0xFFL) != 0L {
        x0 = if c.x < x0 { c.x } else { x0 }
        x1 = if c.x + c.w > x1 { c.x + c.w } else { x1 }
      }
      k = up
    }
    return (x0 + x1) / 2.0
  }
  rc_none
}

///|
test "a key coming at a page's list's foot holding words in a node as wide as the list, or a bubble as wide as its words at its right: the middle across of what it draws where it is at rest at every look of its way" {
  let ww = km_words_w()
  assert_true(ww > 10.0 && ww < 200.0, msg="the words \{ww} wide")
  for g in [0.0, 3.0] {
    for bubble in [false, true] {
      for rate in rc_rates {
        let (tree, keys) = km_case(g, bubble)
        let more = Array::makei(10, fn(i) { i })
        more.push(72)
        let looks = []
        let mut at = rc_at - rc_look_ms
        while at <= rc_at + @flex.move_most_ms + 100.0 {
          looks.push(at)
          at = at + rc_look_ms
        }
        let seen = rc_walk(tree, [(rc_at, fn() { keys.set(more) })], looks, rate, fn() { km_middle(tree, ww) })
        let rest = seen[seen.length() - 1]
        let what = "\{if bubble { "a bubble at its right" } else { "words as wide as the list" }}, grid \{g}, at \{rate} a second"
        assert_true(rest != rc_none, msg="\{what}: not drawn at rest")
        for i, m in seen {
          guard m != rc_none else { continue }
          assert_true((m - rest).abs() <= 1.0, msg="\{what}, look \{i}: its middle at \{m}, \{rest} at rest")
        }
      }
    }
  }
}
