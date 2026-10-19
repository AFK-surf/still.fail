// Native views over the canvas: a system view the host keeps under the app's surface (a video player, a web page),
// shown through a hole the app paints where it is (an instance of kind 9: transparent, written without blending).
// What is painted after the hole draws over the view (a bar, a video's controls, frosted or not); what is painted
// around it, or a clip, hides the rest of it. The host places the view where its node was painted, every frame it
// moves, and hides it on the frames it is not painted (a page gone under another, scrolled away).
//
// A video's bytes come only through the app: the player asks for ranges (`view_read_next`), the view's `read`
// fetches them (still.fail: `station.file.part`, `drive.read` through the core) and answers.
//
// Hosts: Android (NativeViews.java: Media3's ExoPlayer on a TextureView, a WebView), macOS and iOS (apple_views.m:
// AVPlayerLayer, WKWebView), the browser (web/host.js: <video>, a sandboxed <iframe>); Windows has none (`here` is
// false: the app says it cannot show it).
//
// Also here: PDFs drawn by the host page by page into images (`Pdf`, shown with `Ctx::image(pdf.page_src(i))`), and
// an image drawn at a rect of its own within its box (`Ctx::picture`: zoomed, panned).

///|
/// A native view: a player or a page.
pub struct NativeView {
  priv id : Int
  priv read : ((Double, Int, (Bytes, Double) -> Unit) -> Unit)?
  priv info : FixedArray[Double]
  priv mut state : Int
  /// the frame it was last painted in, and where: content x y w h, clip x0 y0 x1 y1
  priv mut painted : Int
  priv at : FixedArray[Double]
  /// what the host was last told: the same 8 and shown
  priv told : FixedArray[Double]
  priv mut told_shown : Bool
  priv mut closed : Bool
}

///|
/// The views open, polled and placed each frame.
let open_views : Array[NativeView] = []

///|
let read_out : FixedArray[Double] = FixedArray::make(2, 0.0)

///|
fn NativeView::make(
  kind : Int,
  arg : String,
  read : ((Double, Int, (Bytes, Double) -> Unit) -> Unit)?,
) -> NativeView {
  let v = {
    id: h_view_open(kind, arg),
    read,
    info: FixedArray::make(8, 0.0),
    state: 0,
    painted: -1,
    at: FixedArray::make(8, 0.0),
    told: FixedArray::make(8, -1.0),
    told_shown: false,
    closed: false,
  }
  if v.id == 0 {
    v.state = -1
  } else {
    open_views.push(v)
  }
  v
}

///|
/// A player of the video (or audio) of MIME type `type_`, its bytes read through `read(offset, length, answer)`:
/// `answer(bytes, total)` with the bytes from `offset` (at most `length`, fewer is fine, none only at the end) and the
/// file's whole size (-1 not known; -2: it could not be read). Paused until `play`.
pub fn NativeView::video(
  type_ : String,
  read : (Double, Int, (Bytes, Double) -> Unit) -> Unit,
) -> NativeView {
  NativeView::make(1, type_, Some(read))
}

///|
/// A page of `html` (its scripts on, nothing of the device's files or the app's reachable, its links not followed).
pub fn NativeView::page(html : String) -> NativeView {
  NativeView::make(2, html, None)
}

///|
/// Whether this host has such a view (Windows has none).
pub fn NativeView::here(self : NativeView) -> Bool {
  self.id != 0
}

///|
/// Gone: its player stopped, its page closed. It shows no more.
pub fn NativeView::close(self : NativeView) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  if self.id != 0 {
    h_view_close(self.id)
    open_views.retain(fn(v) { !physical_equal(v, self) })
  }
}

///|
pub fn NativeView::play(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 1, 0.0)
  }
}

///|
pub fn NativeView::pause(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 2, 0.0)
  }
}

///|
/// To `ms` into it, exactly (the frame there).
pub fn NativeView::seek(self : NativeView, ms : Double) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 3, ms)
    self.info[1] = ms
  }
}

///|
/// Played at `rate` times its speed.
pub fn NativeView::rate(self : NativeView, rate : Double) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 4, rate)
  }
}

///|
/// -1 failed (cannot be played, or loaded; or no such view here), 0 opening, 1 ready.
pub fn NativeView::state(self : NativeView) -> Int {
  self.state
}

///|
/// Its length in ms (-1 not known yet).
pub fn NativeView::duration(self : NativeView) -> Double {
  self.info[0]
}

///|
/// Where it is, in ms.
pub fn NativeView::position(self : NativeView) -> Double {
  self.info[1]
}

///|
pub fn NativeView::playing(self : NativeView) -> Bool {
  self.info[2] > 0.0
}

///|
/// The picture's own size in pixels ((0, 0) until known).
pub fn NativeView::natural(self : NativeView) -> (Double, Double) {
  (self.info[3], self.info[4])
}

///|
/// The bytes it has been given.
pub fn NativeView::bytes(self : NativeView) -> Double {
  self.info[5]
}

///|
/// Whether a frame has been drawn (a page: it has loaded).
pub fn NativeView::shown(self : NativeView) -> Bool {
  self.info[6] > 0.0
}

