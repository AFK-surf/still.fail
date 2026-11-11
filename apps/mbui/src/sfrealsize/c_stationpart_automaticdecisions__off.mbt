// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart automaticDecisions` as `off`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"automaticDecisions"}
  let messages =
    #|[[{"path":["settings","completion","enabled"],"set":false}]]
  put_changes(asked, "off", messages)
}
