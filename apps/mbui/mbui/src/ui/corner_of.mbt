// Corners linked (mbui/paint's corner.mbt): what a corner is worked out from where the old views ask it.

///|
/// What linked corners are worked out from as the old views ask them: the window's corner as the system draws it now,
/// the ranges of the theme being built under (Theme::corner_fit; the window's theme between builds).
pub fn corner_roots() -> CornerRoots {
  { window: window_corner(), fit: g().corner_fit }
}

///|
/// What linked corners of the window's tree's nodes are worked out from: the window's corner as the system draws it and
/// the window's theme's ranges, as the frame began (view_frame); told as either changes, what read it worked out again.
// kept across runs: set as each frame begins
let tree_corner_roots : @signals.Signal[CornerRoots] = @signals.signal(
  { window: 0.0, fit: None },
  same=fn(a, b) { a == b },
)

///|
/// A node of the window's tree's corner linked so (View::radius): worked out from the window's roots as they are now,
/// again as they change (the window maximized, another system's corner, another theme's ranges).
pub fn corner_of(k : CornerOf) -> @view.Live[Double] {
  By(fn() { k.radius(tree_corner_roots.get()) })
}

///|
/// The theme the window's tree's nodes are drawn in (what the old views are built in for the window's width), as the
/// frame began (view_frame); told as it changes (another width's, the system's dark coming), what read it worked out
/// again.
// kept across runs: set as each frame begins
let tree_theme_said : @signals.Signal[Theme?] = @signals.signal(None, same=fn(a, b) {
  match (a, b) {
    (Some(x), Some(y)) => physical_equal(x, y)
    (None, None) => true
    _ => false
  }
})

///|
/// The theme a node of the window's tree is drawn in now (tree_theme_said; before the first frame, the window's).
pub fn tree_theme() -> Theme {
  match tree_theme_said.get() {
    Some(t) => t
    None => g().theme
  }
}
