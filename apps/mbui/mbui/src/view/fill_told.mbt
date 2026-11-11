///|
/// NUMBERS ONLY (a draft, not to merge): a binding told what it read changed as a list's fill gave a block put by
/// another key (View::scrolls_window's `reused`), marked so; every way said while it runs is printed with its line,
/// `MOTION fill_told <file>: <kind> <line>`, so how many there are, and where, is counted before any guard is said.
// kept across runs: set and put back around what a fill tells, and around a binding's run
let filling : Ref[Bool] = Ref(false)

///|
// kept across runs: set and put back around a binding's run (Tree::queued)
let told_from_fill : Ref[Bool] = Ref(false)

///|
/// Whether a list's fill is telling a block put by its key now: set (true) around it, put back after.
fn fill_telling(on : Bool) -> Bool {
  let was = filling.val
  filling.val = on
  was
}

///|
/// A way said (`kind`, at `line`): printed if it is said under a binding told by a fill.
pub fn fill_way_said(kind : String, line : String) -> Unit {
  if told_from_fill.val {
    println("MOTION fill_told \{@flex.fill_file.val}: \{kind} \{line}")
  }
}

