// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chat compact` as `message`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chat","station":"ws/maple","session":"k-maple-0","compact":true}
  let messages =
    #|[[{"path":["askClear"],"set":true},{"path":["lastEntry"],"set":301},{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":301,"thread":1001,"ts":"1001.000301","authorKind":"person","author":"lina@acme.dev","text":"好的，我先跑一遍测试再合。","words":[{"text":"好的，我先跑一遍测试再合。"}],"attachments":[],"quotes":[],"createdAt":1791277200650,"mine":false,"system":false,"by":{"name":"Lina Park"},"waiting":false,"time":{"createdAt":{"ago":"刚刚","full":"10/6 09:00:00"}}},"before":null},{"path":["thread","lastMessage","time","createdAt","ago"],"set":"刚刚"},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/6 09:00:00"}]]
  put_changes(asked, "message", messages)
}
