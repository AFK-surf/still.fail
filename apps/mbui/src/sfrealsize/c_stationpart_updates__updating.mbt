// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart updates` as `updating`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"updates"}
  let messages =
    #|[[{"path":[1,"state"],"set":"updating"}]]
  put_changes(asked, "updating", messages)
}
