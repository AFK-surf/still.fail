// Whether a node's words show cut short as it is laid out at a change's moment (View::words_cut_now), as an old view's
// box is (ui's Ctx::shows_cut): for what is said over it at that moment (a tip saying its words whole, wanted only where
// they do not show whole), never what it is made by. Read where a change is taken (a handler, what reacts to a change,
// what is due at a moment); a binding reading it fails its test: what is laid out told back as what is made (the
// coordinator of the migration, 2026-11-11: layout goes one way, held by the structure, not by what a comment says).

///|
/// Whether any words in it, its own or those of anything it holds that is laid out, show cut short as it is laid out as
/// of the logic's moment (what a change under way told counted, nothing placed by it: Tree::measured_now): ended in an
/// ellipsis where one line of them has not the room (as they are drawn: their one line wider than they are laid out),
/// said one of their shorter ways (View::shorter), or wrapped and laid out less tall than their lines (the lines past its
/// foot, or past the last it says it is drawn on, WordsLook's `max_lines`, as an old view's lines left off after its
/// last). As an old view's box is (ui's Ctx::shows_cut: the words' own
/// and every box holding them). Read where a change is taken, once, never followed; a binding reading it fails its test
/// (said where its node was made). False where it is let go.
pub fn View::words_cut_now(self : View) -> Bool {
  let tree = self.tree
  tree.cut_read_in_binding()
  guard self.alive() else { return false }
  tree.measured_now()
  @signals.untracked(fn() { tree.words_cut_in(self.at) })
}

///|
/// Whether any words of node `at`, or of what it holds that is laid out, show cut short as it is laid out now
/// (View::words_cut_now).
fn Tree::words_cut_in(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  if !n.live || n.out || n.flex.style.display == @flex.DisplayNone {
    return false
  }
  if self.words_cut_at(at) {
    return true
  }
  for k in n.kids {
    if self.words_cut_in(k) {
      return true
    }
  }
  false
}

///|
/// Whether node `at`'s own words show cut short as it is laid out now (View::words_cut_now): its words measured as the
/// host measures them (Tree's `measure`, `measure_runs`) at its size of words, against how big it is laid out, by as much
/// as the host draws them cut short past (half a point: ui's view_paint).
fn Tree::words_cut_at(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  let l = n.look
  if l.words_drawn is Some(_) {
    return true
  }
  let runs = !l.runs.is_empty()
  if l.words == "" && !runs {
    return false
  }
  let scale = self.words_scale_at(at)
  // (all of them, where they say how many lines they are drawn on: cut after the last as they are laid out)
  let look = if l.words_look.max_lines > 0 { { ..l.words_look, max_lines: 0 } } else { l.words_look }
  let measured = fn(width : Double) {
    if runs {
      (self.measure_runs)(l.runs, look, l.runs_look, width, scale)
    } else {
      (self.measure)(l.words, look, width, scale)
    }
  }
  if l.words_look.wrap {
    measured(n.flex.width).1 > n.flex.height + 0.5
  } else {
    measured(-1.0).0 > n.flex.width + 0.5
  }
}

///|
/// What is wrong where View::words_cut_now is read as it is: in a binding of a node made at a place the tree keeps (a
/// Tester's), what it says; None anywhere else (a handler, what reacts to a change; a device's tree, which keeps none).
fn Tree::cut_read_said(self : Tree) -> String? {
  let at = self.binding_reading
  guard at >= 0 && at < self.nodes.length() else { return None }
  let n = self.nodes[at]
  guard n.source is Some(_) else { return None }
  let made = match self.sources_of({ at, gen: n.gen }).get(0) {
    Some(s) => s.made
    None => "?"
  }
  Some(
    "WORDSCUT words_cut_now read in a binding of a node made at \{made}: it is read only at a change's moment (a handler, what reacts to a change), never as what is made is worked out (layout goes one way: mbui's src/view/words_cut.mbt)",
  )
}

///|
/// View::words_cut_now read in a binding: a fault, failing the test that runs it (Tree::cut_read_said).
fn Tree::cut_read_in_binding(self : Tree) -> Unit {
  match self.cut_read_said() {
    Some(said) => @halt.saying(said)
    None => ()
  }
}
