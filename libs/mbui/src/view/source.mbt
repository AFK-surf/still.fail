// Where in the source what the window shows was made: the way from what is seen (a fault a check found, a point of a
// picture, words people name) to the line to change. Each node keeps where it was made (View::box, and a structure's:
// show, pick, each, each_of, boundary; the place that called it, as MoonBit fills a `SourceLoc` in), where the part it
// is the outside of was asked for (View::made_for: a library's part says it, so a press in a button is traced to the
// app's line that asked for the button, not only the library's inside it), and where each of its properties was last
// said (View::bind). A place reads `module/path:line`, `stillfail/src/sfpages/chat.mbt:120`.
//
// Kept only where the tree is made to (Tree::new's `sources`: a Tester's): elsewhere each call passes its place on and
// nothing is kept.

///|
/// Where a node was made and its properties said.
priv struct Source {
  made : SourceLoc
  mut made_for : SourceLoc?
  /// by Prop::ord: the property and where it was last said
  said : Map[Int, (Prop, SourceLoc)]
}

///|
/// A place as it is said: `module/path:line` (MoonBit's `path:line:col-line:col@module`, where it began).
pub fn source_place(loc : SourceLoc) -> String {
  let s = loc.to_string()
  let (path, module_name) = match s.rev_find("@") {
    Some(i) => (s[:i].to_owned(), s[i + 1:].to_owned())
    None => (s, "")
  }
  // (`path:line:col-line:col`: to its first line)
  let path = match path.find(":") {
    Some(i) =>
      match path[i + 1:].find(":") {
        Some(j) => path[:i + 1 + j].to_owned()
        None => path
      }
    None => path
  }
  if module_name == "" {
    path
  } else {
    module_name + "/" + path
  }
}

///|
/// It is the outside of a part asked for at `loc` (a library's part says so of the node it makes and gives back, at the
/// place its caller asked for it: its own `loc~`): what is found in it is traced to there (source.mbt).
pub fn View::made_for(self : View, loc : SourceLoc) -> View {
  guard self.live() is Some(n) else { return self }
  match n.source {
    Some(s) => s.made_for = Some(loc)
    None => ()
  }
  self
}

///|
/// One node on the way from what is drawn out to the root: who it is, where it was made, where the part it is the
/// outside of was asked for ("" where it is no part's), and where each of its properties was last said, by name, in
/// the order the properties are listed. Places as source_place says them.
#derive(Eq, Debug)
pub(all) struct SourceStep {
  id : NodeId
  made : String
  made_for : String
  said : Array[(String, String)]
}

///|
/// Where node `id` was made, and what holds it out to the root, innermost first; none where it is let go or the tree
/// keeps no sources. A structure's own node (show's, each's) holds no box: it is said as what it made is.
pub fn Tree::sources_of(self : Tree, id : NodeId) -> Array[SourceStep] {
  let out : Array[SourceStep] = []
  guard self.alive_id(id) else { return out }
  let mut at = id.at
  while at >= 0 {
    let n = self.nodes[at]
    match n.source {
      Some(s) if !n.slot => {
        // (in the order the properties are listed: Prop::ord)
        let ords = s.said.keys().collect()
        ords.sort()
        let said = ords.map(fn(k) {
          let (p, l) = s.said.get(k).unwrap()
          (Show::to_string(p), source_place(l))
        })
        out.push({
          id: { at, gen: n.gen },
          made: source_place(s.made),
          made_for: match s.made_for {
            Some(l) => source_place(l)
            None => ""
          },
          said,
        })
      }
      _ => ()
    }
    at = n.parent
  }
  out
}

///|
/// The node drawn topmost at (x, y) in the window (by the order drawn, where the scene composed draws it: as a press
/// finds it, whether or not it takes one), none where nothing is seen there.
pub fn Tree::topmost_at(self : Tree, x : Double, y : Double) -> NodeId? {
  let found : Ref[NodeId?] = Ref(None)
  self.each_drawn_scaled(fn(c, cx, cy, alpha, s) {
    if alpha > 0.01 && c.draws() && x >= cx && y >= cy && x < cx + c.w * s && y < cy + c.h * s {
      found.val = Some(c.id)
    }
  })
  found.val
}

