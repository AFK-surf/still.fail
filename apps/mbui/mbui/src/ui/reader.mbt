// Reading: a chapter (paragraphs, headings, pictures, rules) cut into pages
// of a given size, and a pager that turns them. Positions in a chapter are
// offsets into its blocks laid end to end: a paragraph or heading counts its
// UTF-16 length, a picture or a rule counts 1 (as the media service counts
// them, so a reading place or a note means the same everywhere).

///|
pub(all) enum Block {
  Para(String)
  Heading(String)
  /// a picture: its source (as for Ctx::image) and its size in pixels
  Picture(String, Double, Double)
  Rule
}

///|
pub(all) struct PageStyle {
  size : Double
  color : Int64
  /// extra space between lines, in points
  leading : Double
  /// space after a paragraph
  para_gap : Double
  /// first-line indent, in ems (2 for Chinese text, 0 for most English)
  indent : Double
  heading_size : Double
  /// margins around the text, inside the page
  margin_x : Double
  margin_y : Double
  /// the top margin when not margin_y (a bar over the page's top)
  margin_top : Double
  /// a line's height as a multiple of the size (0: the font's own and
  /// `leading`)
  line : Double
  heading_weight : Int
  rule_color : Int64
}

///|
pub fn PageStyle::default() -> PageStyle {
  {
    size: 18.0,
    color: 0x1D1D1FFFL,
    leading: 8.0,
    para_gap: 10.0,
    indent: 2.0,
    heading_size: 24.0,
    margin_x: 24.0,
    margin_y: 32.0,
    margin_top: -1.0,
    line: 0.0,
    heading_weight: 700,
    rule_color: 0xC7C7CCFFL,
  }
}

///|
priv enum PageItem {
  /// a line of block `b`'s text: its layout, the line, where it sits, and
  /// whether it is stretched to the full width
  Line(Int, TextLayout, Int, Double, Double, Bool)
  /// a picture: block, x, y, w, h
  Pic(Int, Double, Double, Double, Double)
  Hr(Double)
}

///|
pub struct Page {
  /// the offsets of the first position on the page and the one after its
  /// last
  start : Int
  end : Int
  priv items : Array[PageItem]
}

///|
pub struct Pages {
  width : Double
  height : Double
  style : PageStyle
  blocks : Array[Block]
  pages : Array[Page]
  /// the offset each block starts at, and the chapter's length
  priv base : Array[Int]
  length : Int
}

///|
fn block_len(b : Block) -> Int {
  match b {
    Para(s) | Heading(s) => s.length()
    Picture(_, _, _) | Rule => 1
  }
}

///|
fn has_cjk(s : Shaped, a : Int, b : Int) -> Bool {
  for c in a..<b {
    if s.cu[c] >= 0x2E80 {
      return true
    }
  }
  false
}

