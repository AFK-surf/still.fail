// A toast (web/ui toast.tsx, toast.css.ts): a short line at the bottom of the window, in the middle, named after what
// happened; 2.6 s, then it goes. mbui's toast (@kit.toaster: paused while the pointer is on it, swiped away) in the
// web's look. The phone's own toast is the phone's (the web's ToastTo).

///|
/// How long a toast stays (Toast.Provider's duration: 2.6 s).
pub let toast_ms : Double = 2600.0

///|
/// How long a toast offering something to do stays (an archive's 撤销): long enough to reach for it.
pub let toast_action_ms : Double = 5000.0

///|
/// What a toast says (said): a write its station did not answer may have been done (the core's `unconfirmed`), said as
/// not known, whatever the page put before it ("没能固定：不确定做没做成：…" → "固定：不确定做没做成：…").
pub fn toast_said(message : String) -> String {
  for lead in ["没能", "无法"] {
    if message.has_prefix(lead) {
      let rest = message.unsafe_substring(start=lead.length(), end=message.length())
      for unknown in ["不确定做没做成：", "无法确认是否成功："] {
        match rest.find("：" + unknown) {
          // (what failed said before it, with no other ： in it)
          Some(i) if !rest.unsafe_substring(start=0, end=i).contains("：") => return rest
          _ => ()
        }
      }
    }
  }
  message
}
