// What a scope owns at rest (rest): a watch whose read holds something outside (a resource told as its last reader
// leaves) lets go of it, the resource told; one that holds nothing keeps what it read, told nothing and nothing of it
// worked out while at rest, and as it wakes is told only where what it read changed meanwhile.

///|
/// Two watches made in one scope (its node): one reading `plain` through a computed (how many times it was worked out
/// in `worked`), one reading `held` (told as its last reader leaves); how many times each was told.
priv struct RestCase {
  owner : ReactiveNode
  plain : Signal[Int]
  held : Signal[Int]
  worked : Ref[Int]
  plain_told : Ref[Int]
  held_told : Ref[Int]
  released : Ref[Int]
}

///|
fn rest_case() -> RestCase {
  let plain = signal(0)
  let held = signal(0)
  let released = Ref(0)
  held.on_unwatched(fn() { released.val += 1 })
  let worked = Ref(0)
  let doubled = computed(fn(_) {
    worked.val += 1
    plain.get() * 2
  })
  let plain_told = Ref(0)
  let held_told = Ref(0)
  let owner : Ref[ReactiveNode?] = Ref(None)
  effect_scope(fn() {
    owner.val = active_sub()
    let p = watch(fn() { plain_told.val += 1 })
    p.read(fn() { doubled.get() }) |> ignore
    let h = watch(fn() { held_told.val += 1 })
    h.read(fn() { held.get() }) |> ignore
  })
  |> ignore
  { owner: owner.val.unwrap(), plain, held, worked, plain_told, held_told, released }
}

///|
test "at rest: what holds something lets go of it, what holds nothing keeps what it read, told as it wakes only where that changed" {
  let c = rest_case()
  let wake = rest(c.owner)
  // (the resource let go of as the watch reading it rests; the other's read kept)
  assert_eq((c.released.val, c.held.watched()), (1, false))
  assert_true(c.plain.watched())
  // (woken with nothing changed: the one that let go told, to read anew; the other not)
  wake()
  assert_eq((c.plain_told.val, c.held_told.val), (0, 1))
}

///|
test "at rest: what it kept, changed meanwhile, is told nothing and worked out never till it wakes, then told once" {
  let c = rest_case()
  let wake = rest(c.owner)
  let worked = c.worked.val
  c.plain.set(1)
  c.plain.set(2)
  assert_eq((c.plain_told.val, c.worked.val - worked), (0, 0))
  wake()
  assert_eq(c.plain_told.val, 1)
}
