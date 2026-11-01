// Images: decoded by the host to the size they are shown at (rounded up to
// a power of two, so a few sizes serve every layout), kept while used and
// dropped least recently used first once they take more than the budget.

///|
pub(all) enum Fit {
  /// fills the box, cropping what sticks out
  FitCover
  /// fills the box, placing the vertical crop at 0 (top) to 1 (bottom)
  FitCoverAt(Double)
  /// shows all of it inside the box
  FitContain
  /// stretched to the box
  FitFill
} derive(Eq)

///|
priv struct ImageEntry {
  id : Int
  mut px : Int // the long side it was asked for (0: drawn again since, shown only until that drawing is ready)
  mut state : Int // 0 decoding, 1 ready, -1 failed
  mut w : Double
  mut h : Double
  mut ow : Double
  mut oh : Double
  mut used : Int // the frame it was last drawn
  mut ready_at : Double
  // a sharper decode of a picture already shown (a smaller one was ready when this was asked for): that one's ready_at,
  // its fade gone on with as this takes its place, not started again from nothing
  follows : Double?
  // its fade in (image_fade_ms from ready_at), told once as it is first drawn fading (Ctx::moving)
  mover : Mover
  mut fade_told : Bool
}

///|
/// An image fading in is at rest image_fade_ms after it was ready.
impl Moving for ImageEntry with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.ready_at + image_fade_ms
}

///|
/// Decodes by source, smallest first.
let image_cache : Map[String, Array[ImageEntry]] = {}

///|
/// Encoded images the app handed over (thumbnails from the core, say), by
/// the key views show them by.
let image_data : Map[String, Bytes] = {}

///|
/// Decoded bytes kept before unused images are dropped.
let image_budget : Double = 192.0 * 1024.0 * 1024.0

///|
// kept across runs: scratch the host writes into before each read, read at once: nothing is carried in it
let image_info_out : FixedArray[Double] = FixedArray::make(4, 0.0)

///|
/// Hands over an encoded image (JPEG, PNG, HEIC, WebP…) to show as `key`.
pub fn Ctx::image_bytes(self : Ctx, key : String, data : Bytes) -> Unit {
  ignore(self)
  if !add_gif(key, data) {
    image_data[key] = data
  }
}

///|
/// Hands over an encoded image to show as `key`, from outside a frame (a
/// core call's answer). Keys starting `mem:` show nothing until given.
pub fn add_image(key : String, data : Bytes) -> Unit {
  // a GIF that moves: its frames each a picture (gif.mbt)
  if !add_gif(key, data) {
    image_data[key] = data
  }
}

///|
// kept across runs: set once as the app starts (its main), what draws vector pictures for every run after
/// What draws a vector picture (SVG) handed over as bytes: its bytes and the pixels wanted on its longer side to its
/// width, height and straight RGBA; None where it is not one. The app's main gives it (mbui/svg's rasterize), so a
/// program that shows none links no vector drawing.
let vector_pictures : Array[(Bytes, Int) -> (Int, Int, FixedArray[Byte])?] = []

///|
/// Sets what draws vector pictures (SVG) handed over as bytes (`add_image`, `Ctx::image_bytes`).
pub fn set_vector_pictures(draw : (Bytes, Int) -> (Int, Int, FixedArray[Byte])?) -> Unit {
  vector_pictures.clear()
  vector_pictures.push(draw)
}

///|
/// An encoded picture as the host decodes it: a vector one drawn here at `px` on its longer side, as a PNG.
fn host_bytes(data : Bytes, px : Int) -> Bytes {
  if vector_pictures.length() > 0 && looks_like_svg(data) {
    match vector_pictures[0](data, px) {
      Some((w, h, rgba)) => return png_of(w, h, rgba)
      None => ()
    }
  }
  data
}

