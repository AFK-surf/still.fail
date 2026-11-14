// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart archiving` as `off`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"archiving"}
  let messages =
    #|[[{"path":["lineText"],"set":"按模型判断，但归档建议没开：现在不会自动归档"},{"path":["modeNote"],"set":"空闲超过下面的天数，并且归档建议判断为没有后续事项，才归档。 这台 station 没开归档建议，所以现在不会自动归档任何 chat。"},{"path":["reviewText"],"set":"未开启"},{"path":["stalled"],"set":true}]]
  put_changes(asked, "off", messages)
}
