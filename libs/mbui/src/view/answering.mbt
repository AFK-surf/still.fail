// What an answer tells is no cause of a way (the coordinator of the migration, 2026-11-13: a way sets out only for a
// cause, a person's act, the core telling something new of what it had answered, or a moment said; never for an answer
// first come, nor a part waking). What tells an answer says so (`answering`): the structures its writes mark are
// settled as it ends, each read anew and, where it reads otherwise, its change done then at once (View::comes), as
// were it made so. So it holds whatever else the change it is in does, in any order: a structure marked by a cause
// first is that cause's still (it is marked once; settled with the cause's change, its way), one settled quietly and
// marked by a cause after is that cause's change from what the answer left. A list's block given another key and woken
// (View::scrolls_window's `reused`) is told so too: a reused block is a new block to everything but the allocator (the
// coordinator of the migration, 2026-11-11), the one mechanism for both (2026-11-13).

///|
/// How deep in `answering` it is now; and the structures marked in it, each settled once as the outermost ends.
// kept across runs: set and put back around what tells an answer
let answering_depth : Ref[Int] = Ref(0)

///|
// kept across runs: filled while answering and emptied as it ends
let answer_marked : Array[() -> Unit] = []

///|
/// How many changes are being committed now (Tree::at_cause, a structure's first making), and whether an answer was told
/// in the one being committed: held till it is told whole, what its flush runs the answer's.
// kept across runs: counted up and down around each change
let cause_open : Ref[Int] = Ref(0)

///|
// kept across runs: the nodes an answer told in a change was told within, put back as that change is told whole
let answer_held : Ref[Array[Int]] = Ref([])

///|
/// Whether node `at` of `tree` is within one an answer told in the change being committed was told within
/// (answer_held): what comes or goes in it then is at once, what is outside it as ever.
fn Tree::answer_holds(self : Tree, at : Int) -> Bool {
  guard answer_held.val.length() > 0 else { return false }
  let mut i = at
  while i >= 0 && i < self.nodes.length() {
    if answer_held.val.contains(i) {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// Whether the structure's change being done now is one an answer told (settled as `answering` ends): what it makes or
/// lets go is so at once (View::comes).
// kept across runs: set and put back around a structure's change settled so
let answered : Ref[Bool] = Ref(false)

///|
/// `f`, which tells an answer (a subscription's first value written, a part of a list's block given another key, a
/// part woken from rest): the structures it marks settled as it ends, quietly, what they make or let go at once.
pub fn answering(f : () -> Unit, within? : View) -> Unit {
  // (told inside a change, within a node: what comes or goes in that node in the rest of that change is the answer's
  // too, held till the change is told whole, Tree::at_cause; a list's block given another key, woken, its parts told as
  // they wake and as they are read anew. What is outside it is the change's as ever: an event in it makes its way)
  match within {
    Some(v) if cause_open.val > 0 && !answer_held.val.contains(v.at) =>
      answer_held.val = answer_held.val + [v.at]
    _ => ()
  }
  // (in a batch of its own: what its writes mark is settled here before anything runs it as a change of its own, which
  // then finds it as it is)
  @signals.start_batch()
  answering_depth.val += 1
  f()
  answering_depth.val -= 1
  if answering_depth.val == 0 {
    // (one settled may mark another, settled in its turn: what it makes is no cause either)
    answering_depth.val += 1
    while answer_marked.length() > 0 {
      let due = answer_marked.copy()
      answer_marked.clear()
      for settle in due {
        settle()
      }
    }
    answering_depth.val -= 1
  }
  @signals.end_batch()
}

///|
/// What writes a subscription's first value tells it so (@signals.first_told), from the start.
fn init {
  @signals.first_told_with(fn(f) { answering(f) })
}

///|
/// Whether an answer is being told now (`answering`, or a structure's change it told being done): for what keys a
/// list's rows by data (its refill) to set them out at once as well.
pub fn answering_now() -> Bool {
  answering_depth.val > 0 || answered.val
}

///|
/// Whether an answer's marks are left set (answering_depth, answer_marked, answered): never, once what told it ends; a
/// Tester holds it after each frame it draws and as each begins (leaked_state).
pub fn answer_marks_left() -> Bool {
  answering_depth.val > 0 ||
  answer_marked.length() > 0 ||
  answered.val ||
  answer_held.val.length() > 0 ||
  cause_open.val > 0
}
