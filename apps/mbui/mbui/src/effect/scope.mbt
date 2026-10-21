///|
/// A scope: what is opened in it (fibers, finalizers, child scopes) ends when
/// it closes, the fibers interrupted and waited for, then the finalizers run
/// last to first, uninterruptibly.
pub struct Scope {
  priv rt : Runtime
  priv st : ScopeState
}

///|
/// What a scope holds (apart from the scope, so that the runtime can keep its
/// root's without holding a Scope, which holds the runtime).
struct ScopeState {
  children : Map[Int, Task]
  finalizers : Array[async () -> Unit]
  mut closed : Bool
  /// A fiber of it that fails is told to the runtime's `on_defect`.
  report : Bool
}

///|
fn ScopeState::new(report : Bool) -> ScopeState {
  { children: {}, finalizers: [], closed: false, report }
}

///|
fn Scope::make(rt : Runtime, report : Bool) -> Scope {
  { rt, st: ScopeState::new(report) }
}

///|
/// A new scope of its own (Scope.make), closed with `close` or `close_now`.
pub fn Runtime::scope(self : Runtime) -> Scope {
  Scope::make(self, true)
}

///|
/// A scope closed when this one closes (Runner.child).
pub fn Scope::child(self : Scope) -> Scope {
  let c = Scope::make(self.rt, self.st.report)
  self.add_finalizer(() => c.close())
  c
}

///|
pub fn Scope::is_closed(self : Scope) -> Bool {
  self.st.closed
}

///|
/// How many fibers of it are still running.
pub fn Scope::running(self : Scope) -> Int {
  self.st.children.length()
}

///|
/// Starts `f` as a fiber of the scope (forkScoped / FiberSet.add): interrupted
/// when the scope closes. Forked into a closed scope, it never runs.
pub fn[X] Scope::fork(self : Scope, f : async () -> X, name? : String = "") -> Fiber[X] {
  let cell : Ref[X?] = Ref(None)
  let t = self.rt.start(name, async fn() { cell.val = Some(f()) })
  if self.st.closed {
    t.interrupt()
  } else {
    self.st.children.set(t.id, t)
    ignore(
      t.watch(() => {
        self.st.children.remove(t.id)
        if self.st.report && t.end is Raised(e) {
          self.rt.report(e)
        }
      }),
    )
  }
  { task: t, cell }
}

///|
/// Runs `f` when the scope closes (addFinalizer); on a closed scope, soon.
pub fn Scope::add_finalizer(self : Scope, f : async () -> Unit) -> Unit {
  if self.st.closed {
    ignore(self.rt.start("finalizer", f))
  } else {
    self.st.finalizers.push(f)
  }
}

///|
/// `acquire`, uninterruptibly, and `release` of what it gave when the scope
/// closes (acquireRelease).
pub async fn[X] Scope::acquire_release(
  self : Scope,
  acquire : async () -> X,
  release : async (X) -> Unit,
) -> X {
  uninterruptible(() => {
    let x = acquire()
    self.add_finalizer(() => release(x))
    x
  })
}

///|
/// Closes it: its fibers are interrupted and waited for, then its finalizers
/// run, last first; all of it uninterruptibly. A finalizer's failure is told
/// to `on_defect` and the others still run.
pub async fn Scope::close(self : Scope) -> Unit noraise {
  if self.st.closed {
    return
  }
  self.st.closed = true
  let t = current_task()
  t.shield += 1
  defer {
    t.shield -= 1
  }
  // A fiber closing its own scope does not wait for itself: it stops at its
  // next suspension once the closing is done.
  let kids = self.st.children.values().to_array().filter(k => k.id != t.id)
  if self.st.children.contains(t.id) {
    t.interrupted = true
  }
  for k in kids {
    k.interrupt()
  }
  for k in kids {
    k.await_end()
  }
  while self.st.finalizers.pop() is Some(f) {
    f() catch {
      e => self.rt.report(e)
    }
  }
}

///|
/// Closes it from outside any fiber (a host's call): done by a task of its own.
pub fn Scope::close_now(self : Scope) -> Unit {
  ignore(self.rt.start("close", () => self.close()))
}

///|
priv enum Out[X] {
  Val(X)
  Thrown(Error)
  Stopped
}

///|
/// Runs `body` with a scope of its own, closed when it ends however it ends
/// (Effect.scoped): with its value, its error, or its interruption, after
/// what was opened in the scope has ended.
pub async fn[X] scoped(body : async (Scope) -> X) -> X {
  let s = Scope::make(current_task().rt, false)
  let out : Out[X] = try
    capture_cancel(() => Val(body(s)), handler=() => Stopped)
  catch {
    e => Thrown(e)
  }
  s.close()
  match out {
    Val(x) => x
    Thrown(e) => raise e
    Stopped => raise_cancel()
  }
}
