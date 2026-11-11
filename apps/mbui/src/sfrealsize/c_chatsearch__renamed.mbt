// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatSearch` as `renamed`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatSearch","scope":"ws","query":"迁移","station":"ws/maple","limit":8,"elsewhere":true,"exclude":"k-maple-0"}
  let messages =
    #|[[{"path":["items"],"key":["station","id"],"drop":["ws/studio","k-studio-15"]},{"path":["items"],"key":["station","id"],"put":{"id":"k-maple-77","session":"k-maple-77","thread":2077,"title":"迁移演练：Postgres 15 → 17 切换","agents":[{"runtime":"claude","agentText":"Opus 5.5 · xhigh","maker":{"id":"anthropic"}}],"last":{"seq":117,"by":{"mine":false},"preview":"需要你决定：按模型拆分时，同一个模型在不同 runtime 上（Claude Code 和 OpenRouter）要合并成一行还是分开显示？两种我都做了截图。"},"unread":false,"connect":"c-slack-1","station":"ws/maple","stationName":"Maple","stationEmoji":"🍁","originText":"Slack · Acme · #android","originKind":"slack","time":{"lastActiveAt":{"ago":"10月4日 04:22","full":"10/4 04:22:00"}},"people":[{"id":"slack:c-slack-1:U06W1X2Y3Z4","shown":{"name":"chenyu","picture":"https://avatars.slack-edge.com/2026-03-15/715205835_8f3c5a2b9d1e4f07c6a5_192.jpg","mine":false}},{"id":"liu.yang@acme.dev","email":"liu.yang@acme.dev","shown":{"name":"刘洋","mine":false}}],"creator":{"id":"slack:c-slack-1:U06W1X2Y3Z4"},"peopleText":"chenyu 发起 · 刘洋","pinned":true,"swipeArchive":true,"swipeAsk":"这是chenyu发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。","stateText":"已完成","stateLead":"done","stateRest":"","mayShare":true,"mayPublish":true,"slackUrl":"https://acme-dev.slack.com/archives/C05ENG0001/p179477000077","slackApp":"slack://channel?team=T04ACME0001&id=C05ENG0001&message=17947700.0077"},"before":["ws/ash","k-ash-6"]}]]
  put_changes(asked, "renamed", messages)
}
