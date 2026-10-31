// What the hand changes of the window's tree's nodes, for what measures it (ui's hand_moves.mbt: a frame built with
// every target lit, at the same moment as the one before it with none): every node read as pointed at and pressed, and
// each node's place in what holds it, size and words, by its own identity (a node kept is the same node in the next
// frame; one made only lit is none of the frame before's).

///|
/// Every node read as pointed at and pressed (View::pointed, View::pressed: the cells that read them now, and any
/// first read while it is so), `on`; or, `on` false, each as the hand has it (Tree's `pointed`, `pressing`).
pub fn Tree::lit_all(self : Tree, on : Bool) -> Unit {
  self.lit_every = on
  for at in 0..<self.nodes.length() {
    let n = self.nodes[at]
    if !n.live {
      continue
    }
    let id = Some({ at, gen: n.gen })
    match n.pointed_cell {
      Some(s) => s.set(on || self.pointed == id)
      None => ()
    }
    match n.pressed_cell {
      Some(s) => s.set(on || self.pressing == id)
      None => ()
    }
  }
}

///|
/// What a node is laid out as, by the hand's measure: its identity (`key`, the same while it is kept) and its holder's,
/// its words (to name it), whether the hand lights it (it reads the pointer or the press, or takes presses), how far
/// down it is placed in what holds it (as placed: its layout's place and its offset, Tree::place), how big it is, and
/// its words' size and line, and the weight each of them is set in (`weights`: how many in a row at which, each piece's
/// own where it is in pieces, View::words_runs; none where it says none).
pub(all) struct HandNode {
  key : String
  holder : String
  said : String
  lights : Bool
  y : Double
  w : Double
  h : Double
  words : Bool
  size : Double
  weights : Array[(Int, Int)]
  line : Double
} derive(Debug)

///|
/// The live nodes as last placed, by the hand's measure (HandNode), what holds each before it.
pub fn Tree::hand_nodes(self : Tree) -> Array[HandNode] {
  let out : Array[HandNode] = []
  fn walk(at : Int, holder : String) -> Unit {
    let n = self.nodes[at]
    if !n.live {
      return
    }
    let key = "\{at}:\{n.gen}"
    let words = n.look.words != ""
    out.push({
      key,
      holder,
      said: n.look.words,
      lights: n.pointed_cell is Some(_) || n.pressed_cell is Some(_) || n.on_press is Some(_),
      y: n.ly,
      w: n.lw,
      h: n.lh,
      words,
      size: if words { n.look.words_look.size } else { 0.0 },
      weights: if words { hand_weights(n.look) } else { [] },
      line: if words { n.look.words_look.line } else { 0.0 },
    })
    for kid in n.kids {
      walk(kid, key)
    }
  }
  if self.nodes.length() > 0 {
    walk(0, "")
  }
  out
}

///|
/// The weight each of a node's words is set in, as how many in a row at which (one where its pieces next to each other
/// are set alike): a piece's own (View::words_runs), else the words' (WordsLook's).
fn hand_weights(look : Look) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let pieces = if look.runs.is_empty() { [words_run(look.words)] } else { look.runs }
  for r in pieces {
    let w = if r.weight == 0 { look.words_look.weight } else { r.weight }
    let k = r.text.length()
    if k == 0 {
      continue
    }
    match out.last() {
      Some((was, at)) if at == w => out[out.length() - 1] = (was + k, w)
      _ => out.push((k, w))
    }
  }
  out
}
