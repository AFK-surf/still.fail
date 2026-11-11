// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats mine` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":true}
  let messages =
    #|[[{"path":["glyph","dim"],"set":2},{"path":["glyph","label"],"set":"5 台 station，3 台在线，3 台运行中，2 台离线"},{"path":["glyph","now"],"set":"8 个 agent 正在运行"},{"path":["glyph","online"],"set":3},{"path":["glyph","running"],"set":8},{"path":["glyph","summary"],"set":"5 台 station · 3 台运行中"},{"path":["glyph","working"],"set":3},{"path":["stations",1,"offline"],"set":"Willow 离线"},{"path":["trouble","text"],"set":"2 台 station 异常"},{"path":["trouble","station"],"remove":true}]]
  put_changes(asked, "down", messages)
}
