// What a tree's nodes are told of where they are drawn, each value by itself (the system's size of words, how many
// pixels a point is, glass drawn solid or not, the soft keyboard over the window's foot, a picture decoded or not) and
// the window's focus let go of: asked of the View a node holds, as what hosts the tree says it (Tree::drawn_by), never a
// context of the host's handed out whole.

///|
/// What hosts a tree says of where its nodes are drawn, each as it is now (Tree::drawn_by); none said: a window at 1,
/// its words as said, its glass glass, no keyboard, no picture decoded, the focus the tree's own.
struct Env {
  mut words_scale : () -> Double
  mut pixel_scale : () -> Double
  mut glass_solid : () -> Bool
  mut keyboard_inset : () -> Double
  mut image_ready : (String, Double) -> Bool
  mut focus_let_go : (() -> Unit)?
}

///|
fn Env::new() -> Env {
  {
    words_scale: fn() { 1.0 },
    pixel_scale: fn() { 1.0 },
    glass_solid: fn() { false },
    keyboard_inset: fn() { 0.0 },
    image_ready: fn(_, _) { false },
    focus_let_go: None,
  }
}

///|
/// What hosts the tree says of where its nodes are drawn, each read as a node asks it (what is not said, as it was):
/// `words_scale` the system's size of words its words are drawn at (as they are measured: ui's Ctx::sp); `pixel_scale`
/// how many pixels a point is; `glass_solid` whether glass is drawn solid; `keyboard_inset` how far the soft keyboard
/// reaches over the window's foot, in points; `image_ready` whether a picture is decoded ready to show so many pixels on
/// its long side (its decode asked for where it is not); `focus_let_go` the window's focus let go of, on either side.
pub fn Tree::drawn_by(
  self : Tree,
  words_scale? : () -> Double,
  pixel_scale? : () -> Double,
  glass_solid? : () -> Bool,
  keyboard_inset? : () -> Double,
  image_ready? : (String, Double) -> Bool,
  focus_let_go? : () -> Unit,
) -> Unit {
  let e = self.env
  if words_scale is Some(f) {
    e.words_scale = f
  }
  if pixel_scale is Some(f) {
    e.pixel_scale = f
  }
  if glass_solid is Some(f) {
    e.glass_solid = f
  }
  if keyboard_inset is Some(f) {
    e.keyboard_inset = f
  }
  if image_ready is Some(f) {
    e.image_ready = f
  }
  if focus_let_go is Some(f) {
    e.focus_let_go = Some(f)
  }
}

///|
/// The system's size of words its tree's words are drawn at (1: as said), followed: what reads it is worked out again
/// as all words are measured anew (View::words_redone). What a node lays out by words it measures itself, their size
/// said by it (ui's sp_at).
pub fn View::words_scale(self : View) -> Double {
  self.tree.words_redone.get() |> ignore
  (self.tree.env.words_scale)()
}

///|
/// How many pixels a point of its tree is where it is drawn: what is made for its pixels (a picture's curves cut as fine
/// as they show, a picture decoded as big as it is drawn) made for these.
pub fn View::pixel_scale(self : View) -> Double {
  (self.tree.env.pixel_scale)()
}

///|
/// Whether glass is drawn solid where its tree is drawn (the system's reduced transparency, or the app's choice): what
/// is drawn as a lens of glass drawn otherwise there.
pub fn View::glass_solid(self : View) -> Bool {
  (self.tree.env.glass_solid)()
}

///|
/// How far the soft keyboard reaches over the foot of the window its tree is drawn in, in points (0: down), followed as
/// it comes, moves and goes.
pub fn View::keyboard_inset(self : View) -> Double {
  (self.tree.env.keyboard_inset)()
}

///|
/// Whether the picture `src` is decoded, ready to show `px` pixels on its long side where its tree is drawn (its decode
/// asked for where it is not), followed as the host says a decode is ready.
pub fn View::image_ready(self : View, src : String, px : Double) -> Bool {
  (self.tree.env.image_ready)(src, px)
}

///|
/// The keyboard's focus let go of (what asks for none, a field written in done with, a press outside it): no field takes
/// keys, the keyboard goes, on either side of what hosts the tree (Tree::drawn_by's `focus_let_go`); where nothing
/// hosts it, the tree's own focus on none (Tree::focus_to).
pub fn View::focus_let_go(self : View) -> Unit {
  match self.tree.env.focus_let_go {
    Some(f) => f()
    None => self.tree.focus_to(None) |> ignore
  }
}
