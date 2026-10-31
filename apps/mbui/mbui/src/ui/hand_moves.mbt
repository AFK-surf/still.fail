// What the hand changes, measured as the corner rule is (corners.mbt): the hand on a thing (a mouse's pointer resting
// on it, a finger pressing it) changes how it looks, its ground and its ink, and never how big words are, nor how tall
// anything it lights is or how far down it stands (still.fail's docs/ui-panels.md 悬停: 「形状就是它能按的范围，字的位置
// 不动」). A page writing its hot words as a style of their own can say more than their ink in it: a popover's foot,
// 全部 1 个 · 在侧栏查看, Meta at rest and Ui under the pointer, grew under it (the user, 2026-10-26: 「这玩意儿 hover
// 会变大」); a row's 忽略, shown only under the pointer, a point taller than the row's line, made the row taller
// (「hover 让高度变化了」). So a test builds one frame with every id lit at once and all that shows only under the hand
// shown (Ctx::lit_every, lit_all), at the same moment as the frame before it with none (Tester::hand_moves), and finds
// what is otherwise (Ctx::hand_faults). Across, a row may make room for what shows in it under the hand, as the web's
// rows do. What goes by an animation the hand starts (motion's while_hover) is where it starts in both.

///|
/// How far a place measured may differ and be the same: the layout's rounding.
let hand_slack : Double = 0.5

///|
/// What a frame laid node `i` out as, each node found again in another frame by its key (Ctx::hand_keys): how far down
/// it stands in what holds it, how big it is, and its words' size, weight and line.
priv struct HandMark {
  y : Double
  w : Double
  h : Double
  size : Double
  weight : Int
  line : Double
}

///|
/// Each node of the frame just built named so that the same node is found in another frame of the same screen, what
/// shows in one and not the other (a row's ⋯, a tip) leaving the rest found: one with an id by it, and which of the
/// nodes with that id it is; words by what holds them and what they say; any other box by what holds it and its place
/// among the boxes it holds with neither, and how many those are (more of them in one frame than in the other, none
/// of them, nor what is in them, found again). Nodes are built in order, what holds one before it.
fn Ctx::hand_keys(self : Ctx) -> Array[String] {
  let keys : Array[String] = Array::make(self.count, "")
  // the boxes each holds with neither an id nor words, in order, and how many
  let place : Array[Int] = Array::make(self.count, 0)
  let boxes : Map[Int, Int] = Map([])
  for i in 0..<self.count {
    let n = self.nodes[i]
    if n.id == 0 && !self.hand_words(i) {
      let k = boxes.get(n.parent).unwrap_or(0)
      place[i] = k
      boxes[n.parent] = k + 1
    }
  }
  let seen : Map[String, Int] = Map([])
  for i in 0..<self.count {
    let n = self.nodes[i]
    let base = if n.id != 0 {
      "#\{n.id}"
    } else {
      let p = n.parent
      let under = if p >= 0 && p < i { keys[p] } else { "" }
      if self.hand_words(i) {
        "\{under}/「\{n.text}」"
      } else {
        "\{under}/\{place[i]} of \{boxes.get(p).unwrap_or(0)}"
      }
    }
    let k = seen.get(base).unwrap_or(0)
    seen[base] = k + 1
    keys[i] = "\{base}#\{k}"
  }
  keys
}

///|
/// Whether node `i` says words (their size, weight and line the hand never changes, wherever they are).
fn Ctx::hand_words(self : Ctx, i : Int) -> Bool {
  let k = self.nodes[i].kind
  k == kind_text || k == kind_rich
}

///|
/// The frame just built, laid out: every node's mark (HandMark) by its key.
fn Ctx::hand_marks(self : Ctx) -> Map[String, HandMark] {
  let keys = self.hand_keys()
  let marks : Map[String, HandMark] = Map([])
  for i in 0..<self.count {
    marks[keys[i]] = self.hand_mark(i)
  }
  marks
}

///|
fn Ctx::hand_mark(self : Ctx, i : Int) -> HandMark {
  let n = self.nodes[i]
  let top = if n.parent >= 0 && n.parent < self.count { self.nodes[n.parent].y } else { 0.0 }
  let words = self.hand_words(i)
  {
    y: n.y - top,
    w: n.fw,
    h: n.fh,
    size: if words { n.font_size } else { 0.0 },
    weight: if words { n.weight } else { 0 },
    line: if words { n.line_h } else { 0.0 },
  }
}