///|
/// Draws the vector pictures handed over again, as what draws them can draw more of them now (a font it lacked come):
/// each shown as it was until its new drawing is ready (followed on from, not faded in again).
pub fn redraw_vector_pictures() -> Unit {
  @signals.start_batch()
  for src, list in image_cache {
    guard image_data.get(src) is Some(d) && looks_like_svg(d) else { continue }
    for e in list {
      if e.state == -1 {
        h_image_free(e.id)
      }
    }
    list.retain(fn(e) { e.state != -1 })
    for e in list {
      e.px = 0
    }
    let said = image_said(src)
    said.decodes.set(@signals.untracked(fn() { said.decodes.get() }) + 1)
  }
  @signals.end_batch()
}

///|
/// An `<svg` near the start of the bytes, or gzip's magic (an .svgz).
fn looks_like_svg(data : Bytes) -> Bool {
  if data.length() >= 2 && data[0] == b'\x1F' && data[1] == b'\x8B' {
    return true
  }
  let n = if data.length() < 1024 { data.length() } else { 1024 }
  for i in 0..<(n - 3) {
    if data[i] == b'<' && data[i + 1] == b's' && data[i + 2] == b'v' && data[i + 3] == b'g' {
      return true
    }
  }
  false
}

///|
/// Whether an image was handed over as `key` (add_image, Ctx::image_bytes): what one made from its key needs make only
/// once (a Tester starts without any).
pub fn has_image(key : String) -> Bool {
  image_data.contains(key)
}

///|
fn bucket(px : Double) -> Int {
  let mut b = 64
  while b.to_double() < px && b < 8192 {
    b = b * 2
  }
  b
}

///|
fn ImageEntry::poll(self : ImageEntry, now : Double) -> Unit {
  if self.state == 0 {
    let st = h_image_info(self.id, image_info_out)
    if st == 1 {
      self.w = image_info_out[0]
      self.h = image_info_out[1]
      self.ow = image_info_out[2]
      self.oh = image_info_out[3]
      self.ready_at = self.follows.unwrap_or(now)
    }
    self.state = st
  }
}

///|
/// The decode of `src` to show at `px` pixels on the long side: the
/// smallest ready one at least that big, else the biggest ready one while
/// a big enough one decodes (started here if none is).
fn Ctx::image_for(self : Ctx, src : String, px : Double) -> ImageEntry? {
  // (followed: which of its decodes is ready changes as the host says one is, or failed)
  image_decodes_read(src)
  // bytes still on their way: nothing to load yet
  if src.has_prefix("mem:") && !image_data.contains(src) {
    return None
  }
  let want = bucket(px)
  let list = match image_cache.get(src) {
    Some(l) => l
    None => {
      let l = []
      image_cache[src] = l
      l
    }
  }
  let mut good : ImageEntry? = None
  let mut fallback : ImageEntry? = None
  let mut pending = false
  let mut failed = false
  // (a decode is ready, or failed, as the host's word that it is says, at that word's moment: image_decoded; never as a
  // frame happens to look)
  for e in list {
    if e.state == -1 {
      failed = true
      continue
    }
    if e.px >= want {
      if e.state == 1 {
        if good is None {
          good = Some(e)
        }
      } else {
        pending = true
      }
    } else if e.state == 1 {
      fallback = Some(e)
    }
  }
  if good is None && !pending && !failed {
    let id = match image_data.get(src) {
      Some(d) => h_image_load_bytes(host_bytes(d, want), want, src)
      None =>
        if src.has_prefix("pdf:") {
          pdf_page_load(src, want)
        } else {
          h_image_load(src, want)
        }
    }
    let e = {
      id,
      px: want,
      state: 0,
      w: 0.0,
      h: 0.0,
      ow: 0.0,
      oh: 0.0,
      used: self.frame_no,
      ready_at: 0.0,
      follows: fallback.map(fn(f) { f.ready_at }),
      mover: Mover::new(),
      fade_told: false,
    }
    // smallest first
    let mut k = 0
    while k < list.length() && list[k].px < want {
      k = k + 1
    }
    list.insert(k, e)
    // (done at once, as the host decoded it, or failed, while asked: so at the moment it was asked, this build's, said
    // as a word of the host's that it is done is, image_decoded)
    image_done(src, e, self.clock)
    if e.state == 1 {
      good = Some(e)
    }
  }
  let r = if good is Some(_) { good } else { fallback }
  match r {
    Some(e) => {
      e.used = self.frame_no
      built_used(fn() { e.used = g().frame_no })
    }
    None => ()
  }
  r
}

