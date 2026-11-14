// A mark on the first line (Tester::first_line_faults), measured on the frame just built as the corner, the spacing
// and the one height rules are (corners.mbt, gaps.mbt, heights.mbt): beside a block of several lines, an icon, a mark
// or a chevron sits on its first line, aligned with it, never centred on the block's height (the user, 2026-11-14:
// 「不应该一个图标或者一行内容跟多行做垂直居中对齐」, said before; a terminal's row, its icon between its two lines, 「这往哪对齐
// 的？」, which no check said). A mark: what a box holding no words draws (a drawing, a picture, a ground of its own),
// no larger than `first_line_mark_most` (an avatar, a tile, is no mark), not pressed on its own (a bar's tool by a
// title of two lines is a control; a row's icon and chevron are pressed with the row). Its block: what lies beside it
// in the box that holds both, its words on two lines or more (one set wrapped, or several one under another). Each
// fault a line naming the mark, how far its middle is off the first line's and the block.

///|
/// How large a mark is at most, either way, to be held to the rule (an icon's 16 or 20 in a button's room, a dot, a
/// chevron).
let first_line_mark_most : Double = 24.0

///|
/// How far a mark's middle may be off its block's first line's, at least (the layout's and the ink's rounding), and
/// as a share of that line's height.
let first_line_slack : Double = 2.0

///|
let first_line_share : Double = 0.25

///|
/// Where the last frame breaks the rule of the first line (see the file's head): one line for each mark beside a
/// block of several lines whose middle is off that block's first line's, the window's tree's nodes among the frame's
/// as drawn, their words laid out as drawn (Ctx::with_tree_nodes `facts`).
pub fn Tester::first_line_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  let c = g()
  c.with_tree_nodes(facts=true, fn() { c.first_line_faults() })
}

///|
/// Whether node `i` shows words of its own.
fn Ctx::first_line_words(self : Ctx, i : Int) -> Bool {
  let n = self.nodes[i]
  (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) &&
  (n.text != "" || n.rich is Some(_) || n.kind == kind_editor) &&
  n.opacity > 0.01
}

///|
/// Whether node `i` draws something besides words: a drawing, a picture, a ground of its own (the tree's as
/// Content::draws says, tree_draws_at).
fn Ctx::first_line_draws(self : Ctx, i : Int) -> Bool {
  let n = self.nodes[i]
  n.fw > 0.0 &&
  n.fh > 0.0 &&
  n.opacity > 0.01 &&
  (
    n.kind == kind_image ||
    n.shapes.length() > 0 ||
    n.lines.length() > 0 ||
    tree_draws_at.contains(i) ||
    (n.kind == kind_box && n.shows_ground())
  )
}

///|
fn Ctx::first_line_faults(self : Ctx) -> Array[String] {
  let out : Array[String] = []
  let n = self.count
  let (whole, layer) = self.shown_whole()
  // (what each holds, by what it says holds it: an old view's boxes held by the tree's node they are drawn in too)
  let kids : Array[Array[Int]] = Array::makei(n, fn(_) { [] })
  for i in 0..<n {
    let p = self.nodes[i].parent
    if p >= 0 && p < n {
      kids[p].push(i)
    }
  }
  // (whether each holds words shown, itself or in what it holds)
  let worded = Array::make(n, false)
  for i in 0..<n {
    if whole[i] && self.first_line_words(i) {
      let mut k = i
      while k >= 0 && k < n && !worded[k] {
        worded[k] = true
        k = self.nodes[k].parent
      }
    }
  }
  let aside = fn(i : Int) {
    let b = self.nodes[i]
    b.layer || b.portal || b.placed_at() || b.moved_off()
  }
  // (each of what `i` holds and itself, depth first)
  let under = fn(i : Int) -> Array[Int] {
    let all : Array[Int] = []
    let todo = [i]
    while todo.pop() is Some(k) {
      all.push(k)
      for ch in kids[k] {
        todo.push(ch)
      }
    }
    all
  }
  for p in 0..<n {
    if !worded[p] || !whole[p] || kids[p].length() < 2 {
      continue
    }
    // (the lines of words each block in it is drawn on: (top, foot, line's height), top first)
    let blocks : Array[(Int, Array[(Double, Double, Double)])] = []
    for b in kids[p] {
      if !worded[b] || !whole[b] || aside(b) || layer[b] != layer[p] {
        continue
      }
      let lines : Array[(Double, Double, Double)] = []
      for w in under(b) {
        if !whole[w] || !self.first_line_words(w) {
          continue
        }
        let t = self.nodes[w]
        let (count, lh) = match t.tl {
          Some(tl) if t.kind == kind_text && tl.line_h > 0.0 => (tl.line_start.length(), tl.line_h)
          _ => (1, t.fh)
        }
        if lh <= 0.0 {
          continue
        }
        let top = t.y + t.pad_t
        for li in 0..<count {
          let y = top + li.to_double() * lh
          // (one already there whose middle is within half a line of this one's: the same line)
          let same = lines.iter().any(fn(l) { (l.0 + l.1 - (y + y + lh)).abs() / 2.0 < dmin(l.2, lh) / 2.0 })
          if !same {
            lines.push((y, y + lh, lh))
          }
        }
      }
      if lines.length() >= 2 {
        lines.sort_by(fn(a, b) { a.0.compare(b.0) })
        blocks.push((b, lines))
      }
    }
    if blocks.is_empty() {
      continue
    }
    for a in kids[p] {
      if worded[a] || !whole[a] || aside(a) || layer[a] != layer[p] {
        continue
      }
      // (what it draws, as one: none larger than a mark)
      let mut x0 = 1.0e9
      let mut y0 = 1.0e9
      let mut x1 = -1.0e9
      let mut y1 = -1.0e9
      let mut mark = -1
      let mut big = false
      for k in under(a) {
        // (a control of its own, a bar's tool, is no mark of the block: a row's icon is pressed with the row)
        if self.nodes[k].hit && !self.nodes[k].points {
          big = true
          break
        }
        if !whole[k] || !self.first_line_draws(k) {
          continue
        }
        let d = self.nodes[k]
        if d.fw > first_line_mark_most + height_slack || d.fh > first_line_mark_most + height_slack {
          big = true
          break
        }
        x0 = dmin(x0, d.x)
        y0 = dmin(y0, d.y)
        x1 = dmax(x1, d.x + d.fw)
        y1 = dmax(y1, d.y + d.fh)
        if mark < 0 || d.fw * d.fh > self.nodes[mark].fw * self.nodes[mark].fh {
          mark = k
        }
      }
      if big || mark < 0 || y1 - y0 > first_line_mark_most + height_slack {
        continue
      }
      let mid = (y0 + y1) / 2.0
      for blk in blocks {
        let (b, lines) = blk
        let bn = self.nodes[b]
        // (beside it: not over or under it, and its middle among the block's lines)
        let apart = x1 <= bn.x + height_slack || x0 >= bn.x + bn.fw - height_slack
        let last = lines[lines.length() - 1]
        if !apart || mid < lines[0].0 || mid > last.1 {
          continue
        }
        let first = lines[0]
        let first_mid = (first.0 + first.1) / 2.0
        let off = mid - first_mid
        if off.abs() > dmax(first_line_slack, first.2 * first_line_share) {
          out.push(
            "first line: \{self.named(mark)} its middle \{(off * 10.0).round() / 10.0} off the first of the \{lines.length()} lines beside it (its \{first.2} high, at \{first.0.round()}), \{self.named(b)}, in \{self.named(p)}",
          )
          break
        }
      }
    }
  }
  out
}
