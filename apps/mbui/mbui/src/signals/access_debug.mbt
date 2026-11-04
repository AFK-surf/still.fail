// Phase contracts are checked in debug builds. Release reads keep the signals' original calling convention.

///|
let access_guard : Ref[String?] = Ref(None)

///|
pub fn set_access_guard(reason : String?) -> String? {
  let was = access_guard.val
  access_guard.val = reason
  was
}

///|
fn access_checked(kind : String, loc : SourceLoc) -> Unit {
  match access_guard.val {
    Some(reason) => {
      access_guard.val = None
      abort("\{reason}: \{kind} at \{loc}; capture this input before entering the phase")
    }
    None => ()
  }
}

///|
#callsite(autofill(loc))
pub fn[T] Signal::get(self : Signal[T], loc~ : SourceLoc) -> T {
  access_checked("signal read", loc)
  self.read_value()
}

///|
#callsite(autofill(loc))
pub fn[T] Computed::get(self : Computed[T], loc~ : SourceLoc) -> T {
  access_checked("computed read", loc)
  self.read_value()
}

///|
#callsite(autofill(loc))
pub fn[T] Computed::peek(self : Computed[T], loc~ : SourceLoc) -> T? {
  access_checked("computed peek", loc)
  self.1.value
}