///|
/// Cuts `blocks` into pages of `width` × `height` points. Lines never split
/// across pages; a picture that doesn't fit what is left of a page starts
/// the next one, shrunk to fit a page if it must.
pub fn paginate(
  blocks : Array[Block],
  width : Double,
  height : Double,
  style? : PageStyle = PageStyle::default(),
) -> Pages {
  let st = style
  let inner_w = dmax(width - 2.0 * st.margin_x, 1.0)
  let top = if st.margin_top >= 0.0 { st.margin_top } else { st.margin_y }
  let bottom = height - st.margin_y
  let pages : Array[Page] = []
  let base = []
  let mut off = 0
  for b in blocks {
    base.push(off)
    off = off + block_len(b)
  }
  let mut items : Array[PageItem] = []
  let mut start = 0
  let mut y = top
  // the offset just past what is on the page so far
  let mut end = 0
  fn new_page(next : Int) {
    pages.push({ start, end, items })
    items = []
    start = next
    end = next
    y = top
  }

  for bi, b in blocks {
    match b {
      Para(text) | Heading(text) => {
        let heading = b is Heading(_)
        let size = if heading { st.heading_size } else { st.size }
        let indent = if heading { 0.0 } else { st.indent * st.size }
        let tl = layout_text(
          text,
          size,
          if heading { st.heading_weight } else { 400 },
          inner_w,
          true,
          indent~,
          line=if st.line > 0.0 { size * st.line } else { 0.0 },
        )
        let lh = if st.line > 0.0 { tl.line_h } else { tl.line_h + st.leading }
        let lines = tl.line_start.length()
        let s = tl.shaped
        // with lines set by the size, a heading has room above it (1.2em)
        // unless it starts the page, and 0.6em under it
        if heading && st.line > 0.0 && y > top + 0.01 {
          y = y + size * 1.2
        }
        for li in 0..<lines {
          if y + tl.line_h > bottom + 0.01 && items.length() > 0 {
            let (a, _) = tl.line_range(li)
            new_page(base[bi] + a)
          }
          let a = tl.line_start[li]
          let e = tl.line_end[li]
          // stretched to the margins unless it ends its paragraph or a
          // hard break
          let last = li == lines - 1 || (e > a && s.hard_end(e - 1))
          items.push(Line(bi, tl, li, 0.0, y, !last && !heading))
          let (_, b_end) = tl.line_range(li)
          end = base[bi] + b_end
          y = y + lh
        }
        if lines == 0 {
          end = base[bi]
        }
        y = y +
          (if heading && st.line > 0.0 {
            size * 0.6
          } else if heading {
            st.para_gap * 2.0
          } else {
            st.para_gap
          })
      }
      Picture(_, pw, ph) => {
        let mut w = dmin(inner_w, pw / g().scale)
        let mut h = if pw > 0.0 { w * ph / pw } else { 0.0 }
        let room = bottom - top
        if h > room {
          w = w * room / h
          h = room
        }
        if y + h > bottom + 0.01 && items.length() > 0 {
          new_page(base[bi])
        }
        items.push(Pic(bi, (inner_w - w) / 2.0, y, w, h))
        end = base[bi] + 1
        y = y + h + st.para_gap
      }
      Rule => {
        if y + 24.0 > bottom + 0.01 && items.length() > 0 {
          new_page(base[bi])
        }
        items.push(Hr(y + 12.0))
        end = base[bi] + 1
        y = y + 24.0 + st.para_gap
      }
    }
  }
  if items.length() > 0 || pages.length() == 0 {
    pages.push({ start, end: off, items })
  }
  { width, height, style: st, blocks, pages, base, length: off }
}

