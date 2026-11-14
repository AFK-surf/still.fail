// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `lock` as `member`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"lock","workspace":"ws"}
  let messages =
    #|[[{"path":["members",3,"groups",2,"devices",0,"renewSoon"],"set":true}]]
  put_changes(asked, "member", messages)
}
