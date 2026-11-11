// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `lock` as `approved`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"lock","workspace":"ws"}
  let messages =
    #|[[{"path":["members",1,"groups",0,"appText"],"set":"其他"},{"path":["members",1,"groups",0,"devices"],"set":[{"id":"dev-s2-tablet","kind":"app","label":"ios still.fail · Lina Park 的 iPad Pro","signs":true,"older":false,"mine":false,"renewSoon":false,"recent":false,"lastSeen":1791277200,"usedText":"一天内使用过","removable":false,"nameText":"ios still.fail · Lina Park 的 iPad Pro","fullText":"ios still.fail · Lina Park 的 iPad Pro","metaText":"一天内使用过 · 受信任"},{"id":"dev-s2-phone","kind":"app","label":"android still.fail · Lina Park 的 Pixel 8","signs":true,"older":false,"mine":false,"renewSoon":false,"recent":false,"lastSeen":1791245524,"usedText":"一天内使用过","removable":false,"nameText":"android still.fail · Lina Park 的 Pixel 8","fullText":"android still.fail · Lina Park 的 Pixel 8","metaText":"一天内使用过 · 受信任"}]},{"path":["members",1,"groups",1,"appText"],"set":"macos still.fail 桌面版"},{"path":["members",1,"groups",1,"devices",0,"fullText"],"set":"Lina Park 的 MacBook Pro · macos still.fail 桌面版"},{"path":["members",1,"groups",1,"devices",0,"id"],"set":"dev-s2-mac"},{"path":["members",1,"groups",1,"devices",0,"label"],"set":"macos still.fail 桌面版 · Lina Park 的 MacBook Pro"},{"path":["members",1,"groups",1,"devices",0,"lastSeen"],"set":1791253443},{"path":["members",1,"groups",1,"devices",0,"nameText"],"set":"Lina Park 的 MacBook Pro"},{"path":["signers"],"set":25}]]
  put_changes(asked, "approved", messages)
}