///|
pub fn NativeView::buffering(self : NativeView) -> Bool {
  self.info[7] > 0.0
}

///|
/// Where `v` shows: a node of `w` × `h` (filling its parent by default), the view's content at `content` within it
/// (x, y, w, h from the node's top left; the whole node when None: a video's picture is stretched to it), seen only
/// inside the node and whatever clips it. What is painted after it draws over it.
pub fn Ctx::native(
  self : Ctx,
  v : NativeView,
  w? : Size = Fill(1.0),
  h? : Size = Fill(1.0),
  content? : (Double, Double, Double, Double)? = None,
) -> Int {
  let i = self.box(w~, h~, fn() {  })
  let n = self.nodes[i]
  n.kind = kind_native
  native_nodes[i] = (v, content)
  i
}

///|
/// The native views' nodes this frame, by their index in the pool.
let native_nodes : Map[Int, (NativeView, (Double, Double, Double, Double)?)] = Map([])

///|
fn Ctx::paint_native(self : Ctx, i : Int, n : Node) -> Unit {
  let (v, content) = match native_nodes.get(i) {
    Some(x) => x
    None => return
  }
  if v.closed || v.id == 0 {
    return
  }
  let (x, y, w, h) = match content {
    Some((cx, cy, cw, ch)) => (n.x + cx, n.y + cy, cw, ch)
    None => (n.x, n.y, n.fw, n.fh)
  }
  // seen within the node and the clip it is painted in
  let k = clip_stack.length() - 4
  let x0 = dmax(n.x, clip_stack[k])
  let y0 = dmax(n.y, clip_stack[k + 1])
  let x1 = dmin(n.x + n.fw, clip_stack[k + 2])
  let y1 = dmin(n.y + n.fh, clip_stack[k + 3])
  if x1 <= x0 || y1 <= y0 {
    return
  }
  // the hole: where the content is, within that, on whole device pixels (no edge row half covered)
  let sc = self.scale
  let snap = fn(v : Double) { (v * sc).round() / sc }
  let hx0 = snap(dmax(x, x0))
  let hy0 = snap(dmax(y, y0))
  let hx1 = snap(dmin(x + w, x1))
  let hy1 = snap(dmin(y + h, y1))
  if hx1 > hx0 && hy1 > hy0 {
    self.push_inst(
      hx0,
      hy0,
      hx1 - hx0,
      hy1 - hy0,
      0.0,
      9.0,
      0.0,
      0.0,
      0L,
      1.0,
      0.0,
      0.0,
      0.0,
      0.0,
    )
  }
  v.painted = self.frame_no
  v.at[0] = x
  v.at[1] = y
  v.at[2] = w
  v.at[3] = h
  v.at[4] = x0
  v.at[5] = y0
  v.at[6] = x1
  v.at[7] = y1
}

///|
/// After a frame is painted: each open view placed where it was painted (hidden where it was not), told how it
/// stands, and the reads its player waits on handed to its `read`.
fn Ctx::sync_views(self : Ctx) -> Unit {
  native_nodes.clear()
  picture_at.clear()
  if open_views.length() == 0 {
    return
  }
  for v in open_views.copy() {
    if v.closed {
      continue
    }
    let shown = v.painted == self.frame_no
    let mut moved = shown != v.told_shown
    if shown {
      for j in 0..<8 {
        if (v.at[j] - v.told[j]).abs() > 0.01 {
          moved = true
        }
      }
    }
    if moved {
      for j in 0..<8 {
        v.told[j] = v.at[j]
      }
      v.told_shown = shown
      h_view_place(
        v.id,
        v.at[0],
        v.at[1],
        v.at[2],
        v.at[3],
        v.at[4],
        v.at[5],
        v.at[6],
        v.at[7],
        shown,
      )
    }
    let before = v.state
    v.state = h_view_info(v.id, v.info)
    if v.state != before || v.playing() {
      // a player playing moves on its own: its time is shown
      self.wants_frame = true
    }
    match v.read {
      Some(read) =>
        for _ in 0..<64 {
          let req = h_view_read_next(v.id, read_out)
          if req <= 0 {
            break
          }
          let id = v.id
          read(read_out[0], read_out[1].to_int(), fn(data, total) {
            if !v.closed {
              h_view_read_answer(id, req, data, total)
            }
          })
        }
      None => ()
    }
  }
}

// ── PDFs ───────────────────────────────────────────────────────────────

///|
/// A PDF the host draws (host_native.mbt pdf_*).
pub struct Pdf {
  priv doc : Int
  /// how many pages (-1: it could not be opened, or this host draws none)
  pages : Int
  /// each page's size in points
  sizes : Array[(Double, Double)]
}

///|
let pdf_out : FixedArray[Double] = FixedArray::make(2, 0.0)

///|
/// The PDF in `data`, opened.
pub fn Pdf::open(data : Bytes) -> Pdf {
  let doc = h_pdf_open(data)
  let pages = if doc == 0 { -1 } else { h_pdf_pages(doc) }
  let sizes = []
  for p in 0..<pages {
    h_pdf_page_size(doc, p, pdf_out)
    sizes.push((pdf_out[0], pdf_out[1]))
  }
  { doc, pages, sizes }
}

