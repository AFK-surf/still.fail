// still.fail's corner rule, measured (its docs/ui-panels.md, "所有带圆角的东西"): what has a ground of its own (a
// button, a row, a field, a block) and lies in the corner of a rounded container stands as far from the two edges of
// that corner, and its corner is the container's less that distance (concentric). A test asks the frame it drew
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
      let even = (dx - dy).abs() <= 0.5
      let concentric = (rb - (ra - dmax(dx, dy))).abs() <= 0.5
      if !(even && concentric) {
        let corner = ["top left", "top right", "bottom left", "bottom right"][k]
        out.push(
          "node \{i} (\{b.fw.round()}×\{b.fh.round()}, corner \{rb}) in the \{corner} of node \{p} (corner \{ra}): \{dx} and \{dy} from its edges" +
          (if concentric { "" } else { ", wants corner \{ra - dmax(dx, dy)}" }),
        )
      }
    }
  }
  out
}
