// Where in the source what a test sees was made (view's source.mbt): from a point of the window, or the words drawn
// there, out to the root, each node with where it was made and the part it is the outside of asked for where, and what
// the node there looks like with where each of that was said. A fault a check finds (squeeze.mbt, contrast.mbt,
// corners.mbt's Ctx::named) says where the node it names was made the same way, so what fails says what to change.
// An old view's boxes (Ctx) keep no places of their own: what holds them is said, the node hosting the old view.

///|
/// What is drawn topmost at (x, y) in the window and what holds it out to the root (Tree::topmost_at,
/// Tree::sources_of), as sources_said says them; or why nothing is said.
pub fn Tester::sources_at(self : Tester, x : Double, y : Double) -> String {
  self.reads_own()
  ignore(self)
  guard view_tree() is Some(tree) else { return "no window's tree" }
  guard tree.topmost_at(x, y) is Some(id) else { return "nothing is drawn at \{x},\{y}" }
  sources_said(tree, id)
}

///|
/// The same for the words `s` where they are drawn last (over the others: Tester::find_last's), the node drawing them.
pub fn Tester::sources_of(self : Tester, s : String) -> String {
  self.reads_own()
  ignore(self)
  guard view_tree() is Some(tree) else { return "no window's tree" }
  let mut found : @view.NodeId? = None
  for d in tree.drawn() {
    if d.bones == 0L && view_words_found(d).contains(s) {
      found = Some(d.id)
    }
  }
  guard found is Some(id) else { return "no words \"\{s}\" are drawn by the window's tree" }
  sources_said(tree, id)
}

///|
/// Node `id` and what holds it, as said for a test: first the places the parts it is in were asked for, innermost
/// first (the app's line is among them: a library's part asked for at it); then each node out to the root, a line
/// each (who it is, its words, where it was made and as what part's outside), the innermost's look under it with
/// where each of that was said (Tree::looks_of).
fn sources_said(tree : @view.Tree, id : @view.NodeId) -> String {
  let steps = tree.sources_of(id)
  if steps.is_empty() {
    return "node \{id.at}: its places are not kept (Tester::new's keeps_sources)"
  }
  let lines : Array[String] = []
  let asked = steps.filter(fn(s) { s.made_for != "" }).map(fn(s) { s.made_for })
  if !asked.is_empty() {
    lines.push("asked for at: " + asked.join(" ← "))
  }
  for k, s in steps {
    let words = match tree.drawn_of(s.id) {
      Some(d) if d.words != "" => " 「\{words_short(d.words)}」"
      _ => ""
    }
    let part = if s.made_for != "" { ", the outside of what was asked for at \{s.made_for}" } else { "" }
    lines.push("node \{s.id.at}\{words}: made at \{s.made}\{part}")
    if k == 0 {
      for l in tree.looks_of(s.id) {
        lines.push("  " + l)
      }
    }
  }
  lines.join("\n")
}

///|
/// Where node `id` of the window's tree comes from, as a fault that names it says it: where it was made, and where
/// the innermost part it is in was asked for ("made at …, in what was asked for at …"); "" where its places are not
/// kept.
fn source_said(id : @view.NodeId) -> String {
  guard view_tree() is Some(tree) else { return "" }
  match tree.source_of(id) {
    ("", _) => ""
    (made, "") => "made at \{made}"
    (made, asked) => "made at \{made}, in what was asked for at \{asked}"
  }
}

///|
/// Where the node hosting the old view that box `i` of the frame just built is in comes from ("in an old view made at
/// …", source_said), "" where none does or its places are not kept.
fn Ctx::old_source_said(self : Ctx, i : Int) -> String {
  if old_boxes.is_empty() {
    return ""
  }
  // (each old view's box, the node hosting it)
  let hosts : Map[Int, @view.NodeId] = Map([])
  for id, at in old_boxes {
    hosts[at] = id
  }
  let mut b = i
  while b >= 0 && b < self.count {
    match hosts.get(b) {
      Some(id) => {
        let s = source_said(id)
        return if s == "" { "" } else { "in an old view " + s }
      }
      None => b = self.nodes[b].parent
    }
  }
  ""
}

///|
/// Words cut to 24 characters for a line that names what draws them.
fn words_short(w : String) -> String {
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
  sb.to_string()
}

///|
/// Node `id` of the window's tree's places as a fault naming it says them after what it says of it (source_said): ",
/// made at …" (` (made at …)` where `paren`), "" where they are not kept.
fn tree_source_said(id : @view.NodeId, paren? : Bool = false) -> String {
  let s = source_said(id)
  if s == "" {
    ""
  } else if paren {
    " (" + s + ")"
  } else {
    ", " + s
  }
}

///|
/// Every rule the screen as it is now is held to, at once: a press's room (the old view's and the window's tree's),
/// what is squeezed, the spacing, the corners, the contrast, words a box with its height said does not hold (each
/// check's own lines, its rule first, what it names said with where the source made it). For the agent that changed a screen to run after the change, in the place of
/// judging a picture by eye: none, and the screen keeps them all. Contrast draws a frame of its own and then the
/// screen back, both at the last frame's moment (Tester::contrast_faults): what is read right after it (the words, the
/// draw list) and the clock are as they were before it.
pub fn Tester::audit(self : Tester) -> Array[String] {
  // (a key's focus left unjudged as the frames stopped short of where its ways end: printed only, for now,
  // tester_focus_off.mbt)
  self.focus_off_left() |> ignore
  self.room_faults() +
  self.tree_room_faults() +
  self.squeeze_faults() +
  self.gap_faults() +
  self.corner_faults() +
  self.contrast_faults() +
  self.fixed_outgrown()
}
