// Type the card to share's game looks set in, made of squares rather than a face (share_games.mbt): a dot matrix of
// 5 by 7 (as a handheld's or an arcade's screen shows a number), the same squares stood up as blocks (a voxel game's
// words, each square a block seen from the front, its top and its right side lit apart), and a calculator's seven
// segments. Each drawn as one picture (@sf.vector), its squares or segments the paths of a few colours.

///|
/// The dot matrix's glyphs, 5 by 7, a row each from the top ("1" a dot): the figures and what a share or a sum is
/// written with. What is not here is left a gap.
// kept across runs: a table, never written
let dot_glyphs : Map[Char, Array[String]] = {
  '0': ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
  '1': ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
  '2': ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
  '3': ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
  '4': ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
  '5': ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
  '6': ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
  '7': ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
  '8': ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
  '9': ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
  '%': ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
  '$': ["00100", "01111", "10100", "01110", "00101", "11110", "00100"],
  ',': ["0", "0", "0", "0", "1", "1", "1"],
  '.': ["0", "0", "0", "0", "0", "0", "1"],
  ' ': ["00", "00", "00", "00", "00", "00", "00"],
}

///|
/// The squares of `words` in the dot matrix, a column apart: each (column, row) lit, and how many columns across.
fn dot_cells(words : String) -> (Array[(Int, Int)], Int) {
  let cells : Array[(Int, Int)] = []
  let mut at = 0
  let mut first = true
  for ch in words {
    guard dot_glyphs.get(ch) is Some(rows) else { continue }
    if !first {
      at = at + 1
    }
    first = false
    for r, row in rows {
      let mut k = 0
      for bit in row {
        if bit == '1' {
          cells.push((at + k, r))
        }
        k = k + 1
      }
    }
    at = at + rows[0].length()
  }
  (cells, at)
}

///|
/// A rectangle as a path's piece.
fn rect_d(x : Double, y : Double, w : Double, h : Double) -> String {
  "M \{x} \{y} H \{x + w} V \{y + h} H \{x} Z "
}

///|
/// A path's layer filled with `ink` (none drawn where `d` is empty).
fn fill_layer(d : StringBuilder, ink : Int64) -> @pixels.VectorPath {
  { d: d.to_string(), fill: ink, stroke: 0L, width: 0.0, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 }
}

///|
/// `words` in the dot matrix, each square `cell` across less a hairline `gap` between, in `ink`; `shade`, if not 0,
/// each square again under it a square down and right (an arcade's shadow). Its width.
fn dot_words(c : @ui.Ctx, words : String, cell : Double, gap : Double, ink : Int64, shade? : Int64 = 0L) -> Int {
  let (cells, cols) = dot_cells(words)
  let lift = if shade != 0L { gap + cell * 0.25 } else { 0.0 }
  let w = cols.to_double() * cell + lift
  let h = 7.0 * cell + lift
  let top = StringBuilder()
  let under = StringBuilder()
  for p in cells {
    let (x, y) = (p.0.to_double() * cell, p.1.to_double() * cell)
    top.write_string(rect_d(x, y, cell - gap, cell - gap))
    under.write_string(rect_d(x + lift, y + lift, cell - gap, cell - gap))
  }
  let layers = if shade != 0L { [fill_layer(under, shade), fill_layer(top, ink)] } else { [fill_layer(top, ink)] }
  @sf.vector(c, "dots/\{words}/\{cell}/\{gap}/\{ink}/\{shade}", { w, h, layers }, w)
}

///|
/// `words` as blocks (a voxel game's words): each square of the dot matrix a block `cell` across, `deep` its top and
/// side seen (to the upper right), the faces another lies against not drawn; drawn back to front by the faces' kinds
/// (sides and tops, then fronts: a front is nearer than the top or side of the block below or left of it). Its width.
fn block_words(c : @ui.Ctx, words : String, cell : Double, deep : Double, inks : @sf.BlockInks) -> Int {
  let (cells, cols) = dot_cells(words)
  blocks_of(c, "words/" + words, cells, cols, 7, cell, deep, inks)
}

///|
/// A row of `n` blocks, side by side (the ground under a voxel game's sky).
fn block_row(c : @ui.Ctx, n : Int, cell : Double, deep : Double, inks : @sf.BlockInks) -> Int {
  blocks_of(c, "row/\{n}", Array::makei(n, fn(k) { (k, 0) }), n, 1, cell, deep, inks)
}

