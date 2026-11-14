// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `station` as `off`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"station","scope":"ws","station":"ws/maple"}
  let messages =
    #|[[{"path":["overview","archiving","lineText"],"set":"按模型判断，但归档建议没开：现在不会自动归档"},{"path":["overview","archiving","modeNote"],"set":"空闲超过下面的天数，并且归档建议判断为没有后续事项，才归档。 这台 station 没开归档建议，所以现在不会自动归档任何 chat。"},{"path":["overview","archiving","reviewText"],"set":"未开启"},{"path":["overview","archiving","stalled"],"set":true},{"path":["overview","machineLogins",0,"quota","resets",1,"text"],"set":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用"},{"path":["overview","profiles",0,"quota","resets",1,"text"],"set":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用"},{"path":["overview","profiles",2,"quota","resets",1,"text"],"set":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用"},{"path":["overview","profiles",4,"quota","resets",0,"text"],"set":"4 天 23 小时后到期"}]]
  put_changes(asked, "off", messages)
}
