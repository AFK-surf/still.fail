// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart profiles` as `quota`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"profiles"}
  let messages =
    #|[[{"path":[3,"quota","checkedAt"],"set":1791277200650},{"path":[3,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":[3,"quota","time","checkedAt","at"],"set":1791277200650},{"path":[3,"quota","time","checkedAt","full"],"set":"10/6 09:00:00"},{"path":[3,"quota","windows",0,"left"],"set":96},{"path":[3,"quota","windows",0,"usedPercent"],"set":4}]]
  put_changes(asked, "quota", messages)
}
