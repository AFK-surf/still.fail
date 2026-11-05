// A value has a source before anyone reads it. Deferring its subscription cell
// must not change that source to the first reader's current computation.

///|
pub struct LazySignal[T] {
  priv mut value : T
  priv mut hovered : Bool
  priv same : ((T, T) -> Bool)?
  priv mut cell : Signal[T]?
}

///|
/// A signal whose dependency node is made at its first read. Its initial value
/// and later writes keep their own provenance, exactly as signal's do.
pub fn[T] lazy_signal(initial : T, same? : (T, T) -> Bool) -> LazySignal[T] {
  { value: initial, hovered: from_hover(), same, cell: None }
}

///|
pub fn[T] LazySignal::get(self : LazySignal[T]) -> T {
  let cell = match self.cell {
    Some(cell) => cell
    None => {
      let cell = signal_with_source(self.value, self.hovered, same?=self.same)
      self.cell = Some(cell)
      cell
    }
  }
  cell.get()
}

///|
#callsite(autofill(loc))
pub fn[T] LazySignal::set(self : LazySignal[T], value : T, loc~ : SourceLoc) -> Unit {
  require_mutable()
  match self.cell {
    Some(cell) => cell.set(value, loc~)
    None => {
      self.value = value
      self.hovered = from_hover()
    }
  }
}

///|
/// Whether a reader has asked for this value (diagnostics need not create one).
pub fn[T] LazySignal::is_read(self : LazySignal[T]) -> Bool {
  self.cell is Some(_)
}
