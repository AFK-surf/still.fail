// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatSearch` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatSearch","scope":"ws","query":"迁移","station":"ws/maple","limit":8,"elsewhere":true,"exclude":"k-maple-0"}
  let messages =
    #|[[{"path":["items"],"key":["station","id"],"patch":["ws/willow","k-willow-9"],"ops":[{"path":["offline"],"set":"Willow 离线"},{"path":["swipeArchive"],"remove":true},{"path":["swipeAsk"],"remove":true}]}]]
  put_changes(asked, "down", messages)
}
