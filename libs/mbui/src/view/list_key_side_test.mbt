// A key of a page's list coming at its foot, drawn as big as its block shows (View::scrolls_window), grows from the
// side what it draws is laid from (Pivot's DrawnSide): a line laid from an edge belongs to that edge, so it never
// moves sideways to its place (the coordinator of the migration, 2026-11-14: the reply's left edge went 155 → 90 on
// 大屏 as it grew about its middle). Words at the left of a node as wide as the list keep their left edge where it rests;
// a bubble as wide as its words at the list's right keeps its right edge; a bubble in the middle keeps its middle. At
// every look 10 ms apart, in one jump and at 60, 120, 24 and 7 a second, on no grid and on 3 pixels a point, within half
// a point.

///|
/// The words the key's block holds.
let ks_side_words : String = "短短的话"

///|
/// How key 72's block is laid out: its words at the left of a node as wide as the list, or in a bubble at its right, or
/// in a bubble in its middle.
priv enum SideCase {
  WordsLeft
  BubbleRight
  BubbleMiddle
}

///|
/// A page's list 300 by 400 on grid `g`, rows 0 to 9 (40 each), following its foot; key 72 laid out as `how` says.
/// Drawn once, at 0.
fn ks_side_case(g : Double, how : SideCase) -> (@view.Tree, @signals.Signal[Array[Int]]) {
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, follows=fn() { true }, fn(b, k) {
        if k == 72 {
          let bubble = fn(b : @view.View) {
            b.box(fn(w) {
              w.ground(Is(0xDDDDDDFFL)).padding(Is((8.0, 8.0, 8.0, 8.0))).words(Is(ks_side_words)) |> ignore
            })
            |> ignore
          }
          match how {
            WordsLeft =>
              b.box(fn(w) { w.height(Is(Some(48.0))).shrink(Is(0.0)).words(Is(ks_side_words)) |> ignore }) |> ignore
            BubbleRight => {
              b.lines_up(Is(Some(End))) |> ignore
              bubble(b)
            }
            BubbleMiddle => {
              b.lines_up(Is(Some(Middle))) |> ignore
              bubble(b)
            }
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
/// Where key 72's side is drawn now, as `how` reads it: its words' left edge (they are laid from the node's start), its
/// bubble's right edge, its bubble's middle; rc_none where it draws nothing seen.
fn ks_side_at(tree : @view.Tree, how : SideCase) -> Double {
  let held = tree.drawn_held()
  for e in held {
    let (d, _, _) = e
    guard d.words == ks_side_words && d.alpha > 0.0 else { continue }
    // (a bubble: the words' own node, its ground with them)
    return match how {
      WordsLeft => d.x
      BubbleRight => d.x + d.w
      BubbleMiddle => d.x + d.w / 2.0
    }
  }
  rc_none
}

///|
test "a key coming at a page's list's foot grows from the side what it draws is laid from: words at the left their left edge, a bubble at the right its right edge, one in the middle its middle, where each rests at every look" {
  for g in [0.0, 3.0] {
    for how in [WordsLeft, BubbleRight, BubbleMiddle] {
      for rate in rc_rates {
        let (tree, keys) = ks_side_case(g, how)
        let more = Array::makei(10, fn(i) { i })
        more.push(72)
        let looks = []
        let mut at = rc_at - rc_look_ms
        while at <= rc_at + @flex.move_most_ms + 100.0 {
          looks.push(at)
          at = at + rc_look_ms
        }
        let seen = rc_walk(tree, [(rc_at, fn() { keys.set(more) })], looks, rate, fn() { ks_side_at(tree, how) })
        let rest = seen[seen.length() - 1]
        let what = "\{ks_side_name(how)}, grid \{g}, at \{rate} a second"
        assert_true(rest != rc_none, msg="\{what}: not drawn at rest")
        for i, m in seen {
          guard m != rc_none else { continue }
          assert_true((m - rest).abs() <= 0.5, msg="\{what}, look \{i}: its side at \{m}, \{rest} at rest")
        }
      }
    }
  }
}

///|
/// What `how` lays out, for a fault's words.
fn ks_side_name(how : SideCase) -> String {
  match how {
    WordsLeft => "words at the left"
    BubbleRight => "a bubble at the right"
    BubbleMiddle => "a bubble in the middle"
  }
}
