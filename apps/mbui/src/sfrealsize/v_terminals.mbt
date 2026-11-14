// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `terminals` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"terminals","station":"ws/maple"}
  let value =
    #|{"terminals":[],"outdated":false,"open":true,"known":true}
  put(asked, value)
}
