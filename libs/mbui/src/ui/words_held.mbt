// Words a box whose height is said in points does not hold: their line as drawn (at the system's size of words) higher
// than the box, or reaching out of it (a chip 16 high round words 20 high at 1.3, still.fail's fill chip before #5377).
// What is laid out by its words never comes to it (a least, min_h / View::min_height, lets them push it open); only a
// height said whatever it holds does: an old view's h=Px, a node's View::height (LaidFacts' `height_points`). Words
// out of the flow of what holds them on purpose are not judged (laid over it or placed apart, Ctx::squeeze_aside_at;
// pulled out of it by a margin below 0; drawn at another size than what holds them, Ctx::squeeze_scaled, or the box
// drawn at another size than it is laid out, a row lifted in the hand), nor what a
// box that scrolls or is a list holds (it holds more than shows by what it is). Run only as a check asks
// (Tester::fixed_outgrown), among the frame's nodes with the window tree's put there as the squeeze has them
// (Ctx::with_tree_nodes `facts`): nothing of it is kept on a node or done as a frame is. In Tester::audit, and in an
// app's sweeps of its screens. Known to fall short: an old view's box keeps no place of its own, so what is said of one
// names the node of the tree it is drawn in (Ctx::sizes_steady_made), not its line; what is drawn without a box of its
// own (a field's words, an icon's) is not judged.

///|
/// How far words may reach past the box that holds them before it is said: a line's rounding.
let fixed_outgrown_slack : Double = 0.5

///|
/// Each of the frame's words a box with its height said does not hold (the file's head): the words and the box with
/// where each was made, how high the words are as drawn and by how much they reach out of it.
pub fn Tester::fixed_outgrown(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  g().fixed_outgrown()
}

///|
fn Ctx::fixed_outgrown(self : Ctx) -> Array[String] {
  self.with_tree_nodes(facts=true, fn() {
    let out : Array[String] = []
    let from = tree_nodes_from.val
    for i in 0..<self.count {
      let w = self.nodes[i]
      if (w.kind != kind_text && w.kind != kind_rich) || !self.squeeze_shows_at(i) {
        continue
      }
      // (how high they are drawn: as they are set, or as high as they are laid out where none is kept)
      let words_h = match (w.tl, w.rl) {
        (Some(tl), _) => tl.h
        (_, Some(rl)) => rl.h
        _ => w.fh
      }
      let top = w.y
      let bottom = w.y + dmax(w.fh, words_h)
      // (the nearest of them and what holds them whose height is said, none where they lie apart from it on purpose)
      let mut k = i
      let mut held = -1
      while k >= 0 && k < self.count {
        let n = self.nodes[k]
        if self.squeeze_aside_at(k) || n.mar_t < 0.0 || n.mar_b < 0.0 || self.squeeze_scaled(k) {
          break
        }
        if k != i && (n.kind == kind_scroll || n.kind == kind_list || n.kind == kind_page || n.sideways) {
          break
        }
        let said = if from >= 0 && k >= from { tree_fixed_h_at.contains(k) } else { n.h is Px(_) }
        if said {
          held = k
          break
        }
        k = n.parent
      }
      // (drawn at another size than laid out, its words measured as laid out: on its way, a row lifted in the hand,
      // judged at rest)
      if held < 0 || self.outgrown_drawn_scaled(held) {
        continue
      }
      let b = self.nodes[held]
      let over = dmax(b.y - top, bottom - (b.y + b.fh))
      if over > fixed_outgrown_slack {
        // (where the box was made and its height said: a node's own, or the app's node an old view's is drawn in)
        let made = match (tree_frame_ids.get(held), view_tree()) {
          (Some(id), Some(tree)) => {
            let said = tree.looks_of(id).filter(fn(l) { l.has_prefix("box ") && l.contains("said at") })
            tree_source_said(id, paren=true) + (if said.is_empty() { "" } else { " [" + said.join("; ") + "]" })
          }
          _ => self.sizes_steady_made(held)
        }
        out.push(
          "\{self.named(i)} \{(words_h * 10.0).round() / 10.0} high, out of \{self.named(held)}\{made}, its height said, by \{(over * 10.0).round() / 10.0}",
        )
      }
    }
    out
  })
}

///|
/// Whether node `i` is drawn at another size than it is laid out (its scale and its holders', View::scale): the
/// nearest node of the window's tree out from it, as the tree draws it.
fn Ctx::outgrown_drawn_scaled(self : Ctx, i : Int) -> Bool {
  guard view_tree() is Some(tree) else { return false }
  let mut b = i
  while b >= 0 && b < self.count {
    match tree_frame_ids.get(b) {
      Some(id) => return (tree.drawn_scale(id) - 1.0).abs() > 1.0e-6
      None => b = self.nodes[b].parent
    }
  }
  false
}
