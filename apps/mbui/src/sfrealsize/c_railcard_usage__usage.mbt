// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `railCard usage` as `usage`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"railCard","scope":"ws","place":"usage"}
  let messages =
    #|[[{"path":["days",6,"share"],"set":0.7242118576099699},{"path":["head"],"set":"近 7 天折合 $7,965"}]]
  put_changes(asked, "usage", messages)
}
