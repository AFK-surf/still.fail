///|
let read_only_depth : Ref[Int] = Ref(0)

///|
/// Evaluate a projection of state. It cannot turn its result into another
/// state change. The caller supplies the inputs explicitly; signal reads here
/// do not attach dependencies to a surrounding effect.
pub fn[T] read_only(f : () -> T) -> T {
  read_only_depth.val += 1
  defer { read_only_depth.val -= 1 }
  untracked(f)
}
