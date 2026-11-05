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
let before_hover_depth : Ref[Int] = Ref(0)

///|
let replying_to_hover : Ref[Bool] = Ref(false)

///|
/// Read inputs to structure, layout or placement. Presentation hover is found
/// after those phases, so it cannot be an input to them, even through a cache.
pub fn[T] before_hover(f : () -> T) -> T {
  require_before_hover()
  before_hover_depth.val += 1
  defer { before_hover_depth.val -= 1 }
  f()
}

///|
fn from_hover() -> Bool {
  replying_to_hover.val || (match deriving.val {
    Some(node) => node.observes_hover
    None => false
  })
}

///|
/// An immediate reply to presentation hover may change paint and accessibility,
/// but cannot move the geometry from which that hover was found.
pub fn require_before_hover() -> Unit {
  guard !from_hover() else {
    abort("presentation hover cannot change structure, layout or placement")
  }
}

///|
/// Mark a presentation hover accessor, including reads made without tracking.
pub fn hover_read() -> Unit {
  guard before_hover_depth.val == 0 else {
    abort("structure, layout and placement cannot read presentation hover")
  }
  output_read()
  match deriving.val {
    Some(node) => node.observes_hover = true
    None => ()
  }
}

///|
fn read_provenance(node : ReactiveNode) -> Unit {
  if node.observes_hover { hover_read() }
  else if node.observes_output { output_read() }
}

///|
fn hover_borrowed(node : ReactiveNode) -> Unit {
  let pending = [node]
  while pending.pop() is Some(source) {
    let mut link = source.subs
    while link is Some(l) {
      let sub = l.sub
      if sub.kind is ComputedNode && !sub.observes_hover {
        sub.observes_hover = true
        sub.observes_output = true
        pending.push(sub)
      }
      link = l.next_sub
    }
  }
}

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
/// A dependency borrowed after a getter ran also belongs to its cached readers.
/// Carry only that provenance: no getter or effect runs, and ownership links do
/// not turn an effect's owner into a reader of its output.
fn output_borrowed(node : ReactiveNode) -> Unit {
  let pending = [node]
  while pending.pop() is Some(source) {
    let mut link = source.subs
    while link is Some(l) {
      let sub = l.sub
      if sub.kind is ComputedNode && !sub.observes_output {
        sub.observes_output = true
        pending.push(sub)
      }
      link = l.next_sub
    }
  }
}

///|
/// Imperative adapters use the same write boundary as Signal::set.
pub fn require_mutable() -> Unit {
  guard read_only_depth.val == 0 else {
    abort("a projection cannot change bindings or structure")
  }
}
