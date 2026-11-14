// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart logins` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"logins"}
  let value =
    #|[]
  put(asked, value)
}