///|
/// Blocks at `cells` (column, row) of a grid `cols` by `rows`, as block_words draws them.
fn blocks_of(
  c : @ui.Ctx,
  key : String,
  cells : Array[(Int, Int)],
  cols : Int,
  rows : Int,
  cell : Double,
  deep : Double,
  inks : @sf.BlockInks,
) -> Int {
  let lit : Map[(Int, Int), Bool] = {}
  for p in cells {
    lit[p] = true
  }
  let w = cols.to_double() * cell + deep
  let h = rows.to_double() * cell + deep
  let (sides, tops, fronts, bands, band_sides, specks, lines) = (
    StringBuilder(),
    StringBuilder(),
    StringBuilder(),
    StringBuilder(),
    StringBuilder(),
    StringBuilder(),
    StringBuilder(),
  )
  let band = cell * 0.3
  let speck = cell / 6.0
  for p in cells {
    let (col, row) = p
    let x = col.to_double() * cell
    let y = row.to_double() * cell + deep
    let open_top = !lit.contains((col, row - 1))
    let open_side = !lit.contains((col + 1, row))
    if open_side {
      let face = "M \{x + cell} \{y} L \{x + cell + deep} \{y - deep} L \{x + cell + deep} \{y + cell - deep} L \{x + cell} \{y + cell} Z "
      sides.write_string(face)
      lines.write_string(face)
      if open_top {
        band_sides.write_string(
          "M \{x + cell} \{y} L \{x + cell + deep} \{y - deep} L \{x + cell + deep} \{y - deep + band} L \{x + cell} \{y + band} Z ",
        )
      }
    }
    if open_top {
      let face = "M \{x} \{y} L \{x + deep} \{y - deep} L \{x + cell + deep} \{y - deep} L \{x + cell} \{y} Z "
      tops.write_string(face)
      lines.write_string(face)
    }
    fronts.write_string(rect_d(x, y, cell, cell))
    lines.write_string(rect_d(x, y, cell, cell))
    if open_top {
      bands.write_string(rect_d(x, y, cell, band))
    }
    // a texture's specks: where each falls by the block's place, the same block always the same
    let seed = col * 7 + row * 13
    for k in 0..<3 {
      let sx = ((seed + k * 5) % 5).to_double() * speck
      let sy = ((seed + k * 3) % 4).to_double() * speck + (if open_top { band } else { 0.0 })
      specks.write_string(rect_d(x + sx + speck * 0.5, y + sy + speck * 0.5, speck, speck))
    }
  }
  let layers = [
    fill_layer(sides, inks.side),
    fill_layer(band_sides, inks.band_side),
    fill_layer(tops, inks.top),
    fill_layer(fronts, inks.front),
    fill_layer(specks, inks.speck),
    fill_layer(bands, inks.band),
    { d: lines.to_string(), fill: 0L, stroke: inks.line, width: 1.0, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 },
  ]
  @sf.vector(c, "blocks/\{key}/\{cell}/\{deep}/\{inks.front}/\{inks.top}", { w, h, layers }, w)
}

///|
/// Which of the seven segments each figure lights: a (top), b (top right), c (foot right), d (foot), e (foot left), f
/// (top left), g (middle).
// kept across runs: a table, never written
let segments_of : Map[Char, String] = {
  '0': "abcdef",
  '1': "bc",
  '2': "abdeg",
  '3': "abcdg",
  '4': "bcfg",
  '5': "acdfg",
  '6': "acdefg",
  '7': "abc",
  '8': "abcdefg",
  '9': "abcdfg",
  '-': "g",
}

///|
/// The figures of `words` (what else is in it left out) in seven segments, each figure `h` tall, the segments lit in
/// `on` and those dark in `off` (a calculator's, an LED counter's), `count` figures at least (0s before them, as a
/// counter shows). Its width.
fn segment_figures(c : @ui.Ctx, words : String, h : Double, on : Int64, off : Int64, count? : Int = 0) -> Int {
  let figures : Array[Char] = []
  for ch in words {
    if segments_of.contains(ch) {
      figures.push(ch)
    }
  }
  while figures.length() < count {
    figures.insert(0, '0')
  }
  let fw = h * 0.55
  let t = h * 0.11
  let apart = h * 0.12
  let w = figures.length().to_double() * (fw + apart) - apart
  let lit = StringBuilder()
  let dark = StringBuilder()
  for i, ch in figures {
    let x0 = i.to_double() * (fw + apart)
    let lights = segments_of.get(ch).unwrap_or("")
    let mid = h / 2.0
    // each segment: a long hexagon between its two ends
    let across = fn(x1 : Double, x2 : Double, y : Double) {
      "M \{x1} \{y} L \{x1 + t / 2.0} \{y - t / 2.0} L \{x2 - t / 2.0} \{y - t / 2.0} L \{x2} \{y} L \{x2 - t / 2.0} \{y + t / 2.0} L \{x1 + t / 2.0} \{y + t / 2.0} Z "
    }
    let down = fn(x : Double, y1 : Double, y2 : Double) {
      "M \{x} \{y1} L \{x + t / 2.0} \{y1 + t / 2.0} L \{x + t / 2.0} \{y2 - t / 2.0} L \{x} \{y2} L \{x - t / 2.0} \{y2 - t / 2.0} L \{x - t / 2.0} \{y1 + t / 2.0} Z "
    }
    let (l, r) = (x0 + t / 2.0 + 1.0, x0 + fw - t / 2.0 - 1.0)
    let (top, foot) = (t / 2.0 + 1.0, h - t / 2.0 - 1.0)
    let pieces = [
      ('a', across(l + 1.0, r - 1.0, top)),
      ('b', down(r, top + 1.0, mid - 1.0)),
      ('c', down(r, mid + 1.0, foot - 1.0)),
      ('d', across(l + 1.0, r - 1.0, foot)),
      ('e', down(l, mid + 1.0, foot - 1.0)),
      ('f', down(l, top + 1.0, mid - 1.0)),
      ('g', across(l + 1.0, r - 1.0, mid)),
    ]
    for p in pieces {
      if lights.iter().any(fn(x) { x == p.0 }) {
        lit.write_string(p.1)
      } else {
        dark.write_string(p.1)
      }
    }
  }
  @sf.vector(c, "segments/\{words}/\{h}/\{on}/\{off}/\{count}", { w, h, layers: [fill_layer(dark, off), fill_layer(lit, on)] }, w)
}
