// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `vaultItems` as `item`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"vaultItems","workspace":"ws","vault":"plain"}
  let messages =
    #|[[{"path":["items"],"key":["id"],"put":{"id":"item-36","version":1,"at":1791277200650,"name":"Linear API key","kind":"token","listed":true,"modes":["proxy"],"hosts":["api.linear.app"],"lasts":"chat","kindText":"Token","agentText":"允许 agent 申请 · 代理 · api.linear.app","lineText":"代理 · api.linear.app","howText":"代理 · 限 api.linear.app","lastsText":"直到对话归档","shut":[{"key":"value","label":"值","value":"••••••••••••••••••••","secret":true,"mono":true}]},"before":"item-7"}]]
  put_changes(asked, "item", messages)
}
