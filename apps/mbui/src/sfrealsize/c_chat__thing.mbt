// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chat` as `thing`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chat","station":"ws/maple","session":"k-maple-0"}
  let messages =
    #|[[{"path":["askClear"],"set":true},{"path":["lastEntry"],"set":301},{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":301,"thread":1001,"ts":"1001.000301","authorKind":"person","author":"lina@acme.dev","text":"截图和新的 PR：https://github.com/acme/app/pull/5250\n\n![](screenshot-301.png)","words":[{"text":"截图和新的 PR："},{"text":"https://github.com/acme/app/pull/5250","link":"https://github.com/acme/app/pull/5250","to":{"peek":"pull"}},{"text":"\n\n![](screenshot-301.png)"}],"attachments":[{"name":"screenshot-301.png","path":".stillfail/uploads/301-screenshot.png","size":251002,"width":1170,"height":2532,"thumbhash":"3OcRJYB4d3h/iIeHeEh3eIhw+j3A","owner":"k-maple-0"}],"quotes":[],"createdAt":1791277200650,"mine":false,"system":false,"by":{"name":"Lina Park"},"waiting":false,"time":{"createdAt":{"ago":"刚刚","full":"10/6 09:00:00"}}},"before":null},{"path":["thread","lastMessage","time","createdAt","ago"],"set":"刚刚"},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/6 09:00:00"}]]
  put_changes(asked, "thing", messages)
}
