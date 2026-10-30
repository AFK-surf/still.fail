// What the app keeps that changes from outside the hand (a call's answer, the host's, a timer) and what shows it
// follows, as it follows the core's topics (mbui/signals): a value is a signal of its own (@signals.Signal); a table or
// a list kept in place is one of these, a Map's or an Array's ways over what it holds and a signal of its changes
// beside them. Each read of it is followed (a part kept as it was drawn, a computed: built or worked out again once it
// changed), each change of it tells them; what is read as it is not (a copy, `peek`) is followed by nothing.

///|
/// A table that what reads it follows (a Map's ways).
pub struct LiveMap[K, V] {
  priv data : Map[K, V]
  priv changes : @signals.Signal[Int]
}

///|
pub fn[K : Hash + Eq, V] LiveMap::new() -> LiveMap[K, V] {
  { data: {}, changes: @signals.signal(0) }
}

///|
#callsite(autofill(loc))
fn live_changed(changes : @signals.Signal[Int], loc~ : SourceLoc) -> Unit {
  // (where it was changed, its caller's: what a watch says changed what it read, Watch::set_as_read)
  changes.set(@signals.untracked(fn() { changes.get() }) + 1, loc~)
}

///|
fn[K, V] LiveMap::read(self : LiveMap[K, V]) -> Map[K, V] {
  self.changes.get() |> ignore
  self.data
}

///|
pub fn[K : Hash + Eq, V] LiveMap::get(self : LiveMap[K, V], key : K) -> V? {
  self.read().get(key)
}

///|
pub fn[K : Hash + Eq, V] LiveMap::op_get(self : LiveMap[K, V], key : K) -> V {
  self.read()[key]
}

///|
pub fn[K : Hash + Eq, V] LiveMap::contains(self : LiveMap[K, V], key : K) -> Bool {
  self.read().contains(key)
}

///|
pub fn[K, V] LiveMap::length(self : LiveMap[K, V]) -> Int {
  self.read().length()
}

///|
pub fn[K, V] LiveMap::is_empty(self : LiveMap[K, V]) -> Bool {
  self.read().is_empty()
}

///|
pub fn[K, V] LiveMap::iter(self : LiveMap[K, V]) -> Iter[(K, V)] {
  self.read().iter()
}

///|
pub fn[K, V] LiveMap::iter2(self : LiveMap[K, V]) -> Iter2[K, V] {
  self.read().iter2()
}

///|
pub fn[K, V] LiveMap::keys(self : LiveMap[K, V]) -> Iter[K] {
  self.read().keys()
}

///|
pub fn[K, V] LiveMap::values(self : LiveMap[K, V]) -> Iter[V] {
  self.read().values()
}

///|
/// What it holds now, a copy: followed as it is read.
pub fn[K, V] LiveMap::copy(self : LiveMap[K, V]) -> Map[K, V] {
  self.read().copy()
}

///|
/// (`m[key] = value`: told as a change only when it held another; a value with no Eq is put with LiveMap::set)
pub fn[K : Hash + Eq, V : Eq] LiveMap::op_set(self : LiveMap[K, V], key : K, value : V) -> Unit {
  if self.data.get(key) != Some(value) {
    self.data[key] = value
    live_changed(self.changes)
  }
}

///|
#callsite(autofill(loc))
pub fn[K : Hash + Eq, V] LiveMap::set(self : LiveMap[K, V], key : K, value : V, loc~ : SourceLoc) -> Unit {
  self.data[key] = value
  live_changed(self.changes, loc~)
}

///|
#callsite(autofill(loc))
pub fn[K : Hash + Eq, V] LiveMap::remove(self : LiveMap[K, V], key : K, loc~ : SourceLoc) -> Unit {
  if self.data.contains(key) {
    self.data.remove(key)
    live_changed(self.changes, loc~)
  }
}

///|
#callsite(autofill(loc))
pub fn[K, V] LiveMap::clear(self : LiveMap[K, V], loc~ : SourceLoc) -> Unit {
  if !self.data.is_empty() {
    self.data.clear()
    live_changed(self.changes, loc~)
  }
}