///|
fn hand_near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= hand_slack
}

///|
/// Where the frame just built, every id lit and all that shows only under the hand shown (Ctx::lit_every, lit_all),
/// stands otherwise than `rest`, the frame before it with none: one line for each thing the hand lights (one with an
/// id) taller or shorter, and for words drawn otherwise, with nothing in it that is (what grew it, not each box it
/// grew); and for each thing it lights moved up or down in what holds it, nothing before it there grown (what moved
/// it), once for what holds it. Across, a row may make room in it for what shows under the hand (a chat's row its
/// station's mark moved over and its last line cut shorter for its 归档 key and its time, as the web's `paddingRight:
/// 24` on hover); and what it lights draws in its own room as it will (a handle's grip grown).
fn Ctx::hand_faults(self : Ctx, rest : Map[String, HandMark]) -> Array[String] {
  let keys = self.hand_keys()
  let grew : Array[Bool] = Array::make(self.count, false)
  let moved : Array[Bool] = Array::make(self.count, false)
  // a thing before it in what holds them grown: what moved it
  let pushed : Array[Bool] = Array::make(self.count, false)
  let was : Array[HandMark?] = Array::make(self.count, None)
  let grew_in : Set[Int] = Set([])
  for i in 0..<self.count {
    let n = self.nodes[i]
    if grew_in.contains(n.parent) {
      pushed[i] = true
    }
    match rest.get(keys[i]) {
      Some(m) => {
        let now = self.hand_mark(i)
        was[i] = Some(m)
        let lights = n.id != 0
        grew[i] = (lights && !hand_near(m.h, now.h)) ||
          (self.hand_words(i) &&
          (!hand_near(m.size, now.size) || m.weight != now.weight || !hand_near(m.line, now.line)))
        moved[i] = lights && !hand_near(m.y, now.y)
        if grew[i] {
          grew_in.add(n.parent)
        }
      }
      // (shown only lit: what it pushes is the fault, and is told)
      None => ()
    }
  }
  // what holds a node that grew grew by it
  let holds_grown : Array[Bool] = Array::make(self.count, false)
  for i in 0..<self.count {
    if grew[i] {
      let mut p = self.nodes[i].parent
      while p >= 0 && p < self.count && !holds_grown[p] {
        holds_grown[p] = true
        p = self.nodes[p].parent
      }
    }
  }
  let out : Array[String] = []
  for i in 0..<self.count {
    if grew[i] && !holds_grown[i] {
      let n = self.nodes[i]
      let m = was[i].unwrap()
      let words = if self.hand_words(i) {
        ", its words \{m.size} at weight \{m.weight} on a line of \{m.line} at rest, \{n.font_size} at \{n.weight} on \{n.line_h} lit"
      } else {
        ""
      }
      out.push("\{self.named(i)} is \{m.w.round()}×\{m.h.round()} at rest, \{n.fw.round()}×\{n.fh.round()} lit\{words}")
    }
  }
  let told : Set[Int] = Set([])
  for i in 0..<self.count {
    let p = self.nodes[i].parent
    if moved[i] && !pushed[i] && !(p >= 0 && p < self.count && (grew[p] || holds_grown[p])) && !told.contains(p) {
      told.add(p)
      let m = was[i].unwrap()
      let n = self.hand_mark(i)
      let holder = if p >= 0 { self.named(p) } else { "the window" }
      out.push("\{self.named(i)} moves in \{holder} lit, from \{m.y.round()} down in it to \{n.y.round()}")
    }
  }
  out
}

///|
/// The frame built again at the moment of the last, every id lit and all that shows only under the hand shown
/// (Ctx::lit_every, lit_all), nothing the host was asked meanwhile answered (decodes, views: Tester::frame_at's), so
/// what differs from the last is the hand alone: where it stands otherwise (Ctx::hand_faults). The frame after it is
/// built as before; the last must have been built with nothing lit (none pointed at, none pressed).
pub fn Tester::hand_moves(self : Tester) -> Array[String] {
  let c = g()
  let rest = c.hand_marks()
  // (the window's tree's nodes too: each that reads the pointer told it is over it, View::pointed)
  let tree_rest = match view_app.val {
    Some(tree) => tree.hand_nodes()
    None => []
  }
  match view_app.val {
    Some(tree) => tree.lit_all(true)
    None => ()
  }
  c.lit_every = true
  c.lit_all = true
  // (how it is drawn changed by the test: built whole, as the frame after it is, frame_watch.mbt)
  test_stepped()
  self.fake.wants = false
  on_frame(self.w, self.h, self.fake.scale, self.fake.time)
  self.frames = self.frames + 1
  let faults = c.hand_faults(rest)
  match view_app.val {
    Some(tree) => {
      faults.append(tree_hand_faults(tree_rest, tree.hand_nodes()))
      tree.lit_all(false)
    }
    None => ()
  }
  c.lit_every = false
  c.lit_all = false
  test_stepped()
  frame_ended_outside()
  faults
}

