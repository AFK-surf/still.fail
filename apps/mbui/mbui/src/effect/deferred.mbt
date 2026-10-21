///|
priv enum Slot[X] {
  Empty
  Value(X)
  Broken(Error)
}

///|
/// A value some fiber waits for and another (or a host's callback) gives, once.
pub struct Deferred[X] {
  priv mut slot : Slot[X]
  priv waiters : Waiters
}

///|
pub fn[X] Deferred::new() -> Deferred[X] {
  { slot: Empty, waiters: Waiters::new() }
}

///|
/// Gives it its value; false when it already had an outcome.
pub fn[X] Deferred::succeed(self : Deferred[X], x : X) -> Bool {
  guard self.slot is Empty else { return false }
  self.slot = Value(x)
  self.waiters.wake_all()
  true
}

///|
/// Gives it a failure; false when it already had an outcome.
pub fn[X] Deferred::fail(self : Deferred[X], e : Error) -> Bool {
  guard self.slot is Empty else { return false }
  self.slot = Broken(e)
  self.waiters.wake_all()
  true
}

///|
pub fn[X] Deferred::is_done(self : Deferred[X]) -> Bool {
  !(self.slot is Empty)
}

///|
/// Its value if it has one (None: not yet); its failure is raised.
pub fn[X] Deferred::poll(self : Deferred[X]) -> X? raise {
  match self.slot {
    Empty => None
    Value(x) => Some(x)
    Broken(e) => raise e
  }
}

///|
/// Waits for its outcome: the value, or the failure raised.
pub async fn[X] Deferred::wait(self : Deferred[X]) -> X {
  while self.slot is Empty {
    self.waiters.wait()
  }
  match self.slot {
    Value(x) => x
    Broken(e) => raise e
    Empty => abort("unreachable")
  }
}
