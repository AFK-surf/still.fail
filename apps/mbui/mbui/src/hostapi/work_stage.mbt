// Work which has started, even if it never returns. Hosts may expose these numeric stages to an independent hang
// watcher. Only code-defined kinds: no conversation ids, messages, keys or URLs. Windows' names: host/win_hang.h.

///|
pub let work_frame_start : Int = 1
///|
pub let work_tree : Int = 2
///|
pub let work_messages : Int = 3
///|
pub let work_build : Int = 4
///|
pub let work_layout : Int = 5
///|
pub let work_after_build : Int = 6
///|
pub let work_paint : Int = 7
///|
pub let work_present : Int = 8
///|
pub let work_after_frame : Int = 9
///|
pub let work_event : Int = 10
///|
pub let work_chat_switch : Int = 20
///|
pub let work_screen_open : Int = 21
///|
pub let work_screen_state : Int = 22
///|
pub let work_screen_close : Int = 23

///|
/// Say the current phase before its work, returning the previous phase for restoring after it. No-op on hosts
/// without an independent watcher. It is diagnostic only: never used to decide what the app does.
pub fn work_stage(stage : Int) -> Int {
  current.val.work_stage(stage)
}

///|
/// A nested operation, its outer stage restored afterwards; the watcher can see it while `f` is still running.
pub fn[T] work_during(stage : Int, f : () -> T) -> T {
  let previous = work_stage(stage)
  let result = f()
  work_stage(previous) |> ignore
  result
}
