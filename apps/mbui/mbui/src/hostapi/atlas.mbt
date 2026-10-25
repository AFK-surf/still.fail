// Where glyphs go in a host's atlas (glyph, glyph_put): its square plots, each filled a shelf at a time, left to right
// and top to bottom. Full, the plot drawn from longest ago is emptied for what comes next and its glyphs said gone,
// never one the frame being drawn draws from: what is on the screen stays where it is, drawn once, however much comes
// and goes round it. (Each host started its atlas over whole as it filled: every glyph on the screen drawn again in one
// frame, and its words shaped again, a list scrolled through new words stopping a moment each time it did.)

///|
/// A plot's side, in pixels: the largest glyph a host draws (a word of a joining script, an emoji at a large size).
pub let atlas_plot : Int = 512

///|
priv struct Plot {
  x : Int
  y : Int
  // the shelf being filled: where it starts, how far along it is, the tallest glyph on it
  mut shelf_y : Int
  mut shelf_x : Int
  mut shelf_h : Int
  // the glyphs in it, and the last frame that drew from it (-1: none since it was emptied)
  keys : Array[Int]
  mut drawn : Int
}

///|
/// A host's atlas `side` pixels a side, as its glyphs are placed in it.
pub struct Atlas {
  // its plots' side, and the plots, a row at a time
  priv plot : Int
  priv plots : Array[Plot]
  // the plot being filled
  priv mut open : Int
  // the frame being drawn
  priv mut frame : Int
}

///|
/// An atlas `side` pixels a side, empty (0: none, nothing placed in it).
pub fn Atlas::new(side : Int) -> Atlas {
  let plot = if side < atlas_plot { side } else { atlas_plot }
  let n = if plot > 0 { side / plot } else { 0 }
  let plots = []
  for j in 0..<n {
    for i in 0..<n {
      plots.push({ x: i * plot, y: j * plot, shelf_y: 0, shelf_x: 0, shelf_h: 0, keys: [], drawn: -1 })
    }
  }
  { plot, plots, open: 0, frame: 0 }
}

///|
/// The next frame begins: what it draws from is kept through it.
pub fn Atlas::next_frame(self : Atlas) -> Unit {
  self.frame = self.frame + 1
}

///|
/// Plot `plot` (Atlas::place's) drawn from in this frame.
pub fn Atlas::drawn(self : Atlas, plot : Int) -> Unit {
  self.plots[plot].drawn = self.frame
}

///|
/// Whether it is an atlas at all (one of a side of 0 is none).
pub fn Atlas::sized(self : Atlas) -> Bool {
  !self.plots.is_empty()
}

///|
/// Whether a glyph `w` × `h` pixels has a place in it at all: something to draw, no larger than a plot.
pub fn Atlas::holds(self : Atlas, w : Int, h : Int) -> Bool {
  w > 0 && h > 0 && w <= self.plot && h <= self.plot && !self.plots.is_empty()
}

///|
/// A glyph `w` × `h` pixels (`key`) placed: its plot and where its top left is, drawn from in this frame; the glyphs of
/// a plot emptied for it said `gone` first. None when there is no room for it while this frame is drawn (every plot
/// drawn from in it), or none ever (Atlas::holds).
pub fn Atlas::place(self : Atlas, key : Int, w : Int, h : Int, gone : (Int) -> Unit) -> (Int, Int, Int)? {
  if !self.holds(w, h) {
    return None
  }
  if self.spot(self.open, w, h) is None {
    // another plot: one never filled, else the one drawn from longest ago
    let mut next = -1
    for i, p in self.plots {
      if i != self.open && (next < 0 || p.drawn < self.plots[next].drawn) {
        next = i
      }
    }
    if next < 0 {
      next = self.open
    }
    let p = self.plots[next]
    if p.drawn == self.frame {
      return None
    }
    for k in p.keys {
      gone(k)
    }
    p.keys.clear()
    p.shelf_y = 0
    p.shelf_x = 0
    p.shelf_h = 0
    self.open = next
  }
  guard self.spot(self.open, w, h) is Some((x, y)) else { return None }
  let p = self.plots[self.open]
  if y != p.shelf_y {
    p.shelf_y = y
    p.shelf_h = 0
  }
  p.shelf_x = x + w + 1
  p.shelf_h = if h > p.shelf_h { h } else { p.shelf_h }
  p.keys.push(key)
  p.drawn = self.frame
  Some((self.open, p.x + x, p.y + y))
}

///|
/// Everything placed let go (what the host drew is gone: atlas_generation).
pub fn Atlas::clear(self : Atlas) -> Unit {
  for p in self.plots {
    p.keys.clear()
    p.shelf_y = 0
    p.shelf_x = 0
    p.shelf_h = 0
    p.drawn = -1
  }
  self.open = 0
}

///|
/// Where in plot `i` a glyph `w` × `h` would go: on its shelf, else on a shelf of its own under it (a pixel apart);
/// None when it is full for it.
fn Atlas::spot(self : Atlas, i : Int, w : Int, h : Int) -> (Int, Int)? {
  let p = self.plots[i]
  let (x, y) = if p.shelf_x + w <= self.plot {
    (p.shelf_x, p.shelf_y)
  } else {
    (0, p.shelf_y + p.shelf_h + 1)
  }
  if y + h <= self.plot {
    Some((x, y))
  } else {
    None
  }
}