///|
/// Whether the image at `src` is still coming at `px` on its long side (its bytes on their way, or a decode of it that
/// large not ready yet and not failed): a shot waits for it (shot.mbt).
fn image_awaited(src : String, px : Double) -> Bool {
  image_decodes_read(src)
  if src.has_prefix("mem:") && !image_data.contains(src) {
    return true
  }
  let want = bucket(px)
  match image_cache.get(src) {
    Some(list) => {
      let mut coming = false
      for e in list {
        if e.state == 1 && e.px >= want {
          return false
        }
        if e.state == 0 && e.px >= want {
          coming = true
        }
      }
      coming
    }
    None => false
  }
}

///|
/// The original's size in pixels, once any decode of it is ready.
fn image_size(src : String) -> (Double, Double)? {
  // (followed, by this picture alone: what reads its size worked out again as it is first known or changes, read
  // only: image_decoded)
  image_said(src).size.get()
}

///|
/// How many pixels on its long side `src` is decoded at to be shown in a box `bw` × `bh` at `fit`: the box's long
/// side, unless the picture covers the box and its proportions are known: then its own long side as it is drawn,
/// cropped. (A wide screenshot covering a square tile is as tall as the tile and several times as wide: decoded at the
/// tile's side it would be stretched several times over, blurred.)
fn Ctx::image_px(self : Ctx, src : String, bw : Double, bh : Double, fit : Fit) -> Double {
  match (fit, image_size(src)) {
    (FitCover | FitCoverAt(_), Some((ow, oh))) if ow > 0.0 && oh > 0.0 && bw > 0.0 && bh > 0.0 =>
      dmax(ow, oh) * dmax(bw / ow, bh / oh) * self.scale
    _ => dmax(bw, bh) * self.scale
  }
}

///|
/// Drops images not drawn this frame, least recently drawn first, until
/// what is kept fits the budget.
fn Ctx::trim_images(self : Ctx) -> Unit {
  images_said_trim()
  let mut total = 0.0
  for _, list in image_cache {
    for e in list {
      total = total + e.w * e.h * 4.0
    }
  }
  if total <= image_budget {
    return
  }
  let all : Array[(String, ImageEntry)] = []
  for src, list in image_cache {
    for e in list {
      if e.used < self.frame_no && e.state != 0 {
        all.push((src, e))
      }
    }
  }
  all.sort_by(fn(a, b) { a.1.used.compare(b.1.used) })
  for item in all {
    if total <= image_budget {
      break
    }
    let (src, e) = item
    total = total - e.w * e.h * 4.0
    h_image_free(e.id)
    match image_cache.get(src) {
      Some(list) => {
        list.retain(fn(x) { x.id != e.id })
        if list.length() == 0 {
          image_cache.remove(src)
          image_forget(src)
        }
      }
      None => ()
    }
  }
}

///|
/// An image from `src` (a file path, an http(s) URL, or a key given to
/// image_bytes). With one side Auto it keeps the image's proportions
/// (until the image is known that side is 0); `bg` shows until it has
/// loaded, and it fades in. With `matte`, the image is composited over `bg` before either is cut to its rounded edge;
/// the background remains in any part the image does not fill (as around a letterboxed video).
pub fn Ctx::image(
  self : Ctx,
  src : String,
  w? : Size = Auto,
  h? : Size = Auto,
  fit? : Fit = FitCover,
  radius? : Double = 0.0,
  bg? : Int64 = 0xE5E5EAFFL,
  fade? : Bool = true,
  still? : Bool = false,
  matte? : Bool = false,
) -> Int {
  let i = self.alloc_part(kind_image, true, false)
  let n = self.nodes[i]
  n.fade = fade
  n.matte = matte
  // a GIF that moves held at its first frame (gif.mbt)
  n.still = still
  // (its frame is picked as it is painted, after the build: what is built kept as it was drawn (a part, a list's row)
  // reads here when its next frame comes, so it is built again then and moves with nothing else changing)
  match moving_images.get(src) {
    Some(m) if !still && part_building() => ignore(self.loop_at(m.ends[m.ends.length() - 1], m.ends))
    _ => ()
  }
  n.text = src
  n.w = w
  n.h = h
  n.fit = fit
  n.radius = radius
  n.bg = bg
  i
}

