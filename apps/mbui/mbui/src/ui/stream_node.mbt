// A decoded stream as the content of a retained tree node. The stream and its decoder are owned by the caller.

///|
/// Draw `stream` in `node` as it changes. The node decides its own size and position, including a cropped or moved
/// picture; its opacity and those of its holders apply to the picture. `layer` allows the system's video layer when
/// the picture can be shown there as it is. If the stream can be replaced, `stream` must read a signal that changes on
/// replacement. The caller keeps and closes the stream separately from the node.
pub fn stream_in(
  node : @view.View,
  stream : () -> Stream?,
  layer? : () -> Bool = fn() { true },
  fit? : () -> Fit = fn() { FitFill },
  pointer? : StreamPointer? = None,
) -> @view.View {
  match pointer {
    Some(p) => stream_pointer_picture(node, p)
    None => ()
  }
  node.texture(By(fn() {
    match stream() {
      Some(s) => {
        let revision = s.picture.get()
        let allowed = layer()
        let how = match fit() {
          FitFill => @view.TextureFill
          FitCover => @view.TextureCover(0.5)
          FitCoverAt(y) => @view.TextureCover(dclamp(y, 0.0, 1.0))
          FitContain => @view.TextureContain
        }
        match s.size {
          Some((w, h)) if !s.closed && s.id != 0 && w > 0 && h > 0 =>
            Some({
              id: @hostapi.stream_tex_base + s.id,
              width: w,
              height: h,
              fit: how,
              direct: allowed && s.h264 && s.view is Some(_),
              revision,
            })
          _ => None
        }
      }
      None => None
    }
  }))
}

///|
/// A host texture drawn at the tree node's composed place, in the clip already open for that node.
fn Ctx::paint_tree_texture(
  self : Ctx,
  c : @view.Content,
  texture : @view.Texture,
  x : Double,
  y : Double,
  scale : Double,
  alpha : Double,
) -> Unit {
  let (bw, bh) = (c.w * scale, c.h * scale)
  let (pw, ph) = (texture.width.to_double(), texture.height.to_double())
  if bw <= 0.0 || bh <= 0.0 || pw <= 0.0 || ph <= 0.0 {
    return
  }
  let (x, y, w, h, u, v, du, dv) = match texture.fit {
    TextureFill => (x, y, bw, bh, 0.0, 0.0, 1.0, 1.0)
    TextureCover(vertical) => {
      let k = dmax(bw / pw, bh / ph)
      let (du, dv) = (bw / k / pw, bh / k / ph)
      (x, y, bw, bh, (1.0 - du) / 2.0, (1.0 - dv) * vertical, du, dv)
    }
    TextureContain => {
      let k = dmin(bw / pw, bh / ph)
      let (w, h) = (pw * k, ph * k)
      (x + (bw - w) / 2.0, y + (bh - h) / 2.0, w, h, 0.0, 0.0, 1.0, 1.0)
    }
  }
  self.push_inst(x, y, w, h, c.radius * scale, 4.0, 0.0, 0.0, 0xFFFFFFFFL, alpha, u, v, du, dv)
  match c.corners {
    Some((tl, tr, br, bl)) => self.corners_last_each(tl * scale, tr * scale, br * scale, bl * scale)
    None => ()
  }
  self.inst[(self.ninst - 1) * inst_size + 20] = texture.id.to_double()
}
