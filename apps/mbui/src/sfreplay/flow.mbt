// What two runs of a flow (steps.mbt) are compared by.

///|
/// The screen as laid out (Tester::dump: every node, where it is, its words) in a number (FNV-1a over its UTF-16
/// units): two runs that end the same have the same.
pub fn screen_sum(t : @ui.Tester) -> String {
  let mut h = 0x811c9dc5U
  for ch in t.dump() {
    h = (h ^ ch.to_int().reinterpret_as_uint()) * 0x01000193U
  }
  h.to_string()
}
