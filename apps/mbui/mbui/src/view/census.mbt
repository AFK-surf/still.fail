// What values the window's tree's nodes are set to, by kind, for what counts them with the old frame's (ui's census.mbt:
// how many sizes of words, paddings, corners and colours a screen uses): as each is set, not as it is drawn.

///|
/// A live node's values as set (Tree::styled): its words' size, line and the weight and ink of each of them (a piece's
/// own where it is in pieces, View::words_runs; none where it says none); its padding (left, top, right, bottom) and the
/// gap between what it holds, in points (none where it has none); its corner; its ground (0: none).
pub(all) struct Styled {
  words : Bool
  size : Double
  line : Double
  weights : Array[Int]
  inks : Array[Int64]
  spaces : Array[Double]
  radius : Double
  ground : Int64
} derive(Debug)

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
      // (each piece that says something in its own weight and ink, the node's where it says none: WordsRun's; the
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
        let k = if r.ink == 0L { l.ink } else { r.ink }
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
