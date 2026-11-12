///|
/// Whether a list's block put by is being given another key now (View::scrolls_window's `reused`: its key set and
/// what it binds woken), held till the change it is of is told whole (Tree::at_cause): what a structure in it makes or
/// lets go because of that is so at once (View::comes), as it would be were the block made anew for that key. A reused
/// block is a new block to everything but the allocator (the coordinator of the migration, 2026-11-11).
// kept across runs: set as a block is taken, put back as the change it is of is told whole
let key_taking : Ref[Bool] = Ref(false)

///|
/// Whether the structure's change being made now was told by a block taken for another key (key_taking, as its
/// reaction was marked): what it makes or lets go is so at once.
// kept across runs: set and put back around a structure's change (Tree::structured)
let key_taken : Ref[Bool] = Ref(false)

///|
/// A block given another key (`at`, the block), marked so (key_taking): only inside a change (Tree::at_cause, a
/// structure's first making), which puts the mark back as it is told whole. One outside any is a fault told, the mark not
/// set (what it makes or lets go then comes its way, as before the rule: wrong by a motion, and said, never the app gone
/// for the framework's own slip); a Tester stops on it.
fn key_taking_set(tree : Tree, at : NodeId) -> Unit {
  if tree.committing == 0 {
    tree.fault(at, "a list's block given another key outside any change: nothing would put key_taking back")
    return
  }
  key_taking.val = true
}

///|
/// Whether a block's key's marks are left set (key_taking, key_taken): never, once a change is told whole; a Tester
/// holds it after each frame it draws and as each begins (leaked_state).
pub fn key_marks_left() -> Bool {
  key_taking.val || key_taken.val
}
