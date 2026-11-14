// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `messagePeek` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"messagePeek","station":"ws/maple","thread":2012,"seq":41}
  let value =
    #|{"author":"","text":"结论 列表掉帧的根因是每一帧都在重新测量行高：measure_row 在滚动时被调用了 1,800 次/秒。 做了什么 行高在第一次布局时算好并缓存，键是行的 id 和宽度； 宽度变化（旋转、分屏）时整表失效一次，而不是逐行； 头像图片解码挪到后台线程，主线程只拿结果。 val height = heights.getOrPut(row.id to width) { measure(row, width) } 结果 设备 之前掉帧 之后 Pixel 8 23.1% 0.6% Galaxy S24 17.4% 0.9% Redmi Note 13 41.0% 3.2% 录屏和 trace 在附件里。还有一个问题需要你决定：低端机上要不要把头像的圆角改成预先裁好的位图？能再省 1.5 ms/帧，但内存多 4 MB。 Here's what I found in the station worker's memory growth: RSS grows ~38 MB/hour with 6 chats open, and never comes back down; heap snapshots at 0 h, 2 h and 6 h show MdCache holding 41k entries at the end, 93% of them for archived chats; nothing evicts them: forget() is only called when a chat is deleted, never when it is archived. The fix (PR #5251): const cache = new Lru<string, Md>(500, (key) => kept.delete(key)); data.onArchived((station, key) => cache.dropWhere((k) => k.startsWith(${station}\\u0001${key}))); After it, RSS is flat at 212 MB over 6 hours with the same load. I also added a test that archives 1,000 chats and checks the cache stays at 500. One question: should the cap be per workspace or for the whole device? Per device is simpler, but a big workspace could push a small one's chats out. 迁移演练的完整记录： pg_dump --format=directory -j 8 导出 412 GB，用时 38 分钟； 新实例 Postgres 17，pg_restore -j 16，用时 1 小时 12 分钟； 逻辑复制追平增量，延迟稳定在 200 ms 以内； 切换：停写 → 等复制追平 → 改连接串 → 恢复写，停写 3 分 41 秒； 校验：每张表行数一致，抽样 10 万行逐列比对无差异。 发现的问题： orders 上有一个函数索引用了 to_char，17 里被标成了不安全，需要改成 immutable 的包装函数； 连接池 pgbouncer 1.21 和 17 的 SCRAM 有兼容问题，升到 1.23 解决。 正式迁移建议放在周六上午，预计停写 4 分钟以内。需要你确认时间，我来发公告。","time":{"at":{"at":1791259200000,"ago":"5 小时前","full":"10/6 04:00:00","until":"1 分钟内","past":true}}}
  put(asked, value)
}
