// Whether what reads now is a computed working itself out (computing): what refuses being read inside one (where
// mbui's view lays things out: Tree::layout_read) asks this; a computed caches what it read till that is told changed,
// and what is no signal is told to nothing.

///|
test "computing: inside a computed's getter alone; not at the top, in an effect, in a watch's read or in untracked" {
  let seen : Array[(String, Bool)] = []
  let s = @signals.signal(1)
  seen.push(("top", @signals.computing()))
  let c = @signals.computed(fn(_) {
    seen.push(("computed", @signals.computing()))
    seen.push(("untracked in it", @signals.untracked(fn() { @signals.computing() })))
    s.get() + 1
  })
  let stop = @signals.effect(fn() {
    seen.push(("effect", @signals.computing()))
    // (a computed read in an effect works itself out there: computing inside it, not after)
    seen.push(("read in it", c.get() > 0 && @signals.computing()))
  })
  let w = @signals.watch(fn() {  })
  w.read(fn() { seen.push(("watch", @signals.computing())) })
  stop()
  w.stop()
  seen.push(("after", @signals.computing()))
  assert_eq(seen, [
    ("top", false),
    ("effect", false),
    ("computed", true),
    ("untracked in it", false),
    ("read in it", false),
    ("watch", false),
    ("after", false),
  ])
}
