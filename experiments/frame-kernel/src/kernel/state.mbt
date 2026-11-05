// A write belongs to a completed input transaction. Reading a cached query
// cannot borrow that permission, even by capturing a transaction in a closure.
// Existing signals only track dependencies here: their watches never run UI
// computation on a write. No page has to set an invalidation flag.

///|
struct Store {
  mut writing : Int
  mut serial : Int
  mut reading : Int
}

///|
struct Transaction {
  store : Store
  serial : Int
  at : Double
}

///|
struct Cell[T] {
  store : Store
  value : @signals.Signal[T]
  mut revision : Int
}

///|
struct Query[K, T] {
  store : Store
  watch : @signals.Watch
  read : (K) -> T
  mut key : K?
  mut kept : T?
  mut runs : Int
}

///|
#derive(Eq, Debug)
enum WriteFault {
  ClosedTransaction
  DifferentStore
  DuringQuery
}

///|
fn Store::new() -> Store {
  { writing: -1, serial: 0, reading: 0 }
}

///|
fn[T] Store::cell(self : Store, value : T, same : (T, T) -> Bool) -> Cell[T] {
  { store: self, value: @signals.signal(value, same~), revision: 0 }
}

///|
fn[T] Store::commit(self : Store, at : Double, f : (Transaction) -> T) -> T {
  guard self.reading == 0 else { abort("a query cannot commit model changes") }
  guard self.writing < 0 else { abort("input transactions cannot nest") }
  self.serial += 1
  self.writing = self.serial
  let tx : Transaction = { store: self, serial: self.serial, at }
  @signals.start_batch()
  let result = f(tx)
  self.writing = -1
  @signals.end_batch()
  result
}

///|
fn[T] Cell::get(self : Cell[T]) -> T {
  self.value.get()
}

///|
fn[T] Cell::try_set(self : Cell[T], tx : Transaction, value : T) -> WriteFault? {
  if !physical_equal(self.store, tx.store) { return Some(DifferentStore) }
  if self.store.reading > 0 { return Some(DuringQuery) }
  if self.store.writing != tx.serial { return Some(ClosedTransaction) }
  self.value.set(value)
  self.revision += 1
  None
}

///|
fn[T] Cell::set(self : Cell[T], tx : Transaction, value : T) -> Unit {
  match self.try_set(tx, value) {
    None => ()
    Some(ClosedTransaction) => abort("model write used a closed transaction")
    Some(DifferentStore) => abort("model write used another store's transaction")
    Some(DuringQuery) => abort("a query tried to write model state")
  }
}

///|
fn[K, T] Store::query(self : Store, read : (K) -> T) -> Query[K, T] {
  { store: self, watch: @signals.watch(fn() { }), read, key: None, kept: None, runs: 0 }
}

///|
fn[K : Eq, T] Query::get(self : Query[K, T], key : K) -> T {
  guard self.store.writing < 0 else { abort("queries observe committed inputs only") }
  // This slice caches root computations over cells, not other queries. A
  // general derived graph needs its own dependency edges before allowing that.
  guard self.store.reading == 0 else { abort("nested cached queries are not supported by this slice") }
  if self.key == Some(key) && !self.watch.is_stale() {
    if self.kept is Some(kept) { return kept }
  }
  self.store.reading += 1
  let value = self.watch.read(fn() { (self.read)(key) })
  self.store.reading -= 1
  self.runs += 1
  self.key = Some(key)
  self.kept = Some(value)
  value
}

///|
fn[K, T] Query::release(self : Query[K, T]) -> Unit {
  self.watch.stop()
  self.kept = None
  self.key = None
}
