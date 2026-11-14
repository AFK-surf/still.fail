// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `workspaceMarks` as `message`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"workspaceMarks"}
  let messages =
    #|[[{"path":["workspaces","ws","items",0,"at"],"set":1791277200650}]]
  put_changes(asked, "message", messages)
}
