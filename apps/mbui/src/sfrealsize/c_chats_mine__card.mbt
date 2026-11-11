// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats mine` as `card`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":true,"limit":50}
  let messages =
    #|[[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"move":["ws/maple","k-maple-6"],"before":["ws/maple","k-maple-0"]},{"path":["items"],"key":["station","id"],"patch":["ws/maple","k-maple-6"],"ops":[{"path":["decision"],"set":{"seq":47,"options":[{"label":"改到周日上午"},{"label":"先不做"},{"label":"可以，周六 9 点","detail":"按计划停写 4 分钟","recommended":true}],"card":{"assignee":"me@x.com","type":"options","options":[{"label":"改到周日上午"},{"label":"先不做"},{"label":"可以，周六 9 点","detail":"按计划停写 4 分钟","recommended":true}]},"text":"待处理 · 需要你决定：周六上午 9 点做生产库迁移可以吗？"}},{"path":["last","preview"],"set":"需要你决定：周六上午 9 点做生产库迁移可以吗？"},{"path":["last","seq"],"set":47},{"path":["stateLead"],"set":"decision"},{"path":["stateLeadText"],"set":"待处理"},{"path":["stateRest"],"set":" · 需要你决定：周六上午 9 点做生产库迁移可以吗？"},{"path":["stateText"],"set":"待处理 · 需要你决定：周六上午 9 点做生产库迁移可以吗？"},{"path":["time","lastActiveAt","ago"],"set":"刚刚"},{"path":["time","lastActiveAt","full"],"set":"10/6 09:00:00"},{"path":["tone"],"set":"wait"}]}]}]]
  put_changes(asked, "card", messages)
}
