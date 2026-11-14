// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `settings` as `off`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"settings","scope":"ws"}
  let messages =
    #|[{"value":{"decisionsOn":4,"decisionsText":"4 台 station 已启用","hintNoReview":false,"hintReviewText":"只有 Willow、Studio、Cedar 开启了归档建议；Maple 上的 chat 不会提示。"}}]
  put_changes(asked, "off", messages)
}
