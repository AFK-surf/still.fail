// Words' halo (View::words_halo): the cover of their glyphs, as they are laid out and drawn, blurred and drawn in one
// colour under them, as CSS's text-shadow with no offset. The host gives each glyph's picture back as it draws it
// (@hostapi.glyph_picture); their cover is added up here where each glyph is drawn, blurred by three boxes each way (a
// Gaussian's within a few hundredths), brought up till its densest point covers wholly, and put in the words' atlas
// as a glyph of its own (@hostapi.atlas_put), drawn
// by an instance of a glyph's kind stretched over it (scene.mbt's kind 1: a mask's three the same as its alpha), so it
// is as opaque, cut, moved and big as its words wherever they are composed. A halo is blurred once for the glyphs,
// places and pixels a point it is of and kept here, put in the atlas again as the atlas lets it go (its key its own,
// below -1, apart from the host's), not blurred again; what was blurred of glyphs the host draws anew (its faces, its
// scale: atlas_generation) is let go with them. Where the host gives no picture back or takes no pixels, none is
// drawn, for the rest of the run: the words drawn as ever.

///|
/// A halo blurred: its cover, `w` by `h` pixels (a byte each), and where it lies from its words' first glyph and how
/// big, in points; what it is of (halo_said).
priv struct HaloPicture {
  said : String
  w : Int
  h : Int
  cover : FixedArray[Byte]
  dx : Double
  dy : Double
  pw : Double
  ph : Double
}

///|
priv struct Halos {
  // each halo's key (below -1, the host's own 0 and up) by what it is of (halo_said), and the next
  keyed : Map[String, Int]
  mut next : Int
  // what was blurred, by key: halos_kept at most, the oldest let go first
  pictures : Map[Int, HaloPicture]
  // whether the host was found to give no glyph's picture back, or to take no pixels
  mut none : Bool
  // halos blurred, and put in the atlas (one put again as the atlas let it go is not blurred again): for a test
  mut blurred : Int
  mut put : Int
  // what words drawn with a halo gather as their glyphs are emitted: each glyph's instance and key (halo_told)
  mut gather : Array[Int]?
}

///|
let halos : Halos = {
  keyed: Map([]),
  next: -2,
  pictures: Map([]),
  none: false,
  blurred: 0,
  put: 0,
  gather: None,
}

///|
/// How many halos blurred are kept at once (each a byte a pixel: a label's some ten thousand).
let halos_kept : Int = 256

///|
/// What was blurred let go (the glyphs it was of drawn anew: their faces, their scale; a Tester starting over).
fn halos_forget() -> Unit {
  halos.keyed.clear()
  halos.pictures.clear()
  halos.gather = None
}

///|
/// Glyph `key` emitted as instance `at`: gathered for the halo of the words being drawn, if they have one.
fn halo_told(at : Int, key : Int) -> Unit {
  match halos.gather {
    Some(a) => {
      a.push(at)
      a.push(key)
    }
    None => ()
  }
}

///|
/// The instance a halo is drawn by, made before the glyphs it is under (filled once they are: Ctx::halo_fill), in
/// `ink`, nothing drawn till then; and what gathers them started. -1 where none is drawn.
fn Ctx::halo_start(self : Ctx, blur : Double, ink : Int64) -> Int {
  if halos.none || blur <= 0.0 || (ink & 0xFFL) == 0L {
    return -1
  }
  // (in its own colour: no ink worked out for what is painted (Ctx::ink_by) nor a glyph's own look (glyphs_by) on it)
  let was_ink = ink_now.val
  ink_now.val = None
  glyph_pushing.val = true
  self.push_inst(0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, ink, 1.0, 0.0, 0.0, 0.0, 0.0)
  glyph_pushing.val = false
  ink_now.val = was_ink
  halos.gather = Some([])
  self.ninst - 1
}

