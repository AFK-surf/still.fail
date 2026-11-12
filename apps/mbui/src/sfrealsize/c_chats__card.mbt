// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats` as `card`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":false}
  let messages =
    #|[[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"drop":["ws/willow","k-willow-4"]},{"path":["items"],"key":["station","id"],"put":{"id":"k-maple-6","session":"k-maple-6","thread":2006,"title":"Windows 安装包签名失败（signtool 0x800b0109）","agents":[{"runtime":"claude","agentText":"Opus 5.5 · xhigh","maker":{"id":"anthropic"}}],"last":{"seq":47,"by":{"mine":false},"preview":"需要你决定：周六上午 9 点做生产库迁移可以吗？"},"unread":true,"station":"ws/maple","stationName":"Maple","stationEmoji":"🍁","people":[{"id":"sam.k@acme.dev","email":"sam.k@acme.dev","shown":{"name":"Sam Kowalski","picture":"https://avatars.slack-edge.com/2026-03-16/716206836_8f3c6a2b9d1e4f07c6a5_192.jpg","mine":false}},{"id":"aiko@acme.dev","email":"aiko@acme.dev","shown":{"name":"Aiko Tanaka","picture":"https://avatars.slack-edge.com/2026-03-18/718208838_8f3c8a2b9d1e4f07c6a5_192.jpg","mine":false}},{"id":"sun.fei@acme.dev","email":"sun.fei@acme.dev","shown":{"name":"孙飞","mine":false}}],"creator":{"id":"sam.k@acme.dev"},"peopleText":"Sam Kowalski 发起 · Aiko Tanaka、孙飞","pinned":false,"swipeArchive":true,"stateText":"待处理 · 需要你决定：周六上午 9 点做生产库迁移可以吗？","stateLead":"decision","stateLeadText":"待处理","stateRest":" · 需要你决定：周六上午 9 点做生产库迁移可以吗？","tone":"wait"},"before":["ws/maple","k-maple-0"]}]}]]
  put_changes(asked, "card", messages)
}
