// Images: decoded by the host to the size they are shown at (rounded up to
// a power of two, so a few sizes serve every layout), kept while used and
// dropped least recently used first once they take more than the budget.

///|
pub(all) enum Fit {
  /// fills the box, cropping what sticks out
  FitCover
  /// shows all of it inside the box
  FitContain
  /// stretched to the box
  FitFill
} derive(Eq)

///|
priv struct ImageEntry {
  id : Int
  px : Int // the long side it was asked for
  mut state : Int // 0 decoding, 1 ready, -1 failed
  mut w : Double
  mut h : Double
  mut ow : Double
  mut oh : Double
  mut used : Int // the frame it was last drawn
  mut ready_at : Double
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
  image_data[key] = data
}

///|
/// Hands over an encoded image to show as `key`, from outside a frame (a
/// core call's answer). Keys starting `mem:` show nothing until given.
pub fn add_image(key : String, data : Bytes) -> Unit {
  image_data[key] = data
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
      self.ready_at = now
    }
    self.state = st
  }
}

///|
/// The decode of `src` to show at `px` pixels on the long side: the
/// smallest ready one at least that big, else the biggest ready one while
/// a big enough one decodes (started here if none is).
fn Ctx::image_for(self : Ctx, src : String, px : Double) -> ImageEntry? {
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
  for e in list {
    e.poll(self.now)
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
      Some(d) => h_image_load_bytes(d, want, src)
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
    }
    e.poll(self.now)
    // smallest first
    let mut k = 0
    while k < list.length() && list[k].px < want {
      k = k + 1
    }
    list.insert(k, e)
    if e.state == 1 {
      good = Some(e)
    }
  }
  let r = if good is Some(_) { good } else { fallback }
  match r {
    Some(e) => e.used = self.frame_no
    None => ()
  }
  r
}

///|
/// The original's size in pixels, once any decode of it is ready.
fn image_size(src : String) -> (Double, Double)? {
  match image_cache.get(src) {
    Some(list) => {
      for e in list {
        e.poll(g().now)
        if e.state == 1 {
          return Some((e.ow, e.oh))
        }
      }
      None
    }
    None => None
  }
}

///|
/// Drops images not drawn this frame, least recently drawn first, until
/// what is kept fits the budget.
fn Ctx::trim_images(self : Ctx) -> Unit {
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
/// loaded, and it fades in.
pub fn Ctx::image(
  self : Ctx,
  src : String,
  w? : Size = Auto,
  h? : Size = Auto,
  fit? : Fit = FitCover,
  radius? : Double = 0.0,
  bg? : Int64 = 0xE5E5EAFFL,
  fade? : Bool = true,
) -> Int {
  let i = self.alloc_part(kind_image, true, false)
  let n = self.nodes[i]
  n.fade = fade
  n.text = src
  n.w = w
  n.h = h
  n.fit = fit
  n.radius = radius
  n.bg = bg
  i
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
      )
    None =>
      self.draw_image(
        n.text,
        n.x,
        n.y,
        n.fw,
        n.fh,
        n.fit,
        n.radius,
        alpha,
        fade=n.fade,
      )
  }
}

///|
/// How long an image takes to fade in once it is decoded (ms).
pub let image_fade_ms : Double = 150.0

///|
/// Draws the image from `src` in the box (x, y, w, h), loading it at the
/// size of the box.
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
) -> Unit {
  // a side still 0 waits for the image's proportions: load it anyway,
  // small if it has no size yet at all
  let px = dmin(dmax(bw, bh) * self.scale, max_px.to_double())
  let px = if px <= 0.0 { 256.0 } else { px }
  let e = match self.image_for(src, px) {
    Some(e) => e
    None => return
  }
  if bw <= 0.0 || bh <= 0.0 {
    return
  }
  let fade = if fade {
    dclamp((self.now - e.ready_at) / image_fade_ms, 0.0, 1.0)
  } else {
    1.0
  }
  if fade < 1.0 {
    self.request_frame()
  }
  let (x, y, w, h, u0, v0, du, dv) = match fit {
    FitFill => (bx, by, bw, bh, 0.0, 0.0, 1.0, 1.0)
    FitCover => {
      // the part of the image the box shows, centred
      let k = dmax(bw / e.w, bh / e.h)
      let du = bw / k / e.w
      let dv = bh / k / e.h
      (bx, by, bw, bh, (1.0 - du) / 2.0, (1.0 - dv) / 2.0, du, dv)
    }
    FitContain => {
      let k = dmin(bw / e.w, bh / e.h)
      let w = e.w * k
      let h = e.h * k
      (bx + (bw - w) / 2.0, by + (bh - h) / 2.0, w, h, 0.0, 0.0, 1.0, 1.0)
    }
  }
  self.push_inst(
    x, y, w, h, radius, 4.0, 0.0, 0.0, 0xFFFFFFFFL, alpha * fade, u0, v0, du,
    dv,
  )
  self.inst[(self.ninst - 1) * inst_size + 20] = e.id.to_double()
}
