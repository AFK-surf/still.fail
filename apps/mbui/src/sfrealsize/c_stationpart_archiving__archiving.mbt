// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart archiving` as `archiving`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"archiving"}
  let messages =
    #|[[{"path":["lineText"],"set":"空闲就归档 · 7 天 · Slack：14 天"},{"path":["mode"],"set":"idle"},{"path":["modeNote"],"set":"空闲超过下面的天数就归档。只看状态，不读内容：chat 里提到但没做完的事，它看不出来。"},{"path":["reviewed"],"set":false}]]
  put_changes(asked, "archiving", messages)
}
