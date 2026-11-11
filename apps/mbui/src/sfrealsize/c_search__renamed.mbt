// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `search` as `renamed`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"search","scope":"ws","query":"迁移"}
  let messages =
    #|[[{"path":["items"],"key":["station","id"],"drop":["ws/studio","k-studio-15"]},{"path":["items"],"key":["station","id"],"put":{"id":"k-maple-7","session":"k-maple-7","thread":2007,"title":"迁移演练：Postgres 15 → 17 切换","agents":[{"runtime":"codex","agentText":"GPT-6 Astra · high","maker":{"id":"openai"}}],"last":{"seq":47,"by":{"mine":false},"preview":"锁屏推送不显示正文是因为通知的 mutable-content 没设，扩展没被调用。修了之后在 iPhone 16 上测过，锁屏能看到消息前两行。"},"unread":false,"station":"ws/maple","stationName":"Maple","stationEmoji":"🍁","time":{"lastActiveAt":{"ago":"5 小时前","full":"10/6 04:12:00"}},"people":[{"id":"liu.yang@acme.dev","email":"liu.yang@acme.dev","shown":{"name":"刘洋","mine":false}},{"id":"he.jing@acme.dev","email":"he.jing@acme.dev","shown":{"name":"何静","mine":false}}],"creator":{"id":"liu.yang@acme.dev"},"peopleText":"刘洋 发起 · 何静","pinned":false,"swipeArchive":true,"swipeAsk":"这是刘洋发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。","stateText":"已完成","stateLead":"done","stateRest":"","mayShare":true,"mayPublish":true},"before":["ws/ash","k-ash-6"]}]]
  put_changes(asked, "renamed", messages)
}
