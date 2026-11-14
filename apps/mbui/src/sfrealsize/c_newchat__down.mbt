// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `newChat` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"newChat","scope":"ws"}
  let messages =
    #|[[{"path":["stations"],"key":["station"],"drop":"ws/willow"}]]
  put_changes(asked, "down", messages)
}
