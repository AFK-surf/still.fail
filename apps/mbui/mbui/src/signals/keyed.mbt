// A set read by its members (SolidJS's createSelector): `has(k)` is whether k is in it, and what reads it is told only
// as k comes into it or leaves it, never as another does. So "is this row pointed at" changes as the pointer crosses
// its edge, not as it moves, and a row's change tells that row alone (docs/incremental.md, the model's 2).

///|
/// A set of keys, read by member.
pub struct Keyed[K] {
  priv members : Map[K, Bool]
  /// a signal for each key read (whether it is in), made as it is first read
  priv said : Map[K, Signal[Bool]]
}

///|
/// An empty one.
pub fn[K : Hash + Eq] keyed() -> Keyed[K] {
  { members: {}, said: {} }
}

///|
/// Whether `k` is in it: what reads it is told as `k` comes in or leaves, nothing else.
pub fn[K : Hash + Eq] Keyed::has(self : Keyed[K], k : K) -> Bool {
  let s = match self.said.get(k) {
    Some(s) => s
    None => {
      let s = signal(self.members.contains(k))
      self.said[k] = s
      s
    }
  }
  s.get()
}

///|
/// Whether `k` is in it, as it stands, read by nothing.
pub fn[K : Hash + Eq] Keyed::peek(self : Keyed[K], k : K) -> Bool {
  self.members.contains(k)
}

///|
/// It holds `ks` now, and nothing else: what read a key that came in or left is told, once, as all of them have
/// changed. The keys nothing reads any more are let go as they leave.
pub fn[K : Hash + Eq] Keyed::set(self : Keyed[K], ks : Array[K]) -> Unit {
  let now : Map[K, Bool] = {}
  for k in ks {
    now[k] = true
  }
  let left : Array[K] = []
  self.members.each(fn(k, _) { if !now.contains(k) { left.push(k) } })
  let came : Array[K] = []
  now.each(fn(k, _) { if !self.members.contains(k) { came.push(k) } })
  if left.is_empty() && came.is_empty() {
    return
  }
  start_batch()
  for k in left {
    self.members.remove(k)
    match self.said.get(k) {
      Some(s) =>
        if s.watched() {
          s.set(false)
        } else {
          self.said.remove(k)
        }
      None => ()
    }
  }
  for k in came {
    self.members[k] = true
    match self.said.get(k) {
      Some(s) => s.set(true)
      None => ()
    }
  }
  end_batch()
  // (what was read once and is read no more, kept by none: let go)
  if self.said.length() > 64 && self.said.length() > 4 * (self.members.length() + 1) {
    let unread : Array[K] = []
    self.said.each(fn(k, s) { if !s.watched() && !self.members.contains(k) { unread.push(k) } })
    for k in unread {
      self.said.remove(k)
    }
  }
}
