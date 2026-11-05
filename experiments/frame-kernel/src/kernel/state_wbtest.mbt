///|
test "a projection cannot mutate state through a captured transaction" {
  let store = Store::new()
  let count = store.cell(0, fn(a, b) { a == b })
  let tx = store.commit(100.0, fn(tx) { count.set(tx, 1); tx })
  assert_eq(tx.at, 100.0)
  assert_eq(count.try_set(tx, 7), Some(ClosedTransaction))
  let query = store.query(fn(_ : Unit) {
    let rejected = count.try_set(tx, 9)
    (count.get(), rejected)
  })
  assert_eq(query.get(()), (1, Some(DuringQuery)))
  assert_eq(count.get(), 1)
  query.release()
}

///|
test "writes invalidate only queries that read them and merge until observed" {
  let store = Store::new()
  let one = store.cell(1, fn(a, b) { a == b })
  let two = store.cell(2, fn(a, b) { a == b })
  let choose_first = store.cell(true, fn(a, b) { a == b })
  let query = store.query(fn(_ : Unit) {
    if choose_first.get() { one.get() } else { two.get() }
  })
  assert_eq(query.get(()), 1)
  store.commit(10.0, fn(tx) { two.set(tx, 20) })
  assert_eq(query.get(()), 1)
  assert_eq(query.runs, 1)
  store.commit(20.0, fn(tx) { one.set(tx, 3); one.set(tx, 4) })
  assert_eq(query.get(()), 4)
  assert_eq(query.runs, 2)
  store.commit(30.0, fn(tx) { choose_first.set(tx, false) })
  assert_eq(query.get(()), 20)
  store.commit(40.0, fn(tx) { one.set(tx, 50) })
  assert_eq(query.get(()), 20)
  assert_eq(query.runs, 3)
  query.release()
}

///|
test "a transaction cannot write into another model" {
  let a = Store::new()
  let b = Store::new()
  let value = b.cell(1, fn(a, b) { a == b })
  let rejected = a.commit(10.0, fn(tx) { value.try_set(tx, 2) })
  assert_eq(rejected, Some(DifferentStore))
  assert_eq(value.get(), 1)
}
