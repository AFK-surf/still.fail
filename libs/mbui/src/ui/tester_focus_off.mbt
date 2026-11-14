// The keyboard's focus is moved along only onto what is in the window: a key that moves it from one to the next (Tab,
// Shift+Tab, an arrow among a menu's rows or a list's) onto a node laid out wholly past the window's edges takes a
// person's focus where nobody sees it (a panel of 中屏's tape laid out behind the one in use, its buttons still gone to
// by Tab: sfdesk's tape_in_use, 2026-11-12). Where it is judged is where it comes to rest: with ways under way as the
// key is taken (a panel sliding in or out, a page coming), where it is once they end, as they said their end; with
// none, where it is then. Two steps, as every check that stops: Tester::focus_off_said says it, what a key the Tester
// presses runs (Tester::focus_moved_held) and the frame those ways end by (Tester::focus_off_at_rest) stop on it; a
// test of the check itself keeps what was said instead (Tester::focus_off_unheld, Tester::focus_off_found).

///|
/// Whether what the check finds stops the test (else kept, Tester::focus_off_found), and what it found so.
// kept across runs: put back by each Tester (Tester::new)
let focus_off_holds : Ref[Bool] = Ref(true)

///|
// kept across runs: emptied by each Tester (Tester::new)
let focus_off_seen : Ref[Array[String]] = Ref([])

///|
/// What the check found kept, not the test stopped on it (a test of the check itself: what it asserts).
pub fn Tester::focus_off_unheld(self : Tester) -> Unit {
  ignore(self)
  focus_off_holds.val = false
}

///|
/// What the check found since the Tester was made, where it is kept (Tester::focus_off_unheld).
pub fn Tester::focus_off_found(self : Tester) -> Array[String] {
  ignore(self)
  focus_off_seen.val.copy()
}

///|
/// The check's finding `said`: the test stopped on it, or it kept (Tester::focus_off_unheld).
fn focus_off_held(said : String) -> Unit {
  if focus_off_holds.val {
    @halt.saying(said)
  } else {
    focus_off_seen.val.push(said)
  }
}

///|
/// What a key moved the focus along onto while ways were under way, to be judged where it stops: which has the focus
/// (Ctx's `focus`), the moment those ways end (Tree::ways_end), the moment of the key, what it is called as the key
/// moved it there, where the Tester was made.
// kept across runs: put back by each Tester (Tester::new), what was left of the one before said first
let focus_off_due : Ref[(Int, Double, Double, String, String)?] = Ref(None)

///|
/// The moment of the last frame the Tester drew, as the check last looked (Tester::focus_off_at_rest).
// kept across runs: put back by each Tester (Tester::new)
let focus_off_drawn_at : Ref[Double] = Ref(0.0)

///|
/// What a key moved the focus along onto while ways were under way and that was not judged yet, the test (or this
/// Tester) at its end before those ways ended: what it is, when the key came, when its ways end, where the Tester
/// stood, where it was made. None where nothing was left so.
fn focus_off_left_said() -> String? {
  guard focus_off_due.val is Some((_, end, key_at, what, made)) else { return None }
  Some(
    "the keyboard's focus moved along at \{key_at} onto \{what}, the ways under way then ending at \{end}, never judged: its Tester's last frame at \{focus_off_drawn_at.val}, \{end - focus_off_drawn_at.val} short of their end (mbui's src/ui/tester_focus_off.mbt), the Tester made at \{made}",
  )
}

///|
/// What a key moved the focus along onto that was left unjudged as this Tester's frames stopped short of where its ways
/// end (focus_off_left_said), as Tester::audit asks (printed: its tests not held to it yet).
pub fn Tester::focus_off_left(self : Tester) -> Array[String] {
  ignore(self)
  match focus_off_left_said() {
    Some(said) => {
      println("FOCUS-OFF-LEFT " + said)
      [said]
    }
    None => []
  }
}

///|
/// As a Tester is made: what the one before left unjudged said (printed: its tests not held to it yet), the check put
/// back for the new one.
fn focus_off_begun() -> Unit {
  match focus_off_left_said() {
    Some(said) => println("FOCUS-OFF-LEFT " + said)
    None => ()
  }
  focus_off_due.val = None
  focus_off_drawn_at.val = 0.0
  focus_off_holds.val = true
  focus_off_seen.val = []
}

