// still.fail's corner rule, measured (its docs/ui-panels.md, "所有带圆角的东西"): what has a ground of its own (a
// button, a row, a field, a block) and lies in the corner of a rounded container stands as far from the two edges of
// that corner, and its corner is the container's less that distance (concentric); a circle or a capsule there is as
// far from both, and the container's corner that distance more than its own (the container's fault when not). A test asks the frame it drew
// (Tester::corner_faults); the gallery's components keep to it.

///|
/// Whether node `n` shows a ground of its own (a fill or an edge) and is drawn.
fn Node::grounded(self : Node) -> Bool {
  self.kind == kind_box &&
  self.opacity > 0.01 &&
  self.fw > 0.0 &&
  self.fh > 0.0 &&
  ((self.bg & 0xFFL) != 0L || (self.border_w > 0.0 && (self.border_c & 0xFFL) != 0L))
}

///|
/// The corner a node draws: its radius, at most half its shorter side.
fn Node::corner(self : Node) -> Double {
  dmin(self.radius, dmin(self.fw, self.fh) / 2.0)
}

///|
/// Where the last frame breaks the corner rule (see the file's head): one line for each grounded node in a rounded
/// container's corner that is not as far from both edges, or not concentric (within half a pixel).
pub fn Tester::corner_faults(self : Tester) -> Array[String] {
  ignore(self)
  let c = g()
  let out : Array[String] = []
  for i in 0..<c.count {
    let b = c.nodes[i]
    if !b.grounded() || b.layer {
      continue
    }
    // the nearest rounded container round it that shows (a ground, an edge, or what it cuts)
    let mut p = b.parent
    while p >= 0 {
      let a = c.nodes[p]
      if a.kind == kind_box && a.corner() >= 6.0 && (a.grounded() || a.clip) {
        break
      }
      p = a.parent
    }
    if p < 0 {
      continue
    }
    let a = c.nodes[p]
    let ra = a.corner()
    let rb = b.corner()
    let l = b.x - a.x
    let t = b.y - a.y
    let r = a.x + a.fw - (b.x + b.fw)
    let d = a.y + a.fh - (b.y + b.fh)
    for k, (dx, dy) in [(l, t), (r, t), (l, d), (r, d)] {
      if dx < -0.5 || dy < -0.5 || dx >= ra || dy >= ra {
        continue
      }
      // (flush in the corner of what cuts it is still a fault: a cut is a rectangle, the container's corner does not
      // round what lies in it; it is let be once the cut follows the corner, mbui#42)
      let even = (dx - dy).abs() <= 0.5
      // a whole circle or a capsule (its corner half its shorter side: an avatar, a switch's knob, a dot) is round by
      // what it is: it is the container whose corner follows it (ui-panels.md: 外圆角 = 距离 + 半高), the fault the
      // container's when it does not
      let round = rb >= dmin(b.fw, b.fh) / 2.0 - 0.5
      let concentric = (rb - (ra - dmax(dx, dy))).abs() <= 0.5
      if !(even && concentric) {
        let corner = ["top left", "top right", "bottom left", "bottom right"][k]
        out.push(
          if round && even {
            "\{c.named(p)} (corner \{ra}): wants corner \{dmax(dx, dy) + rb}, for \{c.named(i)} (round, corner \{rb}) in its \{corner}, \{dx} from both edges"
          } else {
            "\{c.named(i)} (corner \{rb}) in the \{corner} of \{c.named(p)} (corner \{ra}): \{dx} and \{dy} from its edges" +
            (if concentric || round { "" } else { ", wants corner \{ra - dmax(dx, dy)}" })
          },
        )
      }
    }
  }
  out
}

///|
/// Node `i` as a fault names it: the words built in it, else its nearest container's that has any (said so), where
/// it is and how large, and its number in the frame.
fn Ctx::named(self : Ctx, i : Int) -> String {
  let n = self.nodes[i]
  let place = "at \{n.x.round()},\{n.y.round()} \{n.fw.round()}×\{n.fh.round()}, node \{i}"
  match self.words_cut(i) {
    Some(w) => "「\{w}」 (\{place})"
    None => {
      let mut p = n.parent
      while p >= 0 {
        match self.words_cut(p) {
          Some(w) => return "a box in 「\{w}」 (\{place})"
          None => p = self.nodes[p].parent
        }
      }
      "a box (\{place})"
    }
  }
}

///|
/// The words built in node `i` (semantics.mbt's), cut to 24 characters; None when it has none.
fn Ctx::words_cut(self : Ctx, i : Int) -> String? {
  let w = self.words_in(i)
  if w == "" {
    return None
  }
  let sb = StringBuilder()
  let mut count = 0
  for ch in w {
    if count == 24 {
      sb.write_string("…")
      break
    }
    sb.write_char(ch)
    count += 1
  }
  Some(sb.to_string())
}
