// What a column holding its blocks only while they show (View::scrolls_window) makes, whatever the blocks: those that
// show, where they are and pressed there, however many blocks lie before them (hundreds as tall as nothing at its top,
// in one layout: none laid out again for what one measured), counted far from how tall they come to, and back at its
// end from far up.

///|
/// A column 300 by 100 holding blocks `0..<n` while they show, block `k` `tall(k)` high, counted `est` till laid out;
/// from its end where `from_end` says. The tree and the blocks made now, by key.
fn fill_case(
  n : Int,
  tall : (Int) -> Double,
  est : Double,
  from_end? : Bool = false,
) -> (@view.Tree, Map[Int, @view.View]) {
  let scroll = @view.Scroll::list()
  let made : Map[Int, @view.View] = {}
  let pressed = fill_pressed
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { Array::makei(n, fn(i) { i }) }, est~, from_end~, fn(b, k) {
        made[k] = b
        b.owns(fn() { made.remove(k) }) |> ignore
        b.height(Is(Some(tall(k)))).on_press(fn() { pressed.val = Some(k) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // (its first frame: laid out once, what shows made, measured and placed in that one layout)
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  (tree, made)
}

///|
fn fill_shown(made : Map[Int, @view.View]) -> Array[Int] {
  let all = made.keys().collect()
  all.sort()
  all
}

///|
// kept across runs: what a press last hit among a fill_case's blocks, put back by each test that reads it
let fill_pressed : Ref[Int?] = Ref(None)

///|
/// What a press at (150, `y`) in the column hits among its blocks.
fn fill_hit(tree : @view.Tree, y : Double) -> Int? {
  fill_pressed.val = None
  tree.press(150.0, y) |> ignore
  fill_pressed.val
}

///|
test "scrolls_window: six hundred blocks as tall as nothing at its top, then blocks 40 high: those that show made where they are, pressed there" {
  // (more than its layouts in one frame were let be, each laid out again for what one measured: 64, 2026-11-06)
  let (tree, made) = fill_case(700, fn(k) { if k < 600 { 0.0 } else { 40.0 } }, 80.0)
  // (the six hundred at 0, then 600 from 0, 601 from 40, 602 from 80 to 120)
  let showing = fill_shown(made).filter(fn(k) { made[k].rect().3 > 0.0 }).map(fn(k) { (k, made[k].rect().1) })
  assert_eq(showing, [(600, 0.0), (601, 40.0), (602, 80.0)])
  assert_eq([20.0, 60.0, 90.0].map(fn(y) { fill_hit(tree, y) }), [Some(600), Some(601), Some(602)])
}

///|
test "scrolls_window: blocks counted twenty times as tall as they come to: what shows filled once they are laid out" {
  // (counted 200 each: the first alone in sight before it is laid out; 10 each as laid out: ten fill the 100)
  let (_, made) = fill_case(50, fn(_) { 10.0 }, 200.0)
  assert_eq(fill_shown(made), Array::makei(10, fn(i) { i }))
}

///|
test "scrolls_window from its end: scrolled far up and back down past its end, at its end with what shows there made" {
  let (tree, made) = fill_case(50, fn(_) { 40.0 }, 80.0, from_end=true)
  // (at its end: the last block's foot at the column's, 100; the three over it showing)
  let foot = fn() {
    match made.get(49) {
      Some(b) => {
        let (_, y, _, h) = b.rect()
        y + h
      }
      None => -1.0
    }
  }
  let first = (foot(), fill_shown(made))
  tree.wheel_at(150.0, 50.0, 0.0, -1500.0, 0, 20.0) |> ignore
  tree.frame(390.0, 844.0, now=32.0) |> ignore
  let up = made.contains(49)
  tree.wheel_at(150.0, 50.0, 0.0, 3000.0, 0, 40.0) |> ignore
  tree.frame(390.0, 844.0, now=48.0) |> ignore
  assert_eq((first, up, foot(), fill_shown(made)), ((100.0, [47, 48, 49]), false, 100.0, [47, 48, 49]))
}
