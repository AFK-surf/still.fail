// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats` as `archived`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":false}
  let messages =
    #|[[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"drop":["ws/maple","k-maple-2"]},{"path":["items"],"key":["station","id"],"put":{"id":"k-studio-4","session":"k-studio-4","thread":4004,"title":"订单列表慢查询，explain 看一下","agents":[{"runtime":"codex","agentText":"GPT-6 Astra · high","maker":{"id":"openai"}}],"last":{"seq":44,"by":{"mine":false},"preview":"签名失败是证书链缺了中间证书。我把 DigiCert 的中间证书加进了 CI 的 keychain，重新打包签名通过，signtool verify /pa 也过了。"},"unread":false,"station":"ws/studio","stationName":"Studio","stationEmoji":"🎛️","people":[{"id":"sam.k@acme.dev","email":"sam.k@acme.dev","shown":{"name":"Sam Kowalski","picture":"https://avatars.slack-edge.com/2026-03-16/716206836_8f3c6a2b9d1e4f07c6a5_192.jpg","mine":false}}],"creator":{"id":"sam.k@acme.dev"},"peopleText":"Sam Kowalski 发起","pinned":false,"swipeArchive":true,"stateText":"已完成","stateLead":"done","stateRest":""},"before":null}]},{"path":["more"],"set":389}]]
  put_changes(asked, "archived", messages)
}
