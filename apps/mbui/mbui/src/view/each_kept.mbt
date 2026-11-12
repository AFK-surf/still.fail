// A row of View::each kept as its key leaves (its `keeps`): put by (View::park: held by no node, so not laid out,
// placed, drawn, pressed, focused or read out; what it binds at rest, @signals.rest: what is held while it is read let
// go of, nothing of it worked out again meanwhile) instead of let go, and taken in again (View::take_in, its item set,
// woken, put in its order by each_place) as its key is among the items again: the same nodes, as they were left. Let go
// as its key is no more kept, and with the each. Nothing else of it is its own: no way in or out (it is there already,
// or out of sight at once), no lifecycle but park, take_in and rest. What is due on the tree's timeline in it
// (View::at_moment) still comes due as it rests, and a way read by the clock is where the clock has it as it is woken
// (at_rest_today_wbtest.mbt), so a row taken in within its way shows that way where the clock is then.

///|
/// What an each keeps of the rows whose keys left: `keys_of` the keys kept, read where the items are read (a change of
/// it is a change of them, View::each); `keys` as it was read last; each row put by with what wakes it; the wakings due
/// as the change taking them in ends.
priv struct EachKept[K, T] {
  keys_of : () -> Array[K]
  mut keys : Array[K]
  put_by : Map[K, (View, @signals.Signal[T], () -> Unit)]
  wakes : Array[() -> Unit]
}

///|
fn[K : Hash + Eq, T] EachKept::new(keys_of : () -> Array[K]) -> EachKept[K, T] {
  { keys_of, keys: [], put_by: Map([]), wakes: [] }
}

///|
/// The row put by for key `k`, as its item `it` is among the items again: taken into `slot` (after what it holds: put in
/// its order as the change ends, each_place), its item set as it rests (worked out as it wakes), its waking due as the
/// change ends (each_kept_settle). None: none put by for it.
fn[K : Hash + Eq, T] each_kept_takes(
  slot : View,
  kept : EachKept[K, T]?,
  k : K,
  it : T,
) -> (View, @signals.Signal[T])? {
  guard kept is Some(e) && e.put_by.get(k) is Some((v, item, wake)) else { return None }
  e.put_by.remove(k)
  guard v.alive() else { return None }
  slot.take_in(v)
  item.set(it)
  e.wakes.push(wake)
  Some((v, item))
}

///|
/// Row `r` of key `k`, gone from the items, put by where its key is kept (before it is asked of any way out: it takes
/// none); whether it was.
fn[K : Hash + Eq, T] each_kept_parks(
  slot : View,
  kept : EachKept[K, T]?,
  k : K,
  r : (View, @signals.Signal[T]),
) -> Bool {
  guard kept is Some(e) && e.keys.contains(k) && r.0.alive() else { return false }
  let wake = slot.park(r.0)
  e.put_by[k] = (r.0, r.1, wake)
  true
}

///|
/// As a change of the each ends: those put by whose keys are no more kept let go (held by nothing, let go by nothing
/// else), and those taken in woken, each binding that let go of what it read or whose reads changed meanwhile worked
/// out anew, in their places.
fn[K : Hash + Eq, T] each_kept_settle(kept : EachKept[K, T]?) -> Unit {
  guard kept is Some(e) else { return }
  let gone = e.put_by.keys().filter(fn(k) { !e.keys.contains(k) }).collect()
  for k in gone {
    match e.put_by.get(k) {
      Some((v, _, _)) => {
        e.put_by.remove(k)
        v.let_go()
      }
      None => ()
    }
  }
  let wakes = e.wakes.copy()
  e.wakes.clear()
  for w in wakes {
    w()
  }
}

///|
/// All it put by let go, with the each.
fn[K, T] EachKept::let_go_all(self : EachKept[K, T]) -> Unit {
  let all = self.put_by.values().collect()
  self.put_by.clear()
  for r in all {
    r.0.let_go()
  }
}