///|
/// The source `Ctx::image` shows page `page` (from 0) by: drawn at the size it is shown at.
pub fn Pdf::page_src(self : Pdf, page : Int) -> String {
  "pdf:\{self.doc}/\{page}"
}

///|
/// Let go: its pages' images are dropped too.
pub fn Pdf::close(self : Pdf) -> Unit {
  if self.doc == 0 {
    return
  }
  let prefix = "pdf:\{self.doc}/"
  let gone = []
  for src, list in image_cache {
    if src.has_prefix(prefix) {
      for e in list {
        h_image_free(e.id)
      }
      gone.push(src)
    }
  }
  for src in gone {
    image_cache.remove(src)
  }
  h_pdf_close(self.doc)
}

///|
/// A page's image, `src` being "pdf:<doc>/<page>": its id, as an image's load gives.
fn pdf_page_load(src : String, max_px : Int) -> Int {
  let rest = src.unsafe_substring(start=4, end=src.length())
  let parts = rest.split("/").map(fn(s) { s.to_owned() }).to_array()
  if parts.length() != 2 {
    return 0
  }
  match (digits(parts[0]), digits(parts[1])) {
    (Some(doc), Some(page)) => h_pdf_page_load(doc, page, max_px)
    _ => 0
  }
}

///|
/// A whole number written in digits.
fn digits(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for ch in s {
    let d = ch.to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      return None
    }
    n = n * 10 + d
  }
  Some(n)
}

// ── a picture at a rect of its own ─────────────────────────────────────

///|
/// The rects pictures are drawn at this frame, by node.
let picture_at : Map[Int, (Double, Double, Double, Double, Int)] = Map([])

///|
/// The image from `src` drawn stretched to (x, y, w, h) from the top left of a node filling its parent (or `w_` ×
/// `h_`), which may be bigger than the node (zoomed in): only what is inside the clip it is painted in shows. Loaded at
/// the size it is drawn, at most `max_px` on its longer side.
pub fn Ctx::picture(
  self : Ctx,
  src : String,
  x~ : Double,
  y~ : Double,
  w~ : Double,
  h~ : Double,
  w_? : Size = Fill(1.0),
  h_? : Size = Fill(1.0),
  max_px? : Int = 4096,
) -> Int {
  let i = self.image(src, w=w_, h=h_, fit=FitFill, bg=0L, fade=false)
  picture_at[i] = (x, y, w, h, max_px)
  i
}

// ── a box that takes the pointer as its own ────────────────────────────

///|
/// Boxes that take the pointer as their own (`capture`): what is under them (a list) is not dragged or wheeled,
/// their own drags are not taken for a list's, and the wheel over them is theirs (`wheel`).
let captures : Map[Int, Bool] = Map([])

///|
let wheels : Map[Int, Double] = Map([])

///|
/// The box of `id` (given to it this frame) takes the pointer: a finger dragging on it keeps it pressed (`pressed`,
/// `pointer`: a pan), nothing under it scrolls, and the wheel over it is kept for `wheel`.
pub fn capture(c : Ctx, id : Int) -> Unit {
  ignore(c)
  captures[id] = true
}

///|
/// What the wheel moved over `id` since last asked (its dy, as a list would scroll by it).
pub fn wheel(c : Ctx, id : Int) -> Double {
  ignore(c)
  match wheels.get(id) {
    Some(d) => {
      wheels.remove(id)
      d
    }
    None => 0.0
  }
}

///|
/// How an image shown from `src` stands: 1 one of its decodes is ready, -1 it could not be decoded, 0 not yet.
pub fn image_state(src : String) -> Int {
  match image_cache.get(src) {
    Some(list) => {
      let mut failed = list.length() > 0
      for e in list {
        e.poll(g.now)
        if e.state == 1 {
          return 1
        }
        if e.state != -1 {
          failed = false
        }
      }
      if failed {
        -1
      } else {
        0
      }
    }
    None => 0
  }
}

///|
/// The size in pixels of the image shown from `src`, once a decode of it is ready.
pub fn image_natural(src : String) -> (Double, Double)? {
  image_size(src)
}

///|
/// A line on the host's log (a test's fake host keeps it).
pub fn log(s : String) -> Unit {
  h_log(s)
}

// ── a second finger ────────────────────────────────────────────────────

///|
/// The second finger on a touch screen: x, y, down (1) (hosts that have one send it as pointer kinds 4, 5, 6).
let second_ptr : FixedArray[Double] = FixedArray::make(3, 0.0)

///|
fn on_second(kind : Int, x : Double, y : Double) -> Unit {
  second_ptr[0] = x
  second_ptr[1] = y
  second_ptr[2] = if kind == 6 { 0.0 } else { 1.0 }
  h_request_frame()
}

///|
/// A second finger, while one is down beside the first (a pinch): where it is.
pub fn Ctx::second_pointer(self : Ctx) -> (Double, Double)? {
  if self.down && second_ptr[2] > 0.0 {
    Some((second_ptr[0], second_ptr[1]))
  } else {
    None
  }
}
