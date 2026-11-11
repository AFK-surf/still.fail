// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `jobLog line` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"jobLog","station":"ws/maple","job":"job-maple-0","lines":1}
  let value =
    #|{"text":"2026-10-06T08:59:59.100Z ✔ src/views/views.test.ts › 修复 Android 上聊天列表滚动掉帧 (0 ms, 0 assertions)","outputAt":1791277198000,"last":"2026-10-06T08:59:59.100Z ✔ src/views/views.test.ts › 修复 Android 上聊天列表滚动掉帧 (0 ms, 0 assertions)","said":"最后输出 · 刚刚","runs":[{"text":"2026-10-06T08:59:59.100Z","dim":true},{"text":" "},{"text":"✔","fg":"2"},{"text":" src/views/views.test.ts › 修复 Android 上聊天列表滚动掉帧 "},{"text":"(0 ms, 0 assertions)","dim":true}]}
  put(asked, value)
}
