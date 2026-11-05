// Inputs and outputs of a forward calculation have different read permissions.
// Dependency tracking alone cannot enforce this: an untracked read, or a cached
// computed, can still carry an output back into the model's input phase.

///|
let capturing_inputs : Ref[Int] = Ref(0)

///|
let projecting : Ref[Int] = Ref(0)

///|
let deriving : Ref[ReactiveNode?] = Ref(None)

///|
/// Capture model inputs with their dependencies, without writing state or
/// reading a later phase's output. Unlike read_only, tracking is preserved.
pub fn[T] capture_inputs(f : () -> T) -> T {
  capturing_inputs.val += 1
  read_only_depth.val += 1
  defer {
    capturing_inputs.val -= 1
    read_only_depth.val -= 1
  }
  f()
}

///|
/// Calculate from the supplied inputs alone. Dynamic signal reads would be
/// hidden dependencies of the retained answer, even when they are untracked.
pub fn[T] project(f : () -> T) -> T {
  projecting.val += 1
  defer { projecting.val -= 1 }
  read_only(f)
}

///|
fn signal_read() -> Unit {
  guard projecting.val == 0 else {
    abort("a projection reads its captured inputs, not a signal")
  }
}

///|
/// Called by an output accessor (for example, placed geometry). Remember that
/// provenance on computed values too, including reads made inside untracked.
pub fn output_read() -> Unit {
  guard capturing_inputs.val == 0 && projecting.val == 0 else {
    abort("a forward calculation cannot read a previous output as an input")
  }
  match deriving.val {
    Some(node) => node.observes_output = true
    None => ()
  }
}

///|
/// Imperative adapters use the same write boundary as Signal::set.
pub fn require_mutable() -> Unit {
  guard read_only_depth.val == 0 else {
    abort("a projection cannot change bindings or structure")
  }
}