///|
/// Whether `src` is decoded, ready to show `px` pixels on its long side (its decode started here where it is not): a
/// picture put in another's place keeps that one until this is, with no frame of nothing between.
pub fn Ctx::image_ready(self : Ctx, src : String, px : Double) -> Bool {
  match self.image_for(src, px) {
    Some(e) => e.state == 1
    None => false
  }
}

///|
/// Its size in the layout: proportional when one side is free.
fn image_leaf_size(
  n : Node,
  w : Double,
  wm : @flex.MeasureMode,
  h : Double,
  hm : @flex.MeasureMode,
) -> (Double, Double) {
  let (ow, oh) = match image_size(n.text) {
    Some(s) => s
    None => return (if wm == Exactly { w } else { 0.0 }, if hm == Exactly { h } else { 0.0 })
  }
  let ratio = if oh > 0.0 { ow / oh } else { 1.0 }
  if wm == Exactly && hm == Exactly {
    (w, h)
  } else if wm == Exactly {
    (w, w / ratio)
  } else if hm == Exactly {
    (h * ratio, h)
  } else {
    // its pixels at the screen's scale, no bigger than the room given
    let mut iw = ow / g().scale
    let mut ih = oh / g().scale
    if wm == AtMost && iw > w {
      ih = ih * w / iw
      iw = w
    }
    if hm == AtMost && ih > h {
      iw = iw * h / ih
      ih = h
    }
    (iw, ih)
  }
}

///|
fn Ctx::paint_image(self : Ctx, i : Int, n : Node, alpha : Double) -> Unit {
  // a stream's picture (Ctx::stream)
  if self.paint_stream(i, n, alpha) {
    return
  }
  let before = self.ninst
  match picture_at.get(i) {
    // drawn at a rect of its own (Ctx::picture)
    Some((x, y, w, h, max_px)) =>
      self.draw_image(
        n.text,
        n.x + x,
        n.y + y,
        w,
        h,
        FitFill,
        n.radius,
        alpha,
        fade=n.fade,
        max_px~,
        ground=n.bg,
        matte=n.matte,
        frame=if n.matte { Some((n.x, n.y, n.fw, n.fh)) } else { None },
      )
    None =>
      self.draw_image(
        self.moving_src(n),
        n.x,
        n.y,
        n.fw,
        n.fh,
        n.fit,
        n.radius,
        alpha,
        fade=n.fade,
        ground=n.bg,
        matte=n.matte,
      )
  }
  // (its corners each its own, where it was drawn: its ground's, its picture's)
  for k = before; k < self.ninst; k = k + 1 {
    self.corners_on(k, n)
  }
}

///|
/// What a picture node shows now: a GIF that moves the frame of its loop at this frame's time (Ctx::loop_at: as long as
/// its frames' lengths summed, a frame of the window as its next frame comes), unless held still; any other its source. Every frame of it is asked for at the size
/// it is shown, so each is decoded before its turn; one not yet is stood in for by the last one before it that is
/// (never a frame of nothing between them).
fn Ctx::moving_src(self : Ctx, n : Node) -> String {
  match moving_images.get(n.text) {
    Some(m) if !n.still => {
      let px = self.image_px(m.keys[0], n.fw, n.fh, n.fit)
      let px = if px <= 0.0 { 256.0 } else { px }
      let ready = m.keys.map(fn(k) { self.image_ready(k, px) })
      let length = m.ends[m.ends.length() - 1]
      let want = moving_frame(m, self.loop_at(length, m.ends) / length)
      let mut k = m.keys.search(want).unwrap_or(0)
      while k > 0 && !ready[k] {
        k = k - 1
      }
      if ready[k] {
        m.keys[k]
      } else {
        n.text
      }
    }
    _ => n.text
  }
}