///|
/// What node `id` is as laid out and drawn, a line each, and where the property each comes of was said (where the tree
/// keeps that): its box in the window, the room inside and round it, the room between what it holds, its ground, ink,
/// corners and opacity, its words and how they are set. What it says nothing of is not said. None where it is not
/// drawn.
pub fn Tree::looks_of(self : Tree, id : NodeId) -> Array[String] {
  let out : Array[String] = []
  guard self.drawn_of(id) is Some(d) else { return out }
  let n = self.nodes[id.at]
  let said = fn(props : Array[Prop]) -> String {
    match n.source {
      Some(s) => {
        let at : Array[String] = []
        for p in props {
          match s.said.get(p.ord()) {
            Some((_, l)) => {
              let p = source_place(l)
              if !at.contains(p) {
                at.push(p)
              }
            }
            None => ()
          }
        }
        if at.is_empty() {
          ""
        } else {
          " (said at " + at.join(", ") + ")"
        }
      }
      None => ""
    }
  }
  let num = fn(v : Double) -> String {
    let r = (v * 2.0).round() / 2.0
    if r == r.floor() {
      r.to_int().to_string()
    } else {
      r.to_string()
    }
  }
  let colour = fn(c : Int64) -> String {
    let d = "0123456789abcdef"
    let sb = StringBuilder()
    sb.write_string("#")
    for k = 7; k >= 0; k = k - 1 {
      let v = ((c >> (k * 4)) & 0xFL).to_int()
      sb.write_string(d[v:v + 1].to_owned())
    }
    sb.to_string()
  }
  let st = n.flex.style
  let four = fn(a : Double, b : Double, c : Double, e : Double) {
    "\{num(a)},\{num(b)},\{num(c)},\{num(e)}"
  }
  out.push("box \{num(d.x)},\{num(d.y)} \{num(d.w)}×\{num(d.h)}" + said([Width, Height]))
  let pad = (st.padding_left_value(), st.padding_top_value(), st.padding_right_value(), st.padding_bottom_value())
  if pad != (0.0, 0.0, 0.0, 0.0) {
    out.push("padding " + four(pad.0, pad.1, pad.2, pad.3) + said([Padding]))
  }
  let mar = (st.margin_left_value(), st.margin_top_value(), st.margin_right_value(), st.margin_bottom_value())
  if mar != (0.0, 0.0, 0.0, 0.0) {
    out.push("margin " + four(mar.0, mar.1, mar.2, mar.3) + said([Margin]))
  }
  if st.gap_col_value() != 0.0 {
    out.push("gap \{num(st.gap_col_value())}" + said([Gap]))
  }
  if (d.ground & 0xFFL) != 0L {
    out.push("ground " + colour(d.ground) + said([Ground]))
  }
  if d.radius > 0.0 || d.corners is Some(_) {
    let r = match d.corners {
      Some(c) => four(c.0, c.1, c.2, c.3)
      None => num(d.radius)
    }
    out.push("corners " + r + said([Radius, Corners]))
  }
  if d.edge.0 > 0.0 {
    out.push("edge \{num(d.edge.0)} " + colour(d.edge.1) + said([Edge]))
  }
  if d.alpha < 1.0 {
    out.push("opacity \{num(d.alpha * 100.0)}%" + said([Alpha]))
  }
  if d.words != "" {
    let k = d.words_look
    out.push("words \"\{d.words}\" " + colour(d.ink) + said([Words, Ink]))
    out.push("set \{num(k.size)}/\{num(k.line)} weight \{k.weight}\{if k.wrap { " wrapped" } else { "" }}" +
      said([WordsLook]))
  } else if (d.ink & 0xFFL) != 0L {
    out.push("ink " + colour(d.ink) + said([Ink]))
  }
  out
}

///|
/// What takes presses where it is drawn now, for a check of the room each has to be pressed in (ui's rooms.mbt): each
/// node drawn that does something pressed or held (View::on_press, View::on_drag; not one hosting an old view, whose
/// own boxes are its; nor a ground (View::as_ground: a message's words a hold picks in, the links in them, ui's
/// runs_links), no control: no room of its own, none it cuts) and takes
/// it now (Tree::pressless_at: not leaving, nor said to take none, nor under a modal layer
/// it is not in), seen, whole within the window and what bounds its input (View::bounds_input: a list's rows scrolled
/// partly out are not). Each with its box in the window (x0, y0, x1, y1), the nearest such that holds it (its index
/// here, -1 none) and the node of the root's it is in (its layer: two in different ones never meet).
pub fn Tree::press_boxes(self : Tree) -> Array[(NodeId, (Double, Double, Double, Double), Int, Int)] {
  let found : Array[(NodeId, (Double, Double, Double, Double))] = []
  let (ww, wh) = self.room.untracked()
  self.each_drawn_scaled(fn(c, cx, cy, alpha, s) {
    let n = self.nodes[c.id.at]
    if alpha <= 0.01 ||
      n.hosted ||
      (n.points && n.hold_only is None) ||
      (n.on_press is None && n.on_drag is None) ||
      n.as_ground ||
      self.pressless_at(c.id.at) {
      return
    }
    let b = (cx, cy, cx + c.w * s, cy + c.h * s)
    let (bx0, by0, bx1, by1) = self.input_bounds(c.id)
    let slack = 1.0
    if b.2 - b.0 <= 0.0 ||
      b.3 - b.1 <= 0.0 ||
      b.0 < dmax(0.0, bx0) - slack ||
      b.1 < dmax(0.0, by0) - slack ||
      b.2 > dmin(ww, bx1) + slack ||
      b.3 > dmin(wh, by1) + slack {
      return
    }
    found.push((c.id, b))
  })
  let index : Map[Int, Int] = Map([])
  for k, f in found {
    index[f.0.at] = k
  }
  found.map(fn(f) {
    let mut h = self.nodes[f.0.at].parent
    while h >= 0 && !index.contains(h) {
      h = self.nodes[h].parent
    }
    (f.0, f.1, index.get(h).unwrap_or(-1), self.top_of(f.0.at))
  })
}

///|
/// Where node `id` was made, and where the innermost part it is in was asked for ("" where it is in none), as
/// source_place says them: what a line naming it says of it (Tree::sources_of's first and its first part's alone,
/// nothing else worked out); ("", "") where it is let go or the tree keeps no sources.
pub fn Tree::source_of(self : Tree, id : NodeId) -> (String, String) {
  guard self.alive_id(id) && self.nodes[id.at].source is Some(s) else { return ("", "") }
  let mut at = id.at
  while at >= 0 {
    let n = self.nodes[at]
    match n.source {
      Some({ made_for: Some(l), .. }) => return (source_place(s.made), source_place(l))
      _ => ()
    }
    at = n.parent
  }
  (source_place(s.made), "")
}
