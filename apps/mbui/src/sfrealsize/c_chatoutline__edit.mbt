// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatOutline` as `edit`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatOutline","station":"ws/maple","thread":2002}
  let messages =
    #|[[{"path":["held"],"set":1601},{"path":["of"],"set":1601}]]
  put_changes(asked, "edit", messages)
}
