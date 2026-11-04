// The debug build checks captured-input contracts; release signal reads carry no diagnostic argument or check.

///|
pub fn set_access_guard(_reason : String?) -> String? {
  None
}

///|
fn access_checked(_kind : String, _loc : SourceLoc) -> Unit {
  ()
}

///|
pub fn[T] Signal::get(self : Signal[T]) -> T {
  self.read_value()
}

///|
pub fn[T] Computed::get(self : Computed[T]) -> T {
  self.read_value()
}

///|
pub fn[T] Computed::peek(self : Computed[T]) -> T? {
  self.1.value
}
