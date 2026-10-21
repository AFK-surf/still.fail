///|
/// How a fiber ended.
pub(all) enum Exit[X] {
  Succeeded(X)
  Failed(Error)
  Interrupted
} derive(Show)

///|
/// Joining a fiber that was interrupted.
pub suberror Interrupt derive(Show)

///|
/// A fiber: code running beside the code that forked it, in a scope.
pub struct Fiber[X] {
  priv task : Task
  priv cell : Ref[X?]
}

///|
pub fn[X] Fiber::id(self : Fiber[X]) -> Int {
  self.task.id
}

///|
/// How it ended, if it has.
pub fn[X] Fiber::poll(self : Fiber[X]) -> Exit[X]? {
  match self.task.end {
    NotYet => None
    Done => Some(Succeeded(self.cell.val.unwrap()))
    Raised(e) => Some(Failed(e))
    Cut => Some(Interrupted)
  }
}

///|
pub fn[X] Fiber::is_done(self : Fiber[X]) -> Bool {
  !(self.task.end is NotYet)
}

///|
/// Waits for it to end (Effect's Fiber.await).
pub async fn[X] Fiber::wait(self : Fiber[X]) -> Exit[X] noraise {
  self.task.await_end()
  self.poll().unwrap()
}

///|
/// Waits for its value: its error is raised, its interruption is `Interrupt`.
pub async fn[X] Fiber::join(self : Fiber[X]) -> X {
  match self.wait() {
    Succeeded(x) => x
    Failed(e) => raise e
    Interrupted => raise Interrupt
  }
}

///|
/// Asks it to stop, without waiting (Runner.interrupt).
pub fn[X] Fiber::interrupt(self : Fiber[X]) -> Unit {
  self.task.interrupt()
}

///|
/// Asks it to stop and waits until it has, its finalizers run (Fiber.interrupt).
pub async fn[X] Fiber::interrupt_and_wait(self : Fiber[X]) -> Exit[X] noraise {
  self.task.interrupt()
  self.wait()
}

///|
/// Runs `f` where interruption waits: asked to stop meanwhile, the fiber
/// stops at its first suspension after.
pub async fn[X] uninterruptible(f : async () -> X) -> X {
  let t = current_task()
  let x = shielded(t, f)
  // Asked to stop meanwhile: it stops here, not at some later suspension
  // (Effect checks between steps; what was acquired is already in a scope).
  if t.interrupted && t.shield == 0 {
    raise_cancel()
  }
  x
}

///|
async fn[X] shielded(t : Task, f : async () -> X) -> X {
  t.shield += 1
  defer {
    t.shield -= 1
  }
  f()
}

///|
/// The running fiber was asked to stop.
pub fn is_interrupted() -> Bool {
  current_task().interrupted
}

///|
/// Waits for ever (Effect.never): only an interruption ends it.
pub async fn[X] never() -> X noraise {
  while true {
    park()
  }
  abort("unreachable")
}
