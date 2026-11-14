// What values the window's tree's nodes are set to, by kind, for what counts them with the old frame's (ui's census.mbt:
// how many sizes of words, paddings, corners and colours a screen uses): as each is set, not as it is drawn.

///|
/// A live node's values as set (Tree::styled): its words' size, line and the weight and ink of each of them (a piece's
/// own where it is in pieces, View::words_runs; none where it says none), and the size of words they are drawn at
/// (View::words_scale's); its padding (left, top, right, bottom) and the
/// gap between what it holds, in points (none where it has none); its corner; its ground (0: none); the colour of the
/// edge drawn round it (0: none, nor where it is drawn none wide).
#derive(Debug)
pub(all) struct Styled {
  words : Bool
  size : Double
  line : Double
  /// how far apart its letters are set besides their own (WordsLook's)
  tracking : Spacing
  words_scale : Double
  weights : Array[Int]
  inks : Array[Int64]
  spaces : Array[Double]
  radius : Double
  ground : Int64
  edge : Int64
}

///|
/// The live nodes the root holds, each one's values as set (Styled), what holds each before it.
pub fn Tree::styled(self : Tree) -> Array[Styled] {
  let out : Array[Styled] = []
  let pt = fn(d : @flex.Dim) {
    match d {
      Pt(v) => v
      _ => 0.0
    }
  }
  fn walk(at : Int) -> Unit {
    let n = self.nodes[at]
    if !n.live {
      return
    }
    let l = n.look
    let words = l.words != ""
    let weights : Array[Int] = []
    let inks : Array[Int64] = []
    if words {
      // (each piece that says something in its own weight and ink, the node's where it says none: @text.Run's; the
      // whole of it as the node sets it where it is in no pieces)
      let pieces = if l.runs.is_empty() { [words_run(l.words)] } else { l.runs }
      for r in pieces {
        if r.text == "" {
          continue
        }
        let w = if r.weight == 0 { l.words_look.weight } else { r.weight }
        if !weights.contains(w) {
          weights.push(w)
        }
        let k = if r.color == 0L { l.ink } else { r.color }
        if !inks.contains(k) {
          inks.push(k)
        }
      }
    }
    let st = n.flex.style
    out.push({
      words,
      size: if words { l.words_look.size } else { 0.0 },
      line: if words { l.words_look.line } else { 0.0 },
      tracking: l.words_look.tracking,
      words_scale: if words { self.words_scale_at(at) } else { 1.0 },
      weights,
      inks,
      spaces: if n.slot {
        []
      } else {
        [
          pt(st.get_padding_left()),
          pt(st.get_padding_top()),
          pt(st.get_padding_right()),
          pt(st.get_padding_bottom()),
          pt(st.get_gap_row()),
        ]
      },
      radius: l.radius,
      ground: l.ground,
      edge: if l.edge.0 > 0.0 { l.edge.1 } else { 0L },
    })
    for kid in n.kids {
      walk(kid)
    }
  }
  if self.nodes.length() > 0 {
    walk(0)
  }
  out
}
