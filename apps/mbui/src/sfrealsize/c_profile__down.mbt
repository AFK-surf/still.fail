// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `profile` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"profile","scope":"ws","station":"ws/maple","id":"claude-maple-0"}
  let messages =
    #|[[{"path":["places",1,"online"],"set":false},{"path":["places",1,"state"],"remove":true},{"path":["stations",1,"online"],"set":false}]]
  put_changes(asked, "down", messages)
}