///|
/// How long an image takes to fade in once it is decoded (ms).
pub let image_fade_ms : Double = 150.0

///|
/// Draws the image from `src` in the box (x, y, w, h), loading it at the
/// size of the box; `ground` under it until it is in (decoded, faded in), never under it once it is: its edge's
/// pixels, partly covered by it, would show that through as a rim round it. A `matte` is instead composited into the
/// same image before its edge is cut. `frame`, when given, is the box in which a picture and matte are drawn.
fn Ctx::draw_image(
  self : Ctx,
  src : String,
  bx : Double,
  by : Double,
  bw : Double,
  bh : Double,
  fit : Fit,
  radius : Double,
  alpha : Double,
  fade? : Bool = true,
  max_px? : Int = 8192,
  ground? : Int64 = 0L,
  matte? : Bool = false,
  frame? : (Double, Double, Double, Double)? = None,
) -> Unit {
  let (gx, gy, gw, gh) = frame.unwrap_or((bx, by, bw, bh))
  let grounded = (ground & 0xFFL) != 0L && gw > 0.0 && gh > 0.0
  // a side still 0 waits for the image's proportions: load it anyway,
  // small if it has no size yet at all
  let px = dmin(self.image_px(src, bw, bh, fit), max_px.to_double())
  let px = if px <= 0.0 { 256.0 } else { px }
  let e = match self.image_for(src, px) {
    Some(e) => e
    None => {
      if shooting.val && image_awaited(src, px) {
        shot_waits.val = true
      }
      if grounded {
        self.emit_rect(gx, gy, gw, gh, radius, ground, 0.0, 0L, alpha)
      }
      return
    }
  }
  if bw <= 0.0 || bh <= 0.0 || (matte && (gw <= 0.0 || gh <= 0.0)) {
    return
  }
  // (in a shot: whole, and one still decoding there waited for)
  if shooting.val && image_awaited(src, px) {
    shot_waits.val = true
  }
  let fade = if fade && !shooting.val {
    dclamp((self.now_before(e.ready_at + image_fade_ms) - e.ready_at) / image_fade_ms, 0.0, 1.0)
  } else {
    1.0
  }
  if grounded && fade < 1.0 && !matte {
    self.emit_rect(bx, by, bw, bh, radius, ground, 0.0, 0L, alpha)
  }
  if fade < 1.0 && !e.fade_told {
    e.fade_told = true
    self.moving(e.mover, e, what="image \"\{src}\" fading in")
  }
  let (x, y, w, h, u0, v0, du, dv) = match fit {
    FitFill => (bx, by, bw, bh, 0.0, 0.0, 1.0, 1.0)
    FitCover | FitCoverAt(_) => {
      // The part of the image the box shows, centred across and placed vertically by fit.
      let k = dmax(bw / e.w, bh / e.h)
      let du = bw / k / e.w
      let dv = bh / k / e.h
      let vertical = match fit { FitCoverAt(y) => dclamp(y, 0.0, 1.0); _ => 0.5 }
      (bx, by, bw, bh, (1.0 - du) / 2.0, (1.0 - dv) * vertical, du, dv)
    }
    FitContain => {
      let k = dmin(bw / e.w, bh / e.h)
      let w = e.w * k
      let h = e.h * k
      (bx + (bw - w) / 2.0, by + (bh - h) / 2.0, w, h, 0.0, 0.0, 1.0, 1.0)
    }
  }
  if w <= 0.0 || h <= 0.0 {
    return
  }
  if matte {
    // Draw the whole frame once. UVs outside the fitted picture say where its matte shows; the shader composites the
    // picture over the matte before the frame's own and enclosing clips cover their edges.
    self.push_inst(
      gx, gy, gw, gh, radius, 4.0, 0.0, 0.0, 0xFFFFFFFFL, alpha,
      u0 + (gx - x) * du / w, v0 + (gy - y) * dv / h, gw * du / w, gh * dv / h,
    )
    let base = (self.ninst - 1) * inst_size
    self.inst[base + 8] = ((ground >> 24) & 0xFFL).to_double() / 255.0
    self.inst[base + 9] = ((ground >> 16) & 0xFFL).to_double() / 255.0
    self.inst[base + 10] = ((ground >> 8) & 0xFFL).to_double() / 255.0
    self.inst[base + 21] = (ground & 0xFFL).to_double() / 255.0
    self.inst[base + 22] = 1.0
    self.inst[base + 23] = fade
  } else {
    self.push_inst(
      x, y, w, h, radius, 4.0, 0.0, 0.0, 0xFFFFFFFFL, alpha * fade, u0, v0, du,
      dv,
    )
  }
  self.inst[(self.ninst - 1) * inst_size + 20] = e.id.to_double()
}

