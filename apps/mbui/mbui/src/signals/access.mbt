// What a phase may not read: said as the phase begins (set_access_guard, a layout box's: View::layout_box), each read
// and write of a signal checked against it in every build, a test's as an app's. One in it aborts, saying the phase,
// what it was and where: an input the phase reads is taken before it begins.

///|
// kept across runs: said and put back by each phase that keeps its reads to what it took before
let access_guard : Ref[String?] = Ref(None)

///|
/// What no read nor write of a signal may happen in from now (None: any may), what was said before given back.
pub fn set_access_guard(reason : String?) -> String? {
  let was = access_guard.val
  access_guard.val = reason
  was
}

///|
/// A read or write (`kind`) at `loc`: aborted in a phase that may have none, saying which and where.
fn access_checked(kind : String, loc : SourceLoc) -> Unit {
  match access_guard.val {
    Some(reason) => {
      access_guard.val = None
      abort("\{reason}: \{kind} at \{loc}; take this input before the phase begins")
    }
    None => ()
  }
}

///|
/// The signal's value (signalOper read), checked against the phase it is read in (access_checked).
#callsite(autofill(loc))
pub fn[T] Signal::get(self : Signal[T], loc~ : SourceLoc) -> T {
  access_checked("signal read", loc)
  self.read_value()
}

///|
/// The computed's value, worked out again first if what it read changed since (computedOper), checked as a signal's.
#callsite(autofill(loc))
pub fn[T] Computed::get(self : Computed[T], loc~ : SourceLoc) -> T {
  access_checked("computed read", loc)
  self.read_value()
}

///|
/// What the computed made last, not worked out again (none before it was first read), checked as a signal's.
#callsite(autofill(loc))
pub fn[T] Computed::peek(self : Computed[T], loc~ : SourceLoc) -> T? {
  access_checked("computed peek", loc)
  self.1.value
}

///|
/// The tree's phases a read may be guarded in (phase_guard): a build (what a view reads as it is made, a row made in a
/// layout's too), a layout (what measuring reads, a child measured in a layout's too).
pub(all) enum AccessPhase {
  Build
  Layout
} derive(Eq, Show)

///|
// kept across runs: what each phase may not read, as said for it (none yet: each reads what it reads now)
let phase_guards : Map[String, String] = {}

///|
/// The guard of `phase`, what a part of another phase that is one of it (a row made in a layout: a build) runs under:
/// set_access_guard's, given back as it ends.
pub fn phase_guard(phase : AccessPhase) -> String? {
  phase_guards.get(phase.to_string())
}

///|
/// What `phase` may not read from now (None: what it reads now).
pub fn set_phase_guard(phase : AccessPhase, reason : String?) -> Unit {
  match reason {
    Some(r) => phase_guards[phase.to_string()] = r
    None => phase_guards.remove(phase.to_string())
  }
}
