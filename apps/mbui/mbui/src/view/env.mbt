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
  mut image_ask : (String, Double) -> Unit
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
    image_ask: fn(_, _) {  },
    focus_let_go: None,
  }
}

///|
/// What hosts the tree says of where its nodes are drawn, each read as a node asks it (what is not said, as it was):
/// `words_scale` the system's size of words its words are drawn at (as they are measured: ui's Ctx::sp); `pixel_scale`
/// how many pixels a point is; `glass_solid` whether glass is drawn solid; `keyboard_inset` how far the soft keyboard
/// reaches over the window's foot, in points; `image_ready` whether a picture is decoded ready to show so many pixels on
/// its long side, asking for nothing; `image_ask` its decode asked for that large where none is ready or coming;
/// `focus_let_go` the window's focus let go of, on either side.
pub fn Tree::drawn_by(
  self : Tree,
  words_scale? : () -> Double,
  pixel_scale? : () -> Double,
  glass_solid? : () -> Bool,
  keyboard_inset? : () -> Double,
  image_ready? : (String, Double) -> Bool,
  image_ask? : (String, Double) -> Unit,
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
  if image_ask is Some(f) {
    e.image_ask = f
  }
  if focus_let_go is Some(f) {
    e.focus_let_go = Some(f)
  }
}

///|
/// The system's size of words its tree's words are drawn at (1: as said), followed: what reads it is worked out again
/// as all words are measured anew (View::words_redone). What a node lays out by words it measures itself, their size
/// said by it (ui's sp_at). 1 where it was made with its words as said (View::box's `words_as_said`): the one way it is
/// read, by what is made (this) and by what hosts the tree as it measures and draws a node's words
/// (Tree::words_scale_of).
pub fn View::words_scale(self : View) -> Double {
  self.tree.words_redone.get() |> ignore
  self.tree.words_scale_at(self.at)
}

///|
/// The size of words node `id`'s words are measured and drawn at (View::words_scale's, not followed): what hosts the
/// tree measures and draws them by.
pub fn Tree::words_scale_of(self : Tree, id : NodeId) -> Double {
  self.words_scale_at(id.at)
}

///|
/// Said by a part whose words its host draws at the system's size of words whatever its node says (`what`: a field,
/// its words the editor's, ui's Ctx::editor_sizing), as its node is made: where that node's words are as said
/// (View::box's `words_as_said`), a fault naming where it was made and why, under a tree that keeps where its nodes
/// were made (a Tester's, source.mbt); a device's keeps none, and nothing is done there.
pub fn View::words_follow_system(self : View, what : String) -> Unit {
  guard self.live() is Some(n) && n.words_as_said && n.source is Some(_) else { return }
  let (made, part) = self.tree.source_of(self.id())
  let in_part = if part == "" { "" } else { " (in what was asked for at \{part})" }
  self.fault(
    "\{what} made at \{made}\{in_part}, where words are drawn at the size they are said (View::box's words_as_said): its words are drawn at the system's size of words all the same, not as said there",
  )
}

///|
/// The size of words node `at`'s words are at: 1 where it was made with its words as said, else the system's.
fn Tree::words_scale_at(self : Tree, at : Int) -> Double {
  if at >= 0 && at < self.nodes.length() && self.nodes[at].words_as_said {
    1.0
  } else {
    (self.env.words_scale)()
  }
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
/// Whether the picture `src` is decoded, ready to show `px` pixels on its long side where its tree is drawn, followed as
/// the host says a decode is ready. It asks for none: a picture is decoded as what draws the tree comes to it (its node
/// drawn, or gone through outside what shows), or where View::image_ask asks it; so a node made and let go of in one
/// change, never drawn, has nothing decoded for it. What that costs, taken: a node drawing its picture itself made
/// between frames, outside a list, has its decode asked by the next frame's paint, a frame's wait later at most than
/// when this asked it as the node was made; made in a frame's layout
/// (every block of a page's list) nothing differs. Under the Tester's host, which decodes by the frame after it is
/// asked, that is a frame of what stands in for it at the node's moment, its reveal setting out at the same moment
/// (the app's sf/image_reveal_node_wbtest, sfpages/message_media_cmp_wbtest, message_media_node_wbtest and
/// message_video_node_wbtest, each a chat's message made as nodes). One made so that is to show at once (a card opening)
/// asks for it as it is made (View::image_ask).
pub fn View::image_ready(self : View, src : String, px : Double) -> Bool {
  (self.tree.env.image_ready)(src, px)
}

///|
/// The picture `src` asked to be decoded to show `px` pixels on its long side where its tree is drawn, where no decode
/// that large is ready or coming: for a picture wanted before any node of it is drawn (one whose node is made only once
/// it is decoded, or one fetched ahead on purpose). Its bytes are held from then, as a drawn one's are. Said in a change,
/// it is asked as that change ends, the outermost (Tree::change_ended); said in a frame's layout (View::by_room, a page's
/// list's fill), as that layout ends, before its paint (Tree::brought); in either only where this node still stands
/// then: one made and let go of in it (a page's list's block in one pass of its fill, gone in a later) asks nothing.
/// A frame's layout always ends so; one laid out outside a frame (Tree::measured_now, View::grows_now) leaves what it
/// asked to the next of the two. Outside every change and layout, at once. Said again it asks nothing more: a read
/// that says it each time it runs (a face's, whose node waits for its decode) relies on what hosts the tree asking
/// nothing where a decode that large is ready or coming (Tree::drawn_by's `image_ask`); one that asked each time
/// would have those ask in a loop.
pub fn View::image_ask(self : View, src : String, px : Double) -> Unit {
  if self.tree.in_change() {
    self.tree.images_wanted.push((self.id(), src, px))
  } else {
    (self.tree.env.image_ask)(src, px)
  }
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
