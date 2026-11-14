// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chat compact` as `screen`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chat","station":"ws/maple","session":"k-maple-0","compact":true}
  let messages =
    #|[[{"path":["screens",1,"line"],"set":"浏览器标签页 · 1280×800 · 由「修复 Android 上聊天列表滚动掉帧」打开 · 修复 Android 上聊天列表滚动掉帧 正在查看"},{"path":["screens",1,"title"],"set":"Checks · Pull request #5244 · acme/app"}]]
  put_changes(asked, "screen", messages)
}
