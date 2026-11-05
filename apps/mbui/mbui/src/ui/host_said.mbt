// What the host has for the app once (what another app shared in, a file kept or not, the system's answer to an ask),
// which the host says only when asked (its ABI reads it, taking it): asked for as what was posted is taken, as each
// frame begins and before any of the window's tree is built or laid out, and handed to the one node that holds it.

///|
/// One that holds a kind of what the host has once: whether its node is still there, and what asks the host and hands
/// it on (true where something came).
priv struct HostSaid {
  kind : String
  live : Ref[Bool]
  take : () -> Unit
}

///|
/// Who holds what the host has once, in the order they said so.
// kept across runs: let go as a run begins (messages_reset), each with its node
let host_saids : Array[HostSaid] = []

///|
/// What the host has once of kind `kind` (`said`: asks the host, taking it: None, nothing), handed to `f` as it comes:
/// asked as what was posted is taken, as each frame begins, before any of the window's tree is built or laid out; each
/// once. Held by node `owner`: asked no more once it is let go. One kind is one holder's: what `said` takes, another
/// asking after it never has (a Tester aborts where two live holders say one kind). `said` and `f` run untracked: the
/// host asked is nothing they depend on; what `f` sets tells what reads it, as any change does. `f` sets signals and
/// says what is to be done, never reads where things are laid out (that is not laid out yet: View::laid_size_told and
/// the like are a fault there, stopping a test's run, told a host's once).
pub fn[T] on_host_said(owner : @view.View, kind~ : String, said : () -> T?, f : (T) -> Unit) -> Unit {
  if fake.val is Some(_) &&
    host_saids.iter().any(fn(h) { h.live.val && h.kind == kind }) {
    abort("on_host_said: two holders of \"\{kind}\": what the host has once is one holder's")
  }
  let live = Ref(true)
  host_saids.push({
    kind,
    live,
    take: fn() {
      match said() {
        Some(v) => {
          // (nothing laid out yet as it is handed on: a read of where things are is a fault, @view.fault)
          let was = @view.shut_layout_reads(Some("on_host_said \"\{kind}\"'s f"))
          f(v)
          @view.shut_layout_reads(was) |> ignore
        }
        None => ()
      }
    },
  })
  owner.owns(fn() { live.val = false }) |> ignore
}

///|
/// As a frame begins, as what was posted is taken (frame_drawn): each holder still there asked, in the order they said
/// so, untracked; those let go dropped. A holder let go while another's `f` runs is not asked (the list as it was, each
/// looked at as its turn comes).
fn host_said_arrive() -> Unit {
  if host_saids.is_empty() {
    return
  }
  let now = host_saids.copy()
  for h in now {
    if h.live.val {
      @signals.untracked(h.take)
    }
  }
  host_saids.retain(fn(h) { h.live.val })
}
