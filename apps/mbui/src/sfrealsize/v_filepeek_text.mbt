// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `filePeek text` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"filePeek","station":"ws/maple","key":"k-maple-0","path":"src/views/views.ts"}
  let value =
    #|{"kind":"text","path":"/Users/maple/src/app/src/views/views.ts","name":"views.ts","size":212331,"mtime":1791270000000,"type":"text/plain","lines":{"start":1,"text":["已经修好了：列表项的高度现在在第一次布局时就算好，不再在滚动中重新测量。我在 Pixel 8 上录了前后对比，掉帧从 23% 降到 1% 以下，PR #5244 等 CI。…","  日志轮转改成按天切了，保留 14 天，旧的压缩成 .gz。重启 station 之后看了一下 ~/.stillfail/logs，文件名是 station-2026-11-10.log，没问题。","    原因是 Socket Mode 的 ping 超时后我们只关了连接没有重新打开。改成按 backoff 重连（1s 起，最多 60s），本地断网 10 分钟再恢复，3 秒内连上。","      Effect 4.0 的升级跑完了：类型错误 112 处都改了，测试 2,431 个全部通过。有两处 Stream API 的语义变了，我写在 PR 描述里，需要你看一下是否接受。…","闪烁是因为第一帧拿不到缓存的列表，骨架和真实内容之间切了一次。改成先读设备上的缓存再决定画什么，录屏里已经看不到闪了。","  需要你决定：按模型拆分时，同一个模型在不同 runtime 上（Claude Code 和 OpenRouter）要合并成一行还是分开显示？两种我都做了截图。","    签名失败是证书链缺了中间证书。我把 DigiCert 的中间证书加进了 CI 的 keychain，重新打包签名通过，signtool verify /pa 也过了。…","      锁屏推送不显示正文是因为通知的 mutable-content 没设，扩展没被调用。修了之后在 iPhone 16 上测过，锁屏能看到消息前两行。","看完了 #5231，整体没问题。两个小建议：默认天数 7 天对 Slack 的对话太短；另外 reviewed 模式下没有说明为什么没归档。已在 PR 上留言。","  周报草稿写好了，放在 docs/weekly/2026-W45.md：本周发了 3 个 beta、1 个正式版，一次事故（relay 证书过期 22 分钟），下周重点是 iOS 上架。…","    慢查询的原因是 orders(created_at) 上没有和 tenant_id 组合的索引，全表扫了 1200 万行。加了组合索引后从 2.3s 降到 18ms，迁移脚本在 PR 里。","      自建 runner 上缓存命中率现在 87%，平均 CI 时间从 14 分钟降到 6 分 40 秒。还有 arm64 的 Android 构建没迁，等新机器到。"]},"time":{"mtime":{"at":1791270000000,"ago":"2 小时前","full":"10/6 07:00:00","until":"1 分钟内","past":true}}}
  put(asked, value)
}
