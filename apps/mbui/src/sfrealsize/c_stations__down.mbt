// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stations` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stations","scope":"ws"}
  let messages =
    #|[[{"path":[],"key":["station"],"patch":"ws/willow","ops":[{"path":["face"],"set":"offline"},{"path":["online"],"set":false},{"path":["problems"],"append":[{"key":"away","level":"red","text":"离线：在该机器上打开 still.fail 即可重新连接"}]},{"path":["stateBusy"],"set":false},{"path":["stateText"],"set":"刚刚在线"},{"path":["summary"],"set":"离线 · 刚刚"}]}]]
  put_changes(asked, "down", messages)
}
