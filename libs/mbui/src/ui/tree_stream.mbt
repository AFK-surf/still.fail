// A stream (stream.mbt: a picture the host decodes frame by frame) as a node of the window's tree (ui's stream), in
// place of an old view's Ctx::stream. Drawn where the tree draws the node, each frame it is drawn, as big, fitted to it
// as said, at its opacity, in its clip and corners, under what the tree draws after it: the picture the stream shows
// that frame (the last frame its host said decoded, latched as the frame began), nothing until one is. Drawn anew each
// time it is drawn, as a picture is (no row it is in kept and drawn again as kept, nor a list drawn whole as one), so
// that each frame draws the frame shown then. What becomes of each frame handed over is the stream's to say, as ever
// (Stream::new's `shown`, once that frame is painted: drawn or let go). Let go with its node (View::owns): closed then,
// unless what holds it closes it itself (`closes` false: it is only no longer drawn there). Drawn by the app's canvas,
// never on a system video layer (Ctx::stream's `layer`), as it is drawn in the tree's order.

///|
/// A stream of the window's tree's: the stream, how its picture is fitted to its node, whether its node closes it.
priv struct TreeStream {
  stream : Stream
  fit : Fit
  closes : Bool
}

///|
/// The streams of the window's tree, by the node each is drawn in.
// kept across runs: emptied as a run begins (view_forget); each let go with its node (tree_stream_gone)
let tree_streams : Map[@view.NodeId, TreeStream] = Map([])

///|
/// How many times a stream was put in tree_streams or taken out: what view_draws reads besides a node's content (as
/// tree_natives_rev).
// kept across runs: only counts
let tree_streams_rev : Ref[Int] = Ref(0)

///|
/// Stream `s` drawn in a box of `parent`'s, as big as the box is said to be (by default the room its holder leaves it),
/// its picture fitted to it as `fit` says (FitFill: stretched; FitCover, FitContain as an image's), its corners its own
/// (View::radius). Let go with the node: the stream closed, unless not `closes` (what holds it closes it). One stream in
/// one node: given to another while one draws it, a fault. The box made.
#callsite(autofill(loc))
pub fn stream(
  parent : @view.View,
  s : Stream,
  fit? : Fit = FitFill,
  closes? : Bool = true,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    let id = b.id()
    if tree_streams.iter().any(fn(e) { e.0 != id && physical_equal(e.1.stream, s) }) {
      b.fault("stream: one stream given to two nodes of the tree's: a stream is drawn in one place")
    }
    tree_streams_rev.val = tree_streams_rev.val + 1
    tree_streams[id] = { stream: s, fit, closes }
    b.owns(fn() { tree_stream_gone(id) }) |> ignore
  })
}

///|
/// Stream node `id` let go: its stream closed, or, closed by what holds it, only no longer drawn there.
fn tree_stream_gone(id : @view.NodeId) -> Unit {
  guard tree_streams.get(id) is Some(ts) else { return }
  tree_streams.remove(id)
  tree_streams_rev.val = tree_streams_rev.val + 1
  if ts.closes {
    ts.stream.close()
  }
}

///|
/// Stream node `ts` drawn this frame at (`x`, `y`), `w` × `h` where it is drawn, its corners `radius` round, as opaque as
/// `a`: the picture its stream shows, fitted as it says, as Ctx::paint_stream places an old view's; nothing until one
/// shows.
fn Ctx::paint_tree_stream(
  self : Ctx,
  ts : TreeStream,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  a : Double,
) -> Unit {
  let s = ts.stream
  let (pw, ph) = match s.size {
    Some((pw, ph)) if !s.closed && s.id != 0 && pw > 0 && ph > 0 => (pw.to_double(), ph.to_double())
    _ => return
  }
  if w <= 0.0 || h <= 0.0 {
    return
  }
  let (x, y, w, h, u0, v0, du, dv) = match ts.fit {
    FitFill => (x, y, w, h, 0.0, 0.0, 1.0, 1.0)
    FitCover | FitCoverAt(_) => {
      let k = dmax(w / pw, h / ph)
      let du = w / k / pw
      let dv = h / k / ph
      let vertical = match ts.fit { FitCoverAt(y) => dclamp(y, 0.0, 1.0); _ => 0.5 }
      (x, y, w, h, (1.0 - du) / 2.0, (1.0 - dv) * vertical, du, dv)
    }
    FitContain => {
      let k = dmin(w / pw, h / ph)
      let cw = pw * k
      let ch = ph * k
      (x + (w - cw) / 2.0, y + (h - ch) / 2.0, cw, ch, 0.0, 0.0, 1.0, 1.0)
    }
  }
  self.push_inst(x, y, w, h, radius, 4.0, 0.0, 0.0, 0xFFFFFFFFL, a, u0, v0, du, dv)
  self.inst[(self.ninst - 1) * inst_size + 20] = (@hostapi.stream_tex_base + s.id).to_double()
}
