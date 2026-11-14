// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `newChat` as `carried`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"newChat","scope":"ws"}
  let messages =
    #|[[{"path":["presets",2,"name"],"set":"官网 · 文案"}]]
  put_changes(asked, "carried", messages)
}
