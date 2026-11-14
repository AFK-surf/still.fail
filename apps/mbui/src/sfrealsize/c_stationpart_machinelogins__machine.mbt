// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart machineLogins` as `machine`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"machineLogins"}
  let messages =
    #|[[{"path":[0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"quota","windows",0,"left"],"set":37}]]
  put_changes(asked, "machine", messages)
}
