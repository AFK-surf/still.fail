// The desktop's own: its pages and what they hold, each ported from the web's file (or the desktop app's) and made of
// the library's parts (src/sf), reading what sfbase reads. Nothing of the phone's pages is here or reachable from here
// (sfapp imports this package, so this one cannot import it); what both need is the library's or sfbase's.

///|
/// What this package keeps put back as the app begins anew (its reset).
pub fn reset() -> Unit {
  wide_reset()
  marks_reset()
  context_reset()
  switcher_reset()
  browse_reset()
  cols_reset()
  kept_reset()
  pane_reset()
  drive_reset()
  shell_reset()
}
