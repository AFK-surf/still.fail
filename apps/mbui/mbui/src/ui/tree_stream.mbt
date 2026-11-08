// A decoder's picture owned by a retained node, without an old-view island.
// The Stream remains the caller's resource: removing a node stops displaying it,
// but does not close a stream that another part of the application still owns.

///|
priv struct TreeStream {
  stream : Stream
  content : @signals.Signal[(Double, Double, Double, Double)?]
  layer : @signals.Signal[Bool]
  fit : Fit
}

///|
let tree_streams : Map[@view.NodeId, TreeStream] = Map([])

///|
/// Show a stream in a retained node. Its size, placement, opacity and corners are
/// the returned node's properties. Content coordinates are local to that node.
/// System video layers are used for whole, opaque H.264 pictures; other pictures
/// use the decoder's texture, with the same fitting as Ctx::stream.
pub fn stream_node(
  parent : @view.View,
  stream : Stream,
  fit? : Fit = FitFill,
  content? : () -> (Double, Double, Double, Double)? = fn() { None },
  layer? : () -> Bool = fn() { true },
) -> @view.View {
  parent.box(fn(v) {
    let id = v.id()
    let entry : TreeStream = {
      stream, fit,
      content: @signals.signal(None),
      layer: @signals.signal(true),
    }
    tree_streams[id] = entry
    v.reacts(content, fn(at) { entry.content.set(at) })
    v.reacts(layer, fn(on) { entry.layer.set(on) })
    v.owns(fn() { tree_streams.remove(id) }) |> ignore
  })
}

///|
fn Ctx::paint_tree_stream(self : Ctx, c : @view.Content, x : Double, y : Double, scale : Double, alpha : Double) -> Unit {
  let entry = match tree_streams.get(c.id) {
    Some(entry) if c.bones == 0L => entry
    _ => return
  }
  let stream = entry.stream
  let content = entry.content.get().map(fn(r) { (r.0 * scale, r.1 * scale, r.2 * scale, r.3 * scale) })
  let layer = entry.layer.get()
  let box = (x, y, c.w * scale, c.h * scale)
  let corners = match c.corners {
    Some((tl, tr, br, bl)) => (tl * scale, tr * scale, br * scale, bl * scale)
    None => (c.radius * scale, c.radius * scale, c.radius * scale, c.radius * scale)
  }
  let (was, was_tree) = (inst_owners.painting, inst_owners.tree_painting)
  inst_owners.painting = -1
  inst_owners.tree_painting = Some(c.id)
  match stream.view {
    Some(view) if layer && stream.h264 && entry.fit is FitFill &&
      corners == (0.0, 0.0, 0.0, 0.0) && alpha == 1.0 && !stream.closed && stream.at is Some(_) =>
      self.paint_native_at(view, box, content, FixedArray::make(4, 0.0))
    _ => {
      let before = self.ninst
      self.paint_stream_image(stream, box, content, entry.fit, c.radius * scale, alpha)
      if self.ninst > before {
        self.corners_last_each(corners.0, corners.1, corners.2, corners.3)
      }
    }
  }
  inst_owners.painting = was
  inst_owners.tree_painting = was_tree
}
