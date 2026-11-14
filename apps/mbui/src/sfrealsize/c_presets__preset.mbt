// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `presets` as `preset`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"presets","station":"ws/maple"}
  let messages =
    #|[[{"path":["presets",1,"instructions"],"set":"生产环境的改动先在 staging 跑一遍，改动前在 #infra 说一声。改完在 #infra 贴 diff。"},{"path":["presets",1,"updatedAt"],"set":1791277200650}]]
  put_changes(asked, "preset", messages)
}