///|
/// The halo of the glyphs gathered since Ctx::halo_start made instance `at`, `blur` its sigma in points: its place in
/// the atlas (blurred, or as blurred before), and instance `at` drawing it over them all, under them; none where they
/// draw nothing or the host gives no pictures (`at` left drawing nothing).
fn Ctx::halo_fill(self : Ctx, at : Int, blur : Double) -> Unit {
  let gathered = halos.gather.unwrap_or([])
  halos.gather = None
  if at < 0 {
    return
  }
  let a = self.inst
  let b = at * inst_size
  // (nothing till it is drawn)
  let alpha = a[b + 11]
  a[b + 11] = 0.0
  let sc = self.scale
  let glyphs : Array[(Int, Int)] = []
  let mut k = 0
  while k + 1 < gathered.length() {
    let i = gathered[k]
    if a[i * inst_size + 2] > 0.0 && a[i * inst_size + 3] > 0.0 && a[i * inst_size + 14] >= 1.0 {
      glyphs.push((i, gathered[k + 1]))
    }
    k += 2
  }
  if glyphs.is_empty() || halos.none || sc <= 0.0 {
    return
  }
  let (x0, y0) = (a[glyphs[0].0 * inst_size], a[glyphs[0].0 * inst_size + 1])
  let said = halo_said(a, glyphs, x0, y0, blur, sc)
  let key = match halos.keyed.get(said) {
    Some(key) => key
    None => {
      let key = halos.next
      halos.next = key - 1
      halos.keyed[said] = key
      key
    }
  }
  let pic = match halos.pictures.get(key) {
    Some(p) => p
    None =>
      match halo_blurred(a, glyphs, x0, y0, blur, sc, said) {
        Some(p) => {
          halo_keep(key, p)
          p
        }
        None => return
      }
  }
  guard halo_cell(key, pic, sc) is Some(g) else { return }
  a[b] = x0 + pic.dx
  a[b + 1] = y0 + pic.dy
  a[b + 2] = pic.pw
  a[b + 3] = pic.ph
  a[b + 11] = alpha
  a[b + 12] = g.u
  a[b + 13] = g.v
  a[b + 14] = pic.w.to_double()
  a[b + 15] = pic.h.to_double()
}

///|
/// What a halo is of: its blur, the pixels a point, and each glyph's key and where it is drawn from the first, in its
/// cell's pixels: the same words, look, size and scale say the same.
fn halo_said(
  a : FixedArray[Double],
  glyphs : Array[(Int, Int)],
  x0 : Double,
  y0 : Double,
  blur : Double,
  sc : Double,
) -> String {
  let s = StringBuilder()
  let q = fn(v : Double) { (v * 64.0).round().to_int64() }
  s.write_string("\{q(blur)} \{q(sc)}")
  for gl in glyphs {
    let (i, key) = gl
    let b = i * inst_size
    s.write_string(
      " \{key}:\{q(a[b] - x0)},\{q(a[b + 1] - y0)},\{q(a[b + 2])},\{q(a[b + 3])},\{q(a[b + 14])},\{q(a[b + 15])}",
    )
  }
  s.to_string()
}

///|
/// Halo `p` kept as `key`'s, the oldest let go past halos_kept (and what it was of with it).
fn halo_keep(key : Int, p : HaloPicture) -> Unit {
  if halos.pictures.length() >= halos_kept {
    let mut first : (Int, String)? = None
    for k, old in halos.pictures {
      first = Some((k, old.said))
      break
    }
    match first {
      Some((k, said)) => {
        halos.pictures.remove(k)
        halos.keyed.remove(said)
      }
      None => ()
    }
  }
  halos.pictures[key] = p
}