///|
/// What is said of a picture (by its source) as the host's words about its decodes come (image_decoded): its size once
/// one is ready (told where it is new: what lays it out follows it), and its decodes' states (told as one is ready or
/// fails: what draws it, waits for it or asks whether it is ready follows it). That picture's alone.
priv struct ImageSaid {
  size : @signals.Signal[(Double, Double)?]
  decodes : @signals.Signal[Int]
}

///|
// kept across runs: what is said of the pictures kept, gone with them (image_forget, Tester's reset)
let images_said : Map[String, ImageSaid] = {}

///|
fn image_said(src : String) -> ImageSaid {
  match images_said.get(src) {
    Some(s) => s
    None => {
      let s = { size: @signals.signal(None, same=fn(a, b) { a == b }), decodes: @signals.signal(0) }
      images_said[src] = s
      s
    }
  }
}

///|
/// Whether something follows what is said of a picture.
fn ImageSaid::watched(self : ImageSaid) -> Bool {
  self.size.watched() || self.decodes.watched()
}

///|
/// Read where what is built follows the states of `src`'s decodes (one ready, or failed).
fn image_decodes_read(src : String) -> Unit {
  image_said(src).decodes.get() |> ignore
}

///|
/// What is said of the picture `src`, let go with its decodes: unless something follows it still (its signal, the one it
/// reads, kept for it).
fn image_forget(src : String) -> Unit {
  match images_said.get(src) {
    Some(s) if !s.watched() && !image_cache.contains(src) => images_said.remove(src)
    _ => ()
  }
}

///|
/// What is said of the pictures no longer kept and followed by nothing (one read of a picture never decoded, say).
fn images_said_trim() -> Unit {
  let gone = []
  for src, s in images_said {
    if !s.watched() && !image_cache.contains(src) {
      gone.push(src)
    }
  }
  for src in gone {
    images_said.remove(src)
  }
}

///|
/// Decode `e` of `src` (in its cache already) as the host has it at `at`: where it is done (ready, or failed), so as of
/// then, and said: that picture's size where it is ready (told where it is new), its decodes' state told.
fn image_done(src : String, e : ImageEntry, at : Double) -> Unit {
  e.poll(at)
  if e.state == 0 {
    return
  }
  // (its size and its decodes' state told as one: what reads both sees both, never one)
  let said = image_said(src)
  @signals.start_batch()
  if e.state == 1 {
    said.size.set(Some((e.ow, e.oh)))
  }
  said.decodes.set(@signals.untracked(fn() { said.decodes.get() }) + 1)
  @signals.end_batch()
}

///|
/// The host said decode `id` is done (or could not be), at `at` (its word's moment): it is ready then (its fade from
/// then, or on from the one it follows), and its picture's size told, that picture's alone, where it is new.
fn image_decoded(id : Int, at : Double) -> Unit {
  for src, list in image_cache {
    for e in list {
      if e.id == id {
        image_done(src, e, at)
        return
      }
    }
  }
}
