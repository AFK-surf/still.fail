// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `station` as `session`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"station","scope":"ws","station":"ws/maple"}
  let messages =
    #|[[{"path":["overview","machineLogins",0,"quota","resets",1,"text"],"set":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用"},{"path":["overview","profiles",0,"quota","resets",1,"text"],"set":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用"},{"path":["overview","profiles",2,"quota","resets",1,"text"],"set":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用"},{"path":["overview","profiles",4,"quota","resets",0,"text"],"set":"4 天 23 小时后到期"}]]
  put_changes(asked, "session", messages)
}