///|
/// Where the window's tree's nodes, every one that reads the pointer told it is over it (Tree::lit_all), stand
/// otherwise than `rest`, as they were with none (Tree::hand_nodes): as Ctx::hand_faults has it of the old frame's
/// nodes, one line for each that the hand lights grown or shrunk, or for words set otherwise, with nothing in it that is;
/// and for each it lights moved up or down in what holds it, nothing before it there grown, once for what holds it.
fn tree_hand_faults(rest : Array[@view.HandNode], now : Array[@view.HandNode]) -> Array[String] {
  let was : Map[String, @view.HandNode] = Map([])
  for r in rest {
    was[r.key] = r
  }
  let grew : Map[String, Bool] = Map([])
  for n in now {
    match was.get(n.key) {
      Some(m) =>
        if (n.lights && !hand_near(m.h, n.h)) ||
          (n.words && (!hand_near(m.size, n.size) || !weights_alike(m, n) || !hand_near(m.line, n.line))) {
          grew[n.key] = true
        }
      None => ()
    }
  }
  // (what holds one grown grew by it: told once, of the one that grew)
  let holder_of : Map[String, String] = Map([])
  for n in now {
    holder_of[n.key] = n.holder
  }
  let holds_grown : Set[String] = Set([])
  for n in now {
    if grew.contains(n.key) {
      let mut h = n.holder
      while h != "" && !holds_grown.contains(h) {
        holds_grown.add(h)
        h = holder_of.get(h).unwrap_or("")
      }
    }
  }
  let out : Array[String] = []
  for n in now {
    if grew.contains(n.key) && !holds_grown.contains(n.key) {
      let m = was[n.key]
      let words = if n.words {
        ", its words \{m.size} at weights \{m.weights} on a line of \{m.line} at rest, \{n.size} at \{n.weights} on \{n.line} lit"
      } else {
        ""
      }
      out.push("the tree's node \{n.key}\{tree_said(n)} is \{m.w.round()}×\{m.h.round()} at rest, \{n.w.round()}×\{n.h.round()} lit\{words}")
    }
  }
  // moved in what holds it, nothing before it there grown
  let grown_before : Set[String] = Set([])
  let told : Set[String] = Set([])
  for n in now {
    match was.get(n.key) {
      Some(m) =>
        if n.lights &&
          !hand_near(m.y, n.y) &&
          !grown_before.contains(n.holder) &&
          !grew.contains(n.holder) &&
          !holds_grown.contains(n.holder) &&
          !told.contains(n.holder) {
          told.add(n.holder)
          out.push("the tree's node \{n.key}\{tree_said(n)} moves in \{n.holder} lit, from \{m.y.round()} down in it to \{n.y.round()}")
        }
      None => ()
    }
    if grew.contains(n.key) || holds_grown.contains(n.key) {
      grown_before.add(n.holder)
    }
  }
  out
}

///|
/// Whether a tree's node's words are set in the same weights lit as at rest: the same words each in the weight it was;
/// words said otherwise (what they say is the page's, as it is in the frame's nodes) the same weights among them.
fn weights_alike(m : @view.HandNode, n : @view.HandNode) -> Bool {
  if m.said == n.said {
    return m.weights == n.weights
  }
  let used = fn(ws : Array[(Int, Int)]) {
    let set : Array[Int] = []
    for w in ws {
      if !set.contains(w.1) {
        set.push(w.1)
      }
    }
    set.sort()
    set
  }
  used(m.weights) == used(n.weights)
}

///|
/// What a tree's node says, to name it in a fault (「…」), none where it says nothing.
fn tree_said(n : @view.HandNode) -> String {
  if n.said == "" {
    ""
  } else {
    " 「\{n.said}」"
  }
}
