// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `profiles` as `quota`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"profiles","scope":"ws"}
  let messages =
    #|[[{"path":["items",18,"profile","quota","windows",0,"left"],"set":96}]]
  put_changes(asked, "quota", messages)
}
