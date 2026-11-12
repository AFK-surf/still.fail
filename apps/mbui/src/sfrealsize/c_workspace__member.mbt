// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `workspace` as `member`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"workspace","workspace":"ws"}
  let messages =
    #|[[{"path":["members"],"append":[{"sub":"s13","email":"lin.xiao@acme.dev","name":"林晓","role":"member","picture":""}]}]]
  put_changes(asked, "member", messages)
}
