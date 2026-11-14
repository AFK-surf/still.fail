// Boundaries (React's and Solid's ErrorBoundary): what is made under one, and in its place what its fallback makes once
// something under it faults. A fault is what an app asked of the framework that it cannot do as asked (a Field given to
// two editors at once): in a test or a tool it stops the run, as it must fail there; in an app's run on a host (ui's
// `run`) it is told once (`fault_told`: the host's error report), done the nearest safe way where it is asked, and the
// boundary round it shows its fallback from the next moment the tree is woken for, never under what is being made or
// laid out as it faults. What the runtime itself cannot go on from (an index out of its array) no boundary takes.

///|
/// Told of each fault where it does not stop the run, once for each thing said (a host's error report).
// kept across runs: the host's, said once as its run begins
pub let fault_told : Ref[((String) -> Unit)?] = Ref(None)

///|
/// Whether a fault stops the run: in a test and a tool, where what faults must fail (so unless said otherwise); not in
/// an app's run on a host (ui's `run`), where it is told and its boundary shows it instead.
// kept across runs: the host's, said once as its run begins
pub let faults_stop : Ref[Bool] = Ref(true)

///|
/// The faults told so far (each told once).
// kept across runs: what the host was told, never told again
let faults_said : Map[String, Bool] = Map([])

///|
/// A fault with no boundary round it known (said outside any node): stopped where faults stop, else told.
pub fn fault(said : String) -> Unit {
  if faults_stop.val {
    @halt.saying(said)
  }
  if !faults_said.contains(said) {
    faults_said[said] = true
    match fault_told.val {
      Some(f) => f(said)
      None => ()
    }
  }
}

///|
/// A fault under node `id` (fault): told to the nearest boundary holding it, if one does and it is alive.
pub fn Tree::fault(self : Tree, id : NodeId, said : String) -> Unit {
  fault(said)
  let mut at = if self.alive_id(id) { id.at } else { -1 }
  while at >= 0 {
    match self.nodes[at].fault_to {
      Some(f) => {
        f(said)
        return
      }
      None => ()
    }
    at = self.nodes[at].parent
  }
}

///|
/// A fault under this node (Tree::fault).
pub fn View::fault(self : View, said : String) -> Unit {
  self.tree.fault(self.id(), said)
}

///|
/// This node a boundary of its own making: `shown` told the first fault under it (Tree::fault), at the next moment the
/// tree is woken for (not under what is being made or laid out as it faults), once. What shows it is `shown`'s.
pub fn View::faults_to(self : View, shown : (String) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  let told = Ref(false)
  n.fault_to = Some(fn(said) {
    if !told.val {
      told.val = true
      self.at_moment(self.tree.logic_said(), fn() { shown(said) }) |> ignore
    }
  })
  self
}

///|
/// What `make` makes, in its place what `fallback` makes (told what faulted) once something under it faults.
#callsite(autofill(loc))
pub fn View::boundary(self : View, make : (View) -> Unit, fallback : (View, String) -> Unit, loc~ : SourceLoc) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot(loc)
  let faulted : @signals.Signal[String?] = @signals.signal(None)
  slot.faults_to(fn(said) { faulted.set(Some(said)) }) |> ignore
  slot.pick(fn() { faulted.get() }, fn(v, said) {
    match said {
      None => make(v)
      Some(s) => fallback(v, s)
    }
  }, loc~)
}