///|
/// What holds `keep` kept, the rest let go.
#callsite(autofill(loc))
pub fn[K : Hash + Eq, V] LiveMap::retain(self : LiveMap[K, V], keep : (K, V) -> Bool, loc~ : SourceLoc) -> Unit {
  let gone = []
  for k, v in self.data {
    if !keep(k, v) {
      gone.push(k)
    }
  }
  if gone.length() > 0 {
    for k in gone {
      self.data.remove(k)
    }
    live_changed(self.changes, loc~)
  }
}

///|
/// A list that what reads it follows (an Array's ways).
pub struct LiveArray[T] {
  priv data : Array[T]
  priv changes : @signals.Signal[Int]
}

///|
pub fn[T] LiveArray::new() -> LiveArray[T] {
  { data: [], changes: @signals.signal(0) }
}

///|
fn[T] LiveArray::read(self : LiveArray[T]) -> Array[T] {
  self.changes.get() |> ignore
  self.data
}

///|
pub fn[T] LiveArray::op_get(self : LiveArray[T], i : Int) -> T {
  self.read()[i]
}

///|
pub fn[T] LiveArray::get(self : LiveArray[T], i : Int) -> T? {
  self.read().get(i)
}

///|
pub fn[T] LiveArray::length(self : LiveArray[T]) -> Int {
  self.read().length()
}

///|
pub fn[T] LiveArray::is_empty(self : LiveArray[T]) -> Bool {
  self.read().is_empty()
}

///|
pub fn[T] LiveArray::iter(self : LiveArray[T]) -> Iter[T] {
  self.read().iter()
}

///|
pub fn[T] LiveArray::iter2(self : LiveArray[T]) -> Iter2[Int, T] {
  self.read().iter2()
}

///|
pub fn[T] LiveArray::last(self : LiveArray[T]) -> T? {
  self.read().last()
}

///|
/// What it holds now, a copy: followed as it is read.
pub fn[T] LiveArray::copy(self : LiveArray[T]) -> Array[T] {
  self.read().copy()
}

///|
pub fn[T : Eq] LiveArray::contains(self : LiveArray[T], x : T) -> Bool {
  self.read().contains(x)
}

