// Each glyph of what a node holds drawn by a look of its own (View::glyphs_by): words coming in a glyph at a time, or
// giving way to others a glyph at a time. Worked out for a moment its binding says (none: as laid out), as an old
// view's Ctx::glyphs_by works out each as it is painted: what is drawn is made again for each moment, nothing laid out.

///|
/// A glyph as it is drawn, for its own look (View::glyphs_by): its number (from 0 in the order drawn, the order read
/// in, through all the node holds), where its line's box starts (x, y in the window) and its line's height, and the top
/// and foot of what cuts the node that says the looks (the window's part it shows in). What is not a glyph (a list's
/// mark, a code block's ground) is said with the number of the glyph after it, its own box's start and height.
pub(all) struct GlyphAt {
  index : Int
  x : Double
  y : Double
  h : Double
  top : Double
  foot : Double
} derive(Eq, Debug)

///|
/// How a glyph is drawn off where it is laid out: how opaque, how far across and down, how big about its middle, and
/// how wide besides.
pub(all) struct GlyphLook {
  alpha : Double
  dx : Double
  dy : Double
  scale : Double
  sx : Double
} derive(Eq, Debug)

///|
/// Each glyph of the words it holds (its own and all in it) drawn with what `look` gives for it at the moment it is
/// painted at, while `at` says one (None: as laid out, its looks let go): what it draws is made again as that changes
/// (a binding reading the moment drawn at: each frame), nothing laid out. `look` works out the same for the same
/// moment and glyph.
pub fn View::glyphs_by(self : View, at : Live[Double?], look : (Double, GlyphAt) -> GlyphLook) -> View {
  guard self.live() is Some(_) else { return self }
  let tree = self.tree
  let (i, gen) = (self.at, self.gen)
  tree.glyph_looks[i] = (gen, look)
  self.owns(fn() {
    match tree.glyph_looks.get(i) {
      Some((g, _)) if g == gen => tree.glyph_looks.remove(i)
      _ => ()
    }
  })
  |> ignore
  self.bind(Glyphs, at, Paint, fn(t) { tree.nodes[i].look.glyphs_at = t })
  self
}

///|
/// How node `id` says the glyphs it holds are drawn (View::glyphs_by), by the moment they are painted at, while it says
/// one (its binding's moment told: what is painted is made again as that changes); None as laid out.
pub fn Tree::glyphs_of(self : Tree, id : NodeId) -> ((Double, GlyphAt) -> GlyphLook)? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let n = self.nodes[id.at]
  match (n.look.glyphs_at, self.glyph_looks.get(id.at)) {
    (Some(_), Some((g, f))) if g == id.gen && n.live && n.gen == id.gen => Some(f)
    _ => None
  }
}
