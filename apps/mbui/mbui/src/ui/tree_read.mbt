///|
// Observations of what a retained page showed, queued by changes to their inputs. Layout may measure several
// versions of a list before a frame is drawn; only the one drawn is a reading position or a message seen whole.
let view_read_tells : Array[() -> (() -> Unit)] = []

///|
/// Follow `read` in `owner`, telling `f` its latest value once the frame showing it has been drawn. Intermediate
/// values during layout are not observations of the screen. A value already told is not told again, and nothing
/// is told after its owner is gone. Use View::reacts for actions caused by state, rather than observations of a frame.
pub fn[T : Eq] read_drawn(owner : @view.View, read : () -> T, f : (T) -> Unit) -> Unit {
  let live = Ref(true)
  let pending = Ref(false)
  let latest : Ref[T?] = Ref(None)
  let told : Ref[T?] = Ref(None)
  owner.owns(fn() { live.val = false }) |> ignore
  owner.reacts(read, fn(value) {
    latest.val = Some(value)
    if !pending.val {
      pending.val = true
      view_read_tells.push(fn() {
        pending.val = false
        let shown = latest.val
        fn() {
          if live.val && shown != told.val {
            told.val = shown
            match shown { Some(value) => f(value); None => () }
          }
        }
      })
    }
  })
}

///|
fn view_read_drawn() -> Unit {
  let pending = view_read_tells.copy()
  view_read_tells.clear()
  // A reply can change the page again. Capture every observation before sending any, so another reader still
  // reports the frame just drawn; the reply's changes belong to the next frame.
  let shown = pending.map(fn(take) { @signals.untracked(take) })
  for tell in shown { @signals.untracked(tell) }
}
