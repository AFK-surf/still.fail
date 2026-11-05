///|
// Observations of what a retained page showed, read once each frame that reaches the screen has been drawn: where
// things were laid out and placed as that frame drew them, read plainly then, never followed as layout goes (layout
// tells nothing back as a change of its own, docs/retained.md rule 10). Layout may measure several versions of a list
// before a frame is drawn; only the one drawn is a reading position or a message seen whole.
let view_read_tells : Array[(@view.View, () -> (() -> Unit))] = []

///|
/// Tell `f` what `read` reads of `owner`'s page as each frame that shows it is drawn (where things are laid out and
/// placed then, read plainly), as that comes out otherwise than it was last told; told once for its first frame, a
/// value already told not told again, nothing told after its owner is gone. What it reads is no change of anything's:
/// use View::reacts for actions caused by state, rather than observations of a frame.
pub fn[T : Eq] read_drawn(owner : @view.View, read : () -> T, f : (T) -> Unit) -> Unit {
  let live = Ref(true)
  let told : Ref[T?] = Ref(None)
  let tell = fn() {
    let shown = @signals.untracked(read)
    fn() {
      if live.val && Some(shown) != told.val {
        told.val = Some(shown)
        f(shown)
      }
    }
  }
  view_read_tells.push((owner, tell))
  owner.owns(fn() {
    live.val = false
    match view_read_tells.search_by(fn(e) { physical_equal(e.1, tell) }) {
      Some(i) => view_read_tells.remove(i) |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
fn view_read_drawn() -> Unit {
  // A reply can change the page again. Read every observation before sending any, so another reader still reports the
  // frame just drawn; the reply's changes belong to the next frame.
  let shown = view_read_tells.filter(fn(e) { e.0.alive() }).map(fn(e) { (e.1)() })
  for tell in shown {
    @signals.untracked(tell)
  }
}
