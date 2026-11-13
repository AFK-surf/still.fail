// Not of alien-signals: how what writes a subscription's first value says so to what reads it (the app's core client,
// a made-up core's), as an answer. mbui's window tree sets it as its package starts (view's answering.mbt): what that
// makes or lets go comes at once, an answer first come being no cause of a way (the coordinator of the migration,
// 2026-11-13). Its own is to tell it as it is.

///|
// kept across runs: set once as the window tree's package starts, the same every run
let first_told_by : Ref[(() -> Unit) -> Unit] = Ref(fn(f) { f() })

///|
/// What tells a subscription's first value from now on (`by`, given what writes it).
pub fn first_told_with(by : (() -> Unit) -> Unit) -> Unit {
  first_told_by.val = by
}

///|
/// `f`, which writes a subscription's first value, told as one (first_told_with).
pub fn first_told(f : () -> Unit) -> Unit {
  (first_told_by.val)(f)
}
