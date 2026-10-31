// What values the last frame's nodes take, by kind (Tester::census): how many sizes of words, paddings, corners and
// colours a screen uses, which an app keeps few (its styles' tokens: docs/style.md), the window's tree's nodes with the
// old frame's (Tree::styled). Read only.

///|
/// The values the last frame used, each kind's distinct values sorted: words' sizes with their lines' heights
/// (`15/22`; `/0` the font's own; `32/44.8 -0.6` with letter spacing), weights, paddings and gaps, corners, colours (a ground, an edge, words; hex).
pub(all) struct Census {
  text : Array[String]
  weight : Array[String]
  space : Array[String]
  radius : Array[String]
  color : Array[String]
}

///|
fn census_num(v : Double) -> String {
  let r = (v * 100.0).round() / 100.0
  if r == r.floor() {
    r.to_int().to_string()
  } else {
    r.to_string()
  }
}

///|
fn census_hex(c : Int64) -> String {
  let digits = "0123456789ABCDEF"
  let sb = StringBuilder()
  for k in 0..<8 {
    let d = ((c >> ((7 - k) * 4)) & 0xFL).to_int()
    sb.write_char(digits[d].unsafe_to_char())
  }
  sb.to_string()
}

///|
fn census_sorted(m : Map[String, Bool]) -> Array[String] {
  let out = m.keys().collect()
  out.sort()
  out
}

///|
/// What values the last frame's nodes took (Census), the window's tree's nodes' as they are set too.
pub fn Tester::census(self : Tester) -> Census {
  ignore(self)
  let c = g()
  let text : Map[String, Bool] = {}
  let weight : Map[String, Bool] = {}
  let space : Map[String, Bool] = {}
  let radius : Map[String, Bool] = {}
  let color : Map[String, Bool] = {}
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_text || n.kind == kind_rich {
      text[census_num(n.font_size) +
        "/" +
        census_num(n.line_h) +
        (if n.spacing != 0.0 { " " + census_num(n.spacing) } else { "" })] = true
      weight[n.weight.to_string()] = true
      color[census_hex(n.color)] = true
      continue
    }
    if n.kind != kind_box {
      continue
    }
    for v in [n.pad_l, n.pad_t, n.pad_r, n.pad_b, n.gap] {
      if v > 0.0 {
        space[census_num(v)] = true
      }
    }
    for k in 0..<4 {
      if n.radius_at(k) > 0.0 {
        radius[census_num(n.radius_at(k))] = true
      }
    }
    if (n.bg & 0xFFL) != 0L {
      color[census_hex(n.bg)] = true
    }
    if n.border_w > 0.0 && (n.border_c & 0xFFL) != 0L {
      color[census_hex(n.border_c)] = true
    }
  }
  // (and the window's tree's nodes, as each is set: Tree::styled)
  match view_app.val {
    Some(tree) =>
      for n in tree.styled() {
        if n.words {
          text[census_num(n.size) + "/" + census_num(n.line)] = true
          for w in n.weights {
            weight[w.to_string()] = true
          }
          for k in n.inks {
            if (k & 0xFFL) != 0L {
              color[census_hex(k)] = true
            }
          }
        }
        for v in n.spaces {
          if v > 0.0 {
            space[census_num(v)] = true
          }
        }
        if n.radius > 0.0 {
          radius[census_num(n.radius)] = true
        }
        if (n.ground & 0xFFL) != 0L {
          color[census_hex(n.ground)] = true
        }
      }
    None => ()
  }
  {
    text: census_sorted(text),
    weight: census_sorted(weight),
    space: census_sorted(space),
    radius: census_sorted(radius),
    color: census_sorted(color),
  }
}
