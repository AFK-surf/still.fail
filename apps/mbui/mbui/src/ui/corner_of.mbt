// Corners linked (mbui/paint's corner.mbt): what a corner is worked out from where the old views ask it.

///|
/// What linked corners are worked out from as the old views ask them: the window's corner as the system draws it now,
/// the ranges of the theme being built under (Theme::corner_fit; the window's theme between builds).
pub fn corner_roots() -> CornerRoots {
  { window: window_corner(), fit: g().corner_fit }
}

///|
/// The window's corner as the system draws it, for the window's tree's nodes: as the frame began (view_frame), told as
/// it changes (the window maximized, another system's corner), what read it worked out again.
// kept across runs: set as each frame begins
let tree_window_corner : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })

///|
/// A node of the window's tree's corner linked so (View::radius): worked out from the window's roots as they are now
/// (tree_corner_roots_now), again as they change (the window maximized, another system's corner, another theme's
/// ranges).
pub fn corner_of(k : CornerOf) -> @view.Live[Double] {
  By(fn() { k.radius(tree_corner_roots_now()) })
}

///|
/// What linked corners of the window's tree's nodes are worked out from now, followed: the window's corner as the frame
/// began (tree_window_corner), the ranges of the theme its nodes are drawn in (tree_theme: the one the app tells it, as
/// it changes, at once; else the window's): what reads it worked out again as either changes.
pub fn tree_corner_roots_now() -> CornerRoots {
  { window: tree_window_corner.get(), fit: tree_theme().corner_fit }
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
/// The theme a node of the window's tree is drawn in now: the app's, as it tells it (set_tree_theme: what its old
/// views are built in, read as it changes); an app that tells none, the window's as each frame begins (tree_theme_said;
/// before the first frame, the window's).
pub fn tree_theme() -> Theme {
  match tree_theme_of.get() {
    Some(f) => return f()
    None => ()
  }
  match tree_theme_said.get() {
    Some(t) => t
    None => g().theme
  }
}

///|
/// The app's theme for its window's tree (set_tree_theme), none told: told to what read the theme by it (another way
/// to it, what it reads followed from then).
// kept across runs: told by the app as its tree is made; let go as a tree is (view_forget)
let tree_theme_of : @signals.Signal[(() -> Theme)?] = @signals.signal(None, same=fn(a, b) {
  match (a, b) {
    (Some(x), Some(y)) => physical_equal(x, y)
    (None, None) => true
    _ => false
  }
})

///|
/// The theme the window's tree is drawn in, as the app has it (what its old views are built in: Ctx::with_theme's),
/// read where it is drawn so it follows as it changes (a signal read in `f`): told as the tree is made.
pub fn set_tree_theme(f : () -> Theme) -> Unit {
  tree_theme_of.set(Some(f))
}

///|
/// Whether the window has none of the system's title bar (window_inset: its buttons in the app's top row; not full
/// screen nor going there), as the frame began (view_frame); told as it changes, what read it worked out again.
// kept across runs: set as each frame begins
let tree_inset_said : @signals.Signal[Bool?] = @signals.signal(None, same=fn(a, b) { a == b })

///|
/// window_inset for a node of the window's tree: as the frame began, followed (tree_inset_said); before the first
/// frame, the window's.
pub fn window_inset_now() -> Bool {
  match tree_inset_said.get() {
    Some(on) => on
    None => window_inset()
  }
}

///|
/// window_keys_left for a node of the window's tree (window_inset_now), followed.
pub fn window_keys_left_now() -> Bool {
  window_inset_now() && platform() != 3 && platform() != 5
}

///|
/// window_keys_own for a node of the window's tree (window_inset_now), followed.
pub fn window_keys_own_now() -> Bool {
  window_inset_now() && (platform() == 3 || platform() == 5)
}
