// The language's own async primitives, bound as moonbitlang/async binds them
// (internal/coroutine/async_primitive.mbt). Everything in effect.mb is built on
// these four: a task is a chain of continuations the scheduler resumes, and
// cancellation is the language's (`defer` runs, `catch` cannot swallow it).

///|
/// Parks the running code: `register` gets the continuation to call later.
async fn[T] suspend_raw(
  register : ((T) -> Unit) -> Unit,
) -> T noraise + nocancel = "%async.suspend"

///|
/// Starts async code from sync code; it runs until its first suspension.
fn run_raw(work : async () -> Unit noraise + nocancel) -> Unit = "%async.run"

///|
/// Raises the cancellation signal where the code is.
async fn[X] raise_cancel() -> X noraise = "%async.raise_cancellation_signal"

///|
/// Runs `f`; a cancellation signal out of it is turned into `handler`'s result.
async fn[X] capture_cancel(
  f : async () -> X,
  handler~ : async () -> X nocancel,
) -> X nocancel = "%async.capture_cancellation"