///|
/// The halo of `glyphs` (instance, key) drawn as `a` has them, `blur` its sigma in points, at `sc` pixels a point: the
/// cover of their pictures as the host gives them back, added up where each is drawn, blurred. None where the host gives
/// none (none asked again in this run: halos' `none`).
fn halo_blurred(
  a : FixedArray[Double],
  glyphs : Array[(Int, Int)],
  x0 : Double,
  y0 : Double,
  blur : Double,
  sc : Double,
  said : String,
) -> HaloPicture? {
  // (as far as the blur reaches past them: three of its sigma)
  let m = blur * 3.0
  let mut l = 1.0e300
  let mut t = 1.0e300
  let mut r = -1.0e300
  let mut f = -1.0e300
  for gl in glyphs {
    let b = gl.0 * inst_size
    l = dmin(l, a[b])
    t = dmin(t, a[b + 1])
    r = dmax(r, a[b] + a[b + 2])
    f = dmax(f, a[b + 1] + a[b + 3])
  }
  let (l, t, r, f) = (l - m, t - m, r + m, f + m)
  // (pixels a point it is blurred at: the window's, halved while the blur is six of them or more (no more of its
  // detail left once blurred), and till it fits a plot of the atlas)
  let mut px = sc
  while blur * px >= 6.0 {
    px = px / 2.0
  }
  let most = (@hostapi.atlas_plot - 2).to_double()
  while ((r - l) * px).ceil() > most || ((f - t) * px).ceil() > most {
    px = px / 2.0
  }
  let w = ((r - l) * px).ceil().to_int()
  let h = ((f - t) * px).ceil().to_int()
  if w <= 0 || h <= 0 {
    return None
  }
  let cover = FixedArray::make(w * h, 0.0)
  let o = text_cache.gbuf
  for gl in glyphs {
    let (i, key) = gl
    let b = i * inst_size
    // (the glyph's picture as the host draws it: as many pixels as its cell)
    let (cw, ch) = (a[b + 14].round().to_int(), a[b + 15].round().to_int())
    if cw <= 0 || ch <= 0 {
      continue
    }
    h_glyph(key, o)
    let pic = FixedArray::make(cw * ch * 4, b'\x00')
    if !h_glyph_picture(key, pic) {
      halos.none = true
      return None
    }
    // (each of its pixels added where it is drawn, by how much of a pixel here it is)
    let (gx, gy, gw, gh) = (a[b], a[b + 1], a[b + 2], a[b + 3])
    let (sx, sy) = (gw / cw.to_double(), gh / ch.to_double())
    let share = sx * px * (sy * px) / 255.0
    for y in 0..<ch {
      let my = ((gy + (y.to_double() + 0.5) * sy - t) * px).to_int()
      if my < 0 || my >= h {
        continue
      }
      for x in 0..<cw {
        let v = pic[(y * cw + x) * 4 + 3].to_int()
        if v == 0 {
          continue
        }
        let mx = ((gx + (x.to_double() + 0.5) * sx - l) * px).to_int()
        if mx >= 0 && mx < w {
          cover[my * w + mx] = cover[my * w + mx] + v.to_double() * share
        }
      }
    }
  }
  for i in 0..<(w * h) {
    cover[i] = dmin(cover[i], 1.0)
  }
  halo_blur(cover, w, h, blur * px)
  halos.blurred += 1
  // (brought up so that where it is densest it covers wholly: words' strokes are thin, and blurred as they are (CSS's
  // text-shadow) they come to a fifth of a cover or less, too faint to read them on)
  let mut most = 0.0
  for i in 0..<(w * h) {
    most = dmax(most, cover[i])
  }
  let up = if most > 0.0 { 1.0 / most } else { 0.0 }
  let bytes = FixedArray::make(w * h, b'\x00')
  for i in 0..<(w * h) {
    bytes[i] = (dclamp(cover[i] * up, 0.0, 1.0) * 255.0).round().to_int().to_byte()
  }
  Some({ said, w, h, cover: bytes, dx: l - x0, dy: t - y0, pw: w.to_double() / px, ph: h.to_double() / px })
}

