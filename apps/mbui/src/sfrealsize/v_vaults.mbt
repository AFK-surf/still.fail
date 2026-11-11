// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `vaults` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"vaults","workspace":"ws"}
  let value =
    #|{"available":false,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"s1","ownerName":"左子健","mine":true,"members":[{"sub":"s1","name":"左子健"}],"station":"maple","stationName":"Maple","items":36,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false,"lasts":"chat"}],"requests":[{"id":"vr-2","vault":"plain","vaultName":"个人","item":"item-2","itemName":"Sentry auth token","lasts":"chat","session":"k-studio-13","chat":"新的模型选择器的交互稿","station":"studio","mode":"proxy","reason":"推送 PR 并打开 review","timeoutKind":"idle","timeoutSeconds":3600,"command":"gh pr create --fill","hosts":["api.github.com","github.com"],"at":1791275580000,"howText":"代理 · 限 api.github.com, github.com"},{"id":"vr-1","vault":"plain","vaultName":"个人","item":"item-1","itemName":"npm publish token","lasts":"hour","session":"k-willow-8","chat":"Review #5231：归档策略的默认值","station":"willow","mode":"proxy","reason":"推送 PR 并打开 review","timeoutKind":"idle","timeoutSeconds":3600,"command":"gh pr create --fill","hosts":["api.github.com","github.com"],"at":1791276120000,"howText":"代理 · 限 api.github.com, github.com"},{"id":"vr-0","vault":"plain","vaultName":"个人","item":"item-0","itemName":"GitHub token","lasts":"once","session":"k-maple-3","chat":"升级 Effect 到 4.0 并跑完全部测试","station":"maple","mode":"proxy","reason":"推送 PR 并打开 review","timeoutKind":"idle","timeoutSeconds":3600,"command":"gh pr create --fill","hosts":["api.github.com","github.com"],"at":1791276660000,"howText":"代理 · 限 api.github.com, github.com"}],"refused":[],"plain":true,"statusText":"3 个待批准","statusBad":true}
  put(asked, value)
}
