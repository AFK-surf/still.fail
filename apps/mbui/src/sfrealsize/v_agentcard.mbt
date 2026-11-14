// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `agentCard` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"agentCard","station":"ws/maple","key":"k-maple-0"}
  let value =
    #|{"work":"共工作 6 小时 0 分","cost":"$31.42","tokens":"输入 8.4M · 输出 211.4K","cache":{"percent":94,"text":"94%","level":"ok"},"context":{"percent":14,"text":"143.2K / 1M","level":"ok"},"jobs":"服务在线：dev server · 正在监控：watch CI #5244","latest":[{"key":"158","text":"Could you check whether the beta channel is on for your phone? The fix shipped in 0.1.7018 and your logs say 0.1.7012."},{"key":"159","text":"搜索"},{"key":"now","text":"思考中","now":true}],"attention":[],"tasks":[{"id":"t1","kind":"command","text":"pnpm test --watch","kindText":"命令","since":1791276600000},{"id":"t2","kind":"agent","text":"Review the migration script","kindText":"子代理","since":1791277080000}],"plan":[{"text":"复现掉帧","status":"completed"},{"text":"缓存行高","status":"completed"},{"text":"录前后对比","status":"in_progress"},{"text":"开 PR 等 CI","status":"pending"}],"planText":"已完成 2/4","workLine":"后台 2 · 清单 2/4：录前后对比","workMark":"后台 2 · 2/4","workMarkShort":"2 · 2/4","workMarkCount":"2"}
  put(asked, value)
}
