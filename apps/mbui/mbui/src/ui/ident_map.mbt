// Who each node is (Node's `ident`) to the node: what each node built looks itself up in, several times, on every
// frame (Ctx::node_known). Open addressing over arrays, nothing made as it is set: MoonBit's Map keeps an entry made for
// each key set, and a node's ident is set again on each pass of each build.

///|
priv struct IdentMap {
  /// 0 empty, 1 held, 2 let go of (a tombstone: what was set past it is still found)
  mut state : FixedArray[Int]
  mut keys : FixedArray[Int]
  mut vals : FixedArray[Node?]
  /// how many are held, and how many slots are held or tombstones
  mut held : Int
  mut taken : Int
}

///|
fn IdentMap::new() -> IdentMap {
  let cap = 1024
  {
    state: FixedArray::make(cap, 0),
    keys: FixedArray::make(cap, 0),
    vals: FixedArray::make(cap, None),
    held: 0,
    taken: 0,
  }
}

///|
/// The first slot `k` is looked for at (the slots a power of two: the ident is a hash already, spread once more).
fn IdentMap::home(self : IdentMap, k : Int) -> Int {
  let h = k.reinterpret_as_uint() * 2654435769U
  (h ^ (h >> 16)).reinterpret_as_int() & (self.state.length() - 1)
}

///|
/// Where `k` is held, -1 where it is not.
fn IdentMap::find(self : IdentMap, k : Int) -> Int {
  let mask = self.state.length() - 1
  let mut at = self.home(k)
  while true {
    let s = self.state[at]
    if s == 0 {
      return -1
    }
    if s == 1 && self.keys[at] == k {
      return at
    }
    at = (at + 1) & mask
  }
  -1
}

///|
fn IdentMap::get(self : IdentMap, k : Int) -> Node? {
  let at = self.find(k)
  if at < 0 {
    None
  } else {
    self.vals[at]
  }
}

///|
fn IdentMap::set(self : IdentMap, k : Int, v : Node) -> Unit {
  let at = self.find(k)
  if at >= 0 {
    self.vals[at] = Some(v)
    return
  }
  if (self.taken + 1) * 2 > self.state.length() {
    self.grow()
  }
  let mask = self.state.length() - 1
  let mut at = self.home(k)
  while self.state[at] == 1 {
    at = (at + 1) & mask
  }
  if self.state[at] == 0 {
    self.taken = self.taken + 1
  }
  self.state[at] = 1
  self.keys[at] = k
  self.vals[at] = Some(v)
  self.held = self.held + 1
}

///|
fn IdentMap::remove(self : IdentMap, k : Int) -> Unit {
  let at = self.find(k)
  if at >= 0 {
    self.state[at] = 2
    self.vals[at] = None
    self.held = self.held - 1
  }
}

///|
fn IdentMap::clear(self : IdentMap) -> Unit {
  self.state.fill(0)
  self.vals.fill(None)
  self.held = 0
  self.taken = 0
}

///|
/// Laid out again, its tombstones gone: in twice the slots where it holds more than a quarter of them.
fn IdentMap::grow(self : IdentMap) -> Unit {
  let state = self.state
  let keys = self.keys
  let vals = self.vals
  let cap = if self.held * 4 > state.length() { state.length() * 2 } else { state.length() }
  self.state = FixedArray::make(cap, 0)
  self.keys = FixedArray::make(cap, 0)
  self.vals = FixedArray::make(cap, None)
  self.held = 0
  self.taken = 0
  for at in 0..<state.length() {
    if state[at] == 1 {
      match vals[at] {
        Some(v) => self.set(keys[at], v)
        None => ()
      }
    }
  }
}