///|
/// The page showing `offset` (the last page for the chapter's end).
pub fn Pages::page_of(self : Pages, offset : Int) -> Int {
  let mut lo = 0
  let mut hi = self.pages.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if self.pages[mid].start <= offset {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
pub fn Pages::count(self : Pages) -> Int {
  self.pages.length()
}

///|
/// The text on page `i`, lines joined by newlines (for tests and search).
pub fn Pages::text_of(self : Pages, i : Int) -> String {
  let sb = StringBuilder()
  for it in self.pages[i].items {
    match it {
      Line(bi, tl, li, _, _, _) => {
        let (a, b) = tl.line_range(li)
        match self.blocks[bi] {
          Para(s) | Heading(s) => {
            if sb.to_string().length() > 0 {
              sb.write_char('\n')
            }
            sb.write_string(s.view(start_offset=a, end_offset=b).to_string())
          }
          _ => ()
        }
      }
      _ => ()
    }
  }
  sb.to_string()
}

///|
/// A node showing page `i` of `pages` (pages.width × pages.height).
pub fn Ctx::page(self : Ctx, pages : Pages, i : Int) -> Int {
  let k = self.alloc(kind_page)
  let n = self.nodes[k]
  n.w = Px(pages.width)
  n.h = Px(pages.height)
  n.pages = Some(pages)
  n.page_no = i
  k
}

///|
fn Ctx::paint_page(self : Ctx, n : Node, alpha : Double) -> Unit {
  let pages = match n.pages {
    Some(p) => p
    None => return
  }
  if n.page_no < 0 || n.page_no >= pages.pages.length() {
    return
  }
  let st = pages.style
  let ox = n.x + st.margin_x
  let oy = n.y
  let inner_w = pages.width - 2.0 * st.margin_x
  let sc = self.scale
  for it in pages.pages[n.page_no].items {
    match it {
      Line(_, tl, li, x0, y, stretch) => {
        let s = tl.shaped
        let a = tl.line_start[li]
        let mut e = tl.line_end[li]
        // trailing spaces and the line's break don't count
        while e > a && (s.cu[e - 1] == 32 || is_nl(s.cu[e - 1])) {
          e = e - 1
        }
        // stretching: between every two clusters for Chinese and Japanese,
        // at the spaces otherwise
        let cjk = has_cjk(s, a, e)
        let mut gaps = 0
        if stretch {
          for c in a..<(e - 1) {
            if cjk || s.cu[c] == 32 {
              gaps = gaps + 1
            }
          }
        }
        let extra = if stretch && gaps > 0 {
          (inner_w - tl.line_w[li]) / gaps.to_double()
        } else {
          0.0
        }
        let mut shift = 0.0
        for c in a..<e {
          let key = s.keys[c]
          if key >= 0 {
            let gl = glyph(key, sc)
            if gl.gw > 0.0 {
              let gx = on_pixels(ox + x0 + tl.xs[c] + shift + gl.ox, sc)
              let gy = on_glyph_row(oy + y + tl.ascent, gl.oy, sc)
              self.push_inst(
                gx,
                gy,
                gl.gw,
                gl.gh,
                0.0,
                if gl.color { 3.0 } else { 1.0 },
                0.0,
                0.0,
                if gl.color { 0xFFFFFFFFL } else { st.color },
                alpha,
                gl.u,
                gl.v,
                gl.gw * sc,
                gl.gh * sc,
              )
            }
          }
          if cjk || s.cu[c] == 32 {
            shift = shift + extra
          }
        }
      }
      Pic(bi, x, y, w, h) =>
        match pages.blocks[bi] {
          Picture(src, _, _) =>
            self.draw_image(src, ox + x, oy + y, w, h, FitFill, 0.0, alpha)
          _ => ()
        }
      Hr(y) =>
        self.emit_rect(
          ox + inner_w * 0.3,
          oy + y,
          inner_w * 0.4,
          1.0,
          0.0,
          st.rule_color,
          0.0,
          0L,
          alpha,
        )
    }
  }
}

// ---------------------------------------------------------------------------
// The pager: pages side by side, dragged sideways and let go onto the
// nearest, or turned with a tap on either side or the arrow keys.

///|
priv struct PagerState {
  mut index : Int
  mut count : Int
  /// how far the pages are dragged, or still sliding back to 0, in points
  /// (positive: the previous page shows): critically damped, at rest in
  /// about 200 ms, solved for the frame's time (motion_data.mbt)
  slide : SpringPath
  mut width : Double
  mut dragging : Bool
  /// a turn past the first (-1) or last (1) page, for the app to handle
  mut edge : Int
  /// the page the pager last returned to the app
  mut told : Int
}

///|
let pagers : Map[Int, PagerState] = {}

///|
/// Pages `0..<count` side by side, `page(i)` building page i; the one at
/// `index` (as the app last set it) shows. Returns the page now showing:
/// the app keeps it (and sets it to jump). `on_edge(±1)`: turned past the
/// first or last page (the app can open the next chapter); `on_middle`: a
/// tap in the middle third.
pub fn Ctx::pager(
  self : Ctx,
  key : String,
  count : Int,
  index : Int,
  page : (Int) -> Unit,
  w? : Size = Fill(1.0),
  h? : Size = Fill(1.0),
  on_edge? : (Int) -> Unit = fn(_) {  },
  on_middle? : () -> Unit = fn() {  },
) -> Int {
  let id = self.id(key)
  let st = match pagers.get(id) {
    Some(s) => s
    None => {
      let s = {
        index,
        count,
        slide: SpringPath::new(0.0, k=400.0, c=40.0, rest=0.3),
        width: 0.0,
        dragging: false,
        edge: 0,
        told: index,
      }
      pagers[id] = s
      self.own(id)
      s
    }
  }
  st.count = count
  // the app moves to another page (or another chapter) by passing one
  // other than the pager last told it
  if index != st.told && !st.dragging {
    st.index = index
    st.slide.put(0.0)
  }
  // turned past the first or last page since the last frame
  if st.edge != 0 {
    let e = st.edge
    st.edge = 0
    on_edge(e)
  }
  st.index = imax(0, imin(st.index, count - 1))
  let i = self.alloc(kind_box)
  let n = self.nodes[i]
  n.id = id
  self.id_built(i)
  n.hit = true
  n.w = w
  n.h = h
  n.clip = true
  n.dir = Row
  self.with_parent(i, fn() {
    for k in (st.index - 1)..=(st.index + 1) {
      if k >= 0 && k < count {
        let slot = self.alloc_part(kind_box, true, true, key=item_key(k))
        let sn = self.nodes[slot]
        sn.w = Fill(1.0)
        sn.h = Fill(1.0)
        sn.item = k
        sn.pager = id
        self.with_parent(slot, fn() { self.scope(k, fn() { page(k) }) })
      }
    }
  })
  // taps on either side turn the page
  if self.clicked.contains(id) && !st.dragging {
    let third = st.width / 3.0
    let x = self.press_x - n.x
    if x < third {
      self.turn(st, -1)
    } else if x > st.width - third {
      self.turn(st, 1)
    } else {
      on_middle()
    }
  }
  st.told = st.index
  st.index
}

///|
/// When pager `key`'s slide (a turn, a drag let go) is at rest, on the frames' clock (before now: it is): asked where
/// `key` would be (in the scope the pager is built in).
pub fn Ctx::pager_rest(self : Ctx, key : String) -> Double {
  match pagers.get(self.id(key)) {
    Some(st) => st.slide.end()
    None => -1.0
  }
}

///|
/// Turns `dir` pages (±1) with a slide, as far as there are pages.
fn Ctx::turn(self : Ctx, st : PagerState, dir : Int) -> Unit {
  let next = st.index + dir
  if next < 0 || next >= st.count {
    st.edge = dir
    self.read_changed("a pager at its end")
    return
  }
  st.index = next
  // the page that showed is now one width away, and slides in from there
  let (x, v) = st.slide.at(self.clock)
  st.slide.put(x + dir.to_double() * st.width)
  st.slide.go(self.clock, 0.0, v~)
}

///|
/// Pager pages sit side by side: each one where its index puts it, moved by
/// the drag.
fn Ctx::place_pager_slot(self : Ctx, i : Int) -> Unit {
  let n = self.nodes[i]
  match pagers.get(n.pager) {
    Some(st) => {
      let p = self.nodes[n.parent]
      st.width = p.fw
      n.tx = (n.item - st.index).to_double() * p.fw + st.slide.value(self.now_before(st.slide.end()))
    }
    None => ()
  }
}

///|
/// A horizontal drag on a pager (by dx since the last move); false if the
/// point isn't on one.
fn Ctx::pager_drag(self : Ctx, id : Int, dx : Double) -> Bool {
  match pagers.get(id) {
    Some(st) => {
      st.dragging = true
      // resisting past the first and last page
      let offset = st.slide.value(self.now_before(st.slide.end()))
      let at_end = (st.index == 0 && offset + dx > 0.0) ||
        (st.index == st.count - 1 && offset + dx < 0.0)
      st.slide.put(offset + (if at_end { dx * 0.35 } else { dx }))
      true
    }
    None => false
  }
}

///|
/// Let go after a drag: onto the next or previous page if dragged a third
/// of the way or flicked, else back.
fn Ctx::pager_release(self : Ctx, id : Int, vel : Double) -> Unit {
  match pagers.get(id) {
    Some(st) => {
      st.dragging = false
      let w = dmax(st.width, 1.0)
      let offset = st.slide.value(self.now_before(st.slide.end()))
      // past the last or first page, turn() hands it to the app
      if offset < -w / 3.0 || vel < -0.4 {
        self.turn(st, 1)
      } else if offset > w / 3.0 || vel > 0.4 {
        self.turn(st, -1)
      }
      // (vel a millisecond)
      st.slide.go(self.clock, 0.0, v=vel * 1000.0)
    }
    None => ()
  }
}

///|
fn Ctx::pager_key(self : Ctx, id : Int, code : Int) -> Bool {
  match pagers.get(id) {
    Some(st) =>
      if code == key_right || code == key_page_down || code == key_down {
        self.turn(st, 1)
        true
      } else if code == key_left || code == key_page_up || code == key_up {
        self.turn(st, -1)
        true
      } else {
        false
      }
    None => false
  }
}
