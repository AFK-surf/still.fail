// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationUpdates` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationUpdates","scope":"ws"}
  let messages =
    #|[{"value":{"items":[],"offered":0,"labelText":"","titleText":"Station 更新"}}]
  put_changes(asked, "down", messages)
}
