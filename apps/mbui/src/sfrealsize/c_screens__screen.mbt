// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `screens` as `screen`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"screens","station":"ws/maple"}
  let messages =
    #|[[{"path":["screens",1,"line"],"set":"浏览器标签页 · 1280×800 · 由「修复 Android 上聊天列表滚动掉帧」打开 · 修复 Android 上聊天列表滚动掉帧 正在查看"},{"path":["screens",1,"title"],"set":"Checks · Pull request #5244 · acme/app"},{"path":["screens",1,"viewers"],"set":["修复 Android 上聊天列表滚动掉帧"]},{"path":["screens",1,"views"],"set":[{"id":"v-修复 Android 上聊天列表滚动掉帧-0","name":"修复 Android 上聊天列表滚动掉帧","device":"设备 agent","app":"agent","at":1791277200650,"ago":"刚刚","control":true,"here":false,"agent":true,"may":false}]}]]
  put_changes(asked, "screen", messages)
}
