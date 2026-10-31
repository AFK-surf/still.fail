// The splash, starting or failed, is the window's tree's nodes (app_tree's splash_tree), drawn as the app's old view
// alone draws it (splash): the same glyphs, of the same colour, where they are; the same mark; the ground alone till
// the splash's second where there is nothing to say at once.

///|
/// A failure said in two lines, the second long enough to wrap in a phone's window.
let failed_words : String = "still.fail's core stopped\nIt could not open the place it keeps its accounts in, so nothing of them was read"

///|
/// The home fixture, failed as `fatal` says (None: not failed), its accounts never read.
fn splash_case(fatal : String?) -> Source {
  let base = fixture("home")
  {
    ..base,
    fatal: fn() { fatal },
    topic: fn(name, params) {
      if name == "accounts" {
        { value: None, error: None, version: 0 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
}

///|
/// What is drawn at `at` after the start, the window's tree's (`tree`) or the old view's alone: the glyphs (their
/// places and colours) and the shapes.
fn splash_drawn(fatal : String?, tree : Bool, at : Double) -> (Array[(Double, Double, Int64)], Array[(Double, Double, Double, Double, Double, Int64)]) {
  new_run()
  let src = splash_case(fatal)
  let t = if tree {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=800.0, platform=2)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=800.0, platform=2)
  }
  t.run_for(at)
  (t.drawn_glyphs(), t.drawn_shapes())
}

///|
/// Whether the window's tree holds words of the splash's size (the theme's meta) as a node's own.
fn tree_says_meta() -> Bool {
  match @ui.view_tree() {
    Some(tree) => tree.styled().iter().any(fn(s) { s.words && s.size == @sf.theme().t.meta })
    None => false
  }
}

///|
test "failed: the splash's words the window's tree's own, every glyph and the mark drawn as the old view alone draws them, from the first frame" {
  let (old_glyphs, old_shapes) = splash_drawn(Some(failed_words), false, 0.0)
  let (glyphs, shapes) = splash_drawn(Some(failed_words), true, 0.0)
  let own = tree_says_meta()
  let lines = glyphs.map(fn(g) { g.1 }).fold(init=[], fn(ys : Array[Double], y) { if ys.contains(y) { ys } else { ys + [y] } })
  assert_eq(
    (own, glyphs == old_glyphs, shapes == old_shapes, old_shapes.length() > 0, lines.length() > 2),
    (true, true, true, true, true),
    msg="old \{old_glyphs.length()} glyphs, \{old_shapes.length()} shapes; the tree's \{glyphs.length()}, \{shapes.length()}; first old \{old_glyphs[:3]}, tree \{glyphs[:3]}; lines \{lines}",
  )
}

///|
test "starting: the ground alone just before the splash's second, the mark drawn as the old view alone draws it just after" {
  let before = splash_drawn(None, true, splash_label_ms - 50.0)
  let (_, old_shapes) = splash_drawn(None, false, splash_label_ms + 50.0)
  let (glyphs, shapes) = splash_drawn(None, true, splash_label_ms + 50.0)
  assert_eq(
    (before.0.length(), before.1.length(), glyphs.length(), shapes == old_shapes, old_shapes.length() > 0),
    (0, 0, 0, true, true),
    msg="the tree's \{shapes.length()} shapes, the old view's \{old_shapes.length()}",
  )
}

///|
test "failed, the window's buttons come into the app's top row and go again: from the first frame after each, a press on its top drags the window as they are there, and not once they are gone" {
  new_run()
  let src = splash_case(Some(failed_words))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0, window_inset=false)
  t.frame()
  // (pressed on the top's middle, nothing of the splash there: whether it would drag, and how many drags it made)
  let pressed = fn() {
    let before = t.window_drags()
    let would = t.drags_window_at(640.0, 12.0)
    t.tap(640.0, 12.0)
    (would, t.window_drags() - before)
  }
  let none = pressed()
  t.set_window_inset(true)
  t.frame()
  let there = pressed()
  t.set_window_inset(false)
  t.frame()
  let gone = pressed()
  assert_eq((none, there, gone), ((false, 0), (true, 1), (false, 0)))
}

///|
test "failed, the window drawn at half its points (its content zoomed out), then as it was: the top row that drags it as tall as the window's buttons' band at each, from the first frame after" {
  new_run()
  let src = splash_case(Some(failed_words))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0, window_inset=true)
  t.frame()
  // (a press 40 down: in the band of 56 the window's 28 points take drawn at half, past the band of 28 as it was)
  let pressed = fn() {
    let before = t.window_drags()
    let would = t.drags_window_at(640.0, 40.0)
    t.tap(640.0, 40.0)
    (would, t.window_drags() - before)
  }
  let whole = pressed()
  @ui.set_window_zoom(0.5)
  t.frame()
  let half = pressed()
  @ui.set_window_zoom(1.0)
  t.frame()
  let again = pressed()
  assert_eq((whole, half, again), ((false, 0), (true, 1), (false, 0)))
}

///|
test "failed and starting past the second: nothing of the splash an old view hosted in the window's tree, the mark its own node's picture" {
  let hosts = fn() {
    match @ui.view_tree() {
      Some(tree) => tree.said_order().filter(fn(n) { n.hosted }).length()
      None => -1
    }
  }
  let _ = splash_drawn(Some(failed_words), true, 0.0)
  let failed = hosts()
  let _ = splash_drawn(None, true, splash_label_ms + 50.0)
  assert_eq((failed, hosts()), (0, 0))
}
