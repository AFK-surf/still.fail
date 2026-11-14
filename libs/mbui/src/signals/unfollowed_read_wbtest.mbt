// A computed read while nothing follows it (no reader: an `untracked`, a reaction's `then`, a handler; nothing reading
// it). One that holds nothing keeps what it read, as alien-signals keeps it (rest_wbtest's "what holds nothing keeps
// what it read" as well). One whose reads reach what holds something (a resource told as its last reader leaves) keeps
// what it read linked for good too, the resource with it: what a Tester is told of (held_read_said, ui's
// held_read.mbt), the rule to come being that it lets go of what it read (not yet: the shipped page's tests leave a
// chat's subscription as they find it only while it does not, core_signal_wbtest's popped chat).

///|
test "a computed that holds nothing, read while nothing follows it, keeps what it read" {
  let source = signal(1)
  let worked = Ref(0)
  let rows = computed(fn(_) { source.get() })
  let at_foot = computed(fn(_) {
    worked.val += 1
    rows.get() > 0
  })
  assert_true(at_foot.untracked())
  assert_true(source.watched())
  assert_true(rows.watched())
  // (read again with nothing changed: not worked out again)
  assert_true(at_foot.untracked())
  assert_eq(worked.val, 1)
  source.set(0)
  assert_false(at_foot.untracked())
  assert_eq(worked.val, 2)
  at_foot.dispose()
  assert_false(source.watched())
}

///|
test "what a Tester is told: a computed holding something read from an untracked, where; not a scoped one's" {
  let told : Array[String] = []
  held_read_said.val = Some(fn(made, from) {
    let here = fn(l : SourceLoc) { l.to_string().contains("unfollowed_read_wbtest") }
    told.push(
      (if here(made) { "made here" } else { "made elsewhere" }) +
      (match from {
        Some(f) => if here(f) { ", read from here" } else { ", read from elsewhere" }
        None => ", read from nowhere said"
      }),
    )
  })
  let topic = signal(1)
  topic.on_unwatched(fn() {  })
  let holder = computed(fn(_) { topic.get() })
  let scoped = computed_scoped(fn(_) { topic.get() })
  untracked(fn() { holder.get() }) |> ignore
  scoped.untracked() |> ignore
  holder.dispose()
  held_read_said.val = None
  assert_eq(told, ["made here, read from here"])
}
