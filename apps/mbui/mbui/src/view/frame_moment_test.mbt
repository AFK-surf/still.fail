// A frame lays out what it shows as of its own moment, however often what it tells while it is laid out asks the time
// (2026-11-05: the window's tree read the host's clock, which goes on as it is read, for each change a size it told
// set going; each moved what was leaving a little further, its size told again, laid out again inside the pass before:
// thousands deep on an emulator as a chat was left, its GL thread out of stack).

///|
test "a size told as it shrinks while leaving, a part shown by it: one frame lays out once, at the frame's moment, whatever the clock says as it is asked" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let now = Ref(0.0)
  let reads = Ref(0)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        let card = Ref(None)
        o.show(
          fn() { on.get() },
          fn(v) {
            card.val = Some(v)
            v.width(Is(Some(100.0))).height(By(fn() { Some(100.0 * (1.0 - v.going())) })) |> ignore
          },
          leave=300.0,
        )
        // (a part shown while the card is laid out taller than 10: what reads its size, made again as it is told)
        o.show(
          fn() {
            match card.val {
              Some(c) => c.laid_size_told().map(fn(z) { z.1 }).unwrap_or(0.0) > 10.0
              None => false
            }
          },
          fn(m) { m.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore },
        )
      })
      |> ignore
    },
    // (the host's clock: a millisecond on each time it is asked, as a real one goes on between two asks)
    time=fn() {
      reads.val += 1
      now.val += 1.0
      now.val
    },
  )
  t.frame(390.0, 844.0, now=0.0) |> ignore
  t.frame(390.0, 844.0, now=16.0) |> ignore
  on.set(false)
  @view.laid_out_nesting_most() |> ignore
  t.frame(390.0, 844.0, now=32.0) |> ignore
  t.frame(390.0, 844.0, now=48.0) |> ignore
  let deep = @view.laid_out_nesting_most()
  t.dispose()
  assert_true(deep <= 3, msg="layout passes \{deep} deep in each other")
}
///|
test "a frame lays out at the moment it is given, the host later by then: what it tells as it is laid out does not move it to the host's now" {
  let host_now = Ref(0.0)
  let host_reads = Ref(0)
  let seen : Ref[(Double, Double)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(child) {
        child.width(Is(Some(80.0)))
        .height(By(fn() { Some(20.0 + root.tree.drawn_at() / 10.0) }))
        .shrink(Is(0.0)) |> ignore
        child.reacts(fn() { child.laid_size_told() }, fn(size) {
          seen.val = size
        })
      }) |> ignore
    },
    time=fn() {
      host_reads.val += 1
      host_now.val
    },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  host_reads.val = 0
  // The host can be later by the time a frame does its work. Its wall clock is
  // not a new event, and observing layout must not move this frame to it.
  host_now.val = 200.0
  tree.at(100.0)
  tree.frame(390.0, 844.0, now=100.0) |> ignore

  assert_eq(tree.logic_at(), 100.0)
  assert_eq(tree.drawn_at(), 100.0)
  assert_eq(seen.val, Some((80.0, 30.0)))
  assert_eq(host_reads.val, 0)
}