///|
/// `v` (`w` by `h`) blurred by a Gaussian of sigma `s` pixels, near enough: three boxes across, then three down, each as
/// wide as makes their three a Gaussian of that sigma (Kovesi's widths); nothing past its edges.
fn halo_blur(v : FixedArray[Double], w : Int, h : Int, s : Double) -> Unit {
  if s <= 0.0 {
    return
  }
  let n = 3.0
  let ideal = (12.0 * s * s / n + 1.0).sqrt()
  let mut wl = ideal.floor().to_int()
  if wl % 2 == 0 {
    wl -= 1
  }
  let wu = wl + 2
  let wld = wl.to_double()
  let mi = ((12.0 * s * s - n * wld * wld - 4.0 * n * wld - 3.0 * n) / (-4.0 * wld - 4.0)).round().to_int()
  let tmp = FixedArray::make(if w > h { w } else { h }, 0.0)
  for k in 0..<3 {
    let rad = ((if k < mi { wl } else { wu }) - 1) / 2
    if rad <= 0 {
      continue
    }
    for y in 0..<h {
      box_line(v, y * w, 1, w, rad, tmp)
    }
    for x in 0..<w {
      box_line(v, x, w, h, rad, tmp)
    }
  }
}

///|
/// The `n` values of `v` from `from`, `step` apart, each the mean of those within `rad` of it (nothing past its ends):
/// a running sum, as long whatever `rad` is.
fn box_line(v : FixedArray[Double], from : Int, step : Int, n : Int, rad : Int, tmp : FixedArray[Double]) -> Unit {
  for i in 0..<n {
    tmp[i] = v[from + i * step]
  }
  let k = 1.0 / (2 * rad + 1).to_double()
  let mut sum = 0.0
  for i in 0..<(if rad < n { rad } else { n }) {
    sum += tmp[i]
  }
  for i in 0..<n {
    if i + rad < n {
      sum += tmp[i + rad]
    }
    if i - rad - 1 >= 0 {
      sum -= tmp[i - rad - 1]
    }
    v[from + i * step] = sum * k
  }
}

///|
/// Halo `key` (`p`) in the words' atlas at `sc` pixels a point: where it is, drawn from in this frame, put there as it
/// is not (its pixels a glyph's of one colour: its three as its alpha). None where it is not put: no room while this
/// frame is drawn (none_short, as a glyph's), or a host that takes none (halos' `none`).
fn halo_cell(key : Int, p : HaloPicture, sc : Double) -> Glyph? {
  match text_cache.glyphs.get(key) {
    Some(g) if g.plot >= 0 && !glyph_other_scale(g, sc) => {
      atlas_of(false).drawn(g.plot)
      glyph_kept(key, g)
      return Some(g)
    }
    _ => ()
  }
  text_cache.glyphs.remove(key)
  let (atlas, _) = atlas_for(false)
  if !atlas.holds(p.w, p.h) {
    return None
  }
  match
    atlas.place(key, p.w, p.h, fn(k) {
      text_cache.glyphs.remove(k)
      glyphs_lost.val = true
    }) {
    Some((plot, x, y)) => {
      let rgba = FixedArray::make(p.w * p.h * 4, b'\x00')
      for i in 0..<(p.w * p.h) {
        let c = p.cover[i]
        rgba[i * 4] = c
        rgba[i * 4 + 1] = c
        rgba[i * 4 + 2] = c
        rgba[i * 4 + 3] = c
      }
      if !h_atlas_put(x, y, p.w, p.h, rgba) {
        halos.none = true
        return None
      }
      halos.put += 1
      let g = {
        u: x.to_double(),
        v: y.to_double(),
        gw: p.pw,
        gh: p.ph,
        ox: p.dx,
        oy: p.dy,
        color: false,
        plot,
        in_colour: false,
        sc,
      }
      text_cache.glyphs[key] = g
      glyph_kept(key, g)
      Some(g)
    }
    // (no room while this frame is drawn: what is made to be kept made again once there is, glyphs_still)
    None => {
      text_cache.short = true
      glyphs_lost.val = true
      glyph_kept(key, { ..no_glyph, u: -1.0, v: -1.0 })
      None
    }
  }
}

///|
/// How many halos were blurred, and put in the words' atlas, since the Tester started (View::words_halo): one drawn
/// again as it was is neither; one put again as the atlas let it go is not blurred again.
pub fn Tester::halos_made(self : Tester) -> (Int, Int) {
  ignore(self)
  (halos.blurred, halos.put)
}
