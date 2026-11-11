// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `railCard` as `card`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"railCard","scope":"ws","place":"chats"}
  let messages =
    #|[[{"path":["stats",0,"value"],"set":"86"},{"path":["stats",2,"value"],"set":"37"}]]
  put_changes(asked, "card", messages)
}