///|
/// What has the focus now said where it is wholly outside the window (None: nothing has it, it is drawn nowhere (no size),
/// or some of it is in the window): what it is, where it is drawn, the window's size, the moment, where the Tester was
/// made, and where the node was made where it is the window's tree's (Tree::source_of). `judged`: how the moment it is
/// judged at was come to (where it stops, or where it is with nothing on its way), said after where it is.
pub fn Tester::focus_off_said(self : Tester, judged? : String = "") -> String? {
  self.reads_own()
  let c = g()
  guard c.focus != 0 else { return None }
  let read = c.semantics_tree()
  guard read.search_by(fn(s) { s.focused }) is Some(k) else { return None }
  let s = read[k]
  let (x, y, w, h) = s.rect
  if w <= 0.0 || h <= 0.0 {
    return None
  }
  if x < self.w && x + w > 0.0 && y < self.h && y + h > 0.0 {
    return None
  }
  let made = match (tree_said_ids.get(s.id), view_app.val) {
    (Some(id), Some(tree)) =>
      match tree.source_of(id) {
        ("", _) => ", a node of the window's tree (its places not kept)"
        (m, "") => ", made at \{m}"
        (m, part) => ", made at \{m} (in what was asked for at \{part})"
      }
    _ => ", an old view's widget"
  }
  let judged = if judged == "" { "" } else { " (\{judged})" }
  Some(
    "the keyboard's focus moved onto what is wholly outside the window (mbui's src/ui/tester_focus_off.mbt): \{s.describe()} at \{rect_text(s.rect)}\{judged}\{made}; the window \{self.w}×\{self.h}, at \{self.fake.time}, the Tester made at \{looks_made_at.val}",
  )
}

///|
/// After a key the Tester pressed (`code`, `mods` held; `was`: what had the focus before it, Ctx's `focus`): where it
/// is one that moves the focus along (Tab, Shift+Tab, an arrow with nothing held) and the focus moved, where what has it comes to rest is judged: where ways are
/// under way as the key is taken (Tree::ways_end: a panel sliding in or out, a page coming), once they end, where it is
/// then (Tester::focus_off_at_rest); else where it is now, the test stopped where that is wholly outside the window,
/// saying so (Tester::focus_off_said).
fn Tester::focus_moved_held(self : Tester, code : Int, mods : Int, was : Int) -> Unit {
  // (Tab, Shift+Tab, an arrow with nothing held: a key with ⌘, ⌥ or ⌃ is a shortcut, ⌥↓ the next chat, not one)
  let along = (code == key_tab && (mods & mod_shift_key) == mods) ||
    (mods == 0 && (code == key_up || code == key_down || code == key_left || code == key_right))
  guard along else { return }
  let c = g()
  if c.focus == was {
    return
  }
  focus_off_due.val = None
  let end = match view_app.val {
    Some(tree) => tree.ways_end()
    None => -1.0
  }
  if end > self.fake.time {
    let what = match c.semantics_tree().search_by(fn(s) { s.focused }) {
      Some(k) => c.semantics_tree()[k].describe()
      None => "what has no words"
    }
    focus_off_due.val = Some((c.focus, end, self.fake.time, what, looks_made_at.val))
    return
  }
  match self.focus_off_said(judged="where it is, nothing on its way") {
    Some(said) => focus_off_held(said)
    None => ()
  }
}

///|
/// After a frame the Tester drew: where a key moved the focus along while ways were under way and they have ended by
/// now (Tester::focus_moved_held), what still has the focus judged where it stopped, the test stopped where that is
/// wholly outside the window; the focus gone elsewhere since, nothing judged.
fn Tester::focus_off_at_rest(self : Tester) -> Unit {
  focus_off_drawn_at.val = self.fake.time
  guard focus_off_due.val is Some((id, end, key_at, _, _)) && self.fake.time >= end else { return }
  focus_off_due.val = None
  if g().focus != id {
    return
  }
  match self.focus_off_said(judged="where it stops: moved onto at \{key_at} as ways went, judged at their end, \{end}") {
    Some(said) => focus_off_held(said)
    None => ()
  }
}