///|
pub fn[T] LiveArray::op_set(self : LiveArray[T], i : Int, x : T) -> Unit {
  self.data[i] = x
  live_changed(self.changes)
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::push(self : LiveArray[T], x : T, loc~ : SourceLoc) -> Unit {
  self.data.push(x)
  live_changed(self.changes, loc~)
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::remove(self : LiveArray[T], i : Int, loc~ : SourceLoc) -> T {
  let x = self.data.remove(i)
  live_changed(self.changes, loc~)
  x
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::clear(self : LiveArray[T], loc~ : SourceLoc) -> Unit {
  if !self.data.is_empty() {
    self.data.clear()
    live_changed(self.changes, loc~)
  }
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::retain(self : LiveArray[T], keep : (T) -> Bool, loc~ : SourceLoc) -> Unit {
  let n = self.data.length()
  self.data.retain(keep)
  if self.data.length() != n {
    live_changed(self.changes, loc~)
  }
}

///|
/// What it holds from now on: `all`, in place of what it held.
#callsite(autofill(loc))
pub fn[T] LiveArray::replace(self : LiveArray[T], all : Array[T], loc~ : SourceLoc) -> Unit {
  self.data.clear()
  self.data.append(all)
  live_changed(self.changes, loc~)
}

///|
pub fn[T] LiveArray::filter(self : LiveArray[T], f : (T) -> Bool) -> Array[T] {
  self.read().filter(f)
}

///|
pub fn[T, U] LiveArray::map(self : LiveArray[T], f : (T) -> U) -> Array[U] {
  self.read().map(f)
}

///|
pub fn[T, U] LiveArray::mapi(self : LiveArray[T], f : (Int, T) -> U) -> Array[U] {
  self.read().mapi(f)
}

///|
pub fn[T] LiveArray::any(self : LiveArray[T], f : (T) -> Bool) -> Bool {
  self.read().iter().any(f)
}

///|
pub fn[T] LiveArray::all(self : LiveArray[T], f : (T) -> Bool) -> Bool {
  self.read().iter().all(f)
}

///|
pub fn[T] LiveArray::each(self : LiveArray[T], f : (T) -> Unit) -> Unit {
  self.read().each(f)
}

///|
pub fn[T] LiveArray::eachi(self : LiveArray[T], f : (Int, T) -> Unit) -> Unit {
  self.read().eachi(f)
}

///|
pub fn[T] LiveArray::search_by(self : LiveArray[T], f : (T) -> Bool) -> Int? {
  self.read().search_by(f)
}

///|
pub fn[T, A] LiveArray::fold(self : LiveArray[T], init~ : A, f : (A, T) -> A) -> A {
  self.read().fold(init~, f)
}

///|
pub fn[T] LiveArray::rev_iter(self : LiveArray[T]) -> Iter[T] {
  self.read().rev_iter()
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::push_iter(self : LiveArray[T], xs : Iter[T], loc~ : SourceLoc) -> Unit {
  let n = self.data.length()
  self.data.push_iter(xs)
  if self.data.length() != n {
    live_changed(self.changes, loc~)
  }
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::append(self : LiveArray[T], xs : Array[T], loc~ : SourceLoc) -> Unit {
  if xs.length() > 0 {
    self.data.append(xs)
    live_changed(self.changes, loc~)
  }
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::insert(self : LiveArray[T], i : Int, x : T, loc~ : SourceLoc) -> Unit {
  self.data.insert(i, x)
  live_changed(self.changes, loc~)
}

///|
#callsite(autofill(loc))
pub fn[T] LiveArray::pop(self : LiveArray[T], loc~ : SourceLoc) -> T? {
  let x = self.data.pop()
  if x is Some(_) {
    live_changed(self.changes, loc~)
  }
  x
}

///|
/// Something in it changed in place (a field of one of its items): what reads it follows that too.
#callsite(autofill(loc))
pub fn[T] LiveArray::touched(self : LiveArray[T], loc~ : SourceLoc) -> Unit {
  live_changed(self.changes, loc~)
}

///|
/// Something in it changed in place (a field of one of its values): what reads it follows that too.
#callsite(autofill(loc))
pub fn[K, V] LiveMap::touched(self : LiveMap[K, V], loc~ : SourceLoc) -> Unit {
  live_changed(self.changes, loc~)
}

///|
pub fn[T : Eq] LiveArray::search(self : LiveArray[T], x : T) -> Int? {
  self.read().search(x)
}

///|
/// One holding `all` (taken as it is, not copied).
pub fn[T] LiveArray::from(all : Array[T]) -> LiveArray[T] {
  { data: all, changes: @signals.signal(0) }
}

///|
/// One holding `all` (taken as it is, not copied).
pub fn[K, V] LiveMap::from(all : Map[K, V]) -> LiveMap[K, V] {
  { data: all, changes: @signals.signal(0) }
}

///|
pub fn[T, U] LiveArray::filter_map(self : LiveArray[T], f : (T) -> U?) -> Array[U] {
  self.read().filter_map(f)
}

///|
/// `key` holding `value`, told as a change only when it held another (what is put each time it is worked out, the
/// same again, changes nothing for what reads it).
#callsite(autofill(loc))
pub fn[K : Hash + Eq, V : Eq] LiveMap::put(self : LiveMap[K, V], key : K, value : V, loc~ : SourceLoc) -> Unit {
  if self.data.get(key) != Some(value) {
    self.data[key] = value
    live_changed(self.changes, loc~)
  }
}

///|
/// Holding what `all` holds and nothing else, told as a change only when that differs from what it held.
#callsite(autofill(loc))
pub fn[K : Hash + Eq, V : Eq] LiveMap::put_all(self : LiveMap[K, V], all : Map[K, V], loc~ : SourceLoc) -> Unit {
  let same = self.data.length() == all.length() &&
    all.iter().all(fn(kv) { self.data.get(kv.0) == Some(kv.1) })
  if !same {
    self.data.clear()
    for k, v in all {
      self.data[k] = v
    }
    live_changed(self.changes, loc~)
  }
}
