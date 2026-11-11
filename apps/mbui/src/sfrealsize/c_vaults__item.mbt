// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `vaults` as `item`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"vaults","workspace":"ws"}
  let messages =
    #|[[{"path":["vaults"],"key":["id"],"patch":"plain","ops":[{"path":["items"],"set":37}]}]]
  put_changes(asked, "item", messages)
}
