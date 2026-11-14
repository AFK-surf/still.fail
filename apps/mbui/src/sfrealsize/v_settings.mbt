// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `settings` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"settings","scope":"ws"}
  let value =
    #|{"decisionsOn":5,"decisionsText":"5 台 station 已启用","hintNoReview":false,"hintReviewText":""}
  put(asked, value)
}
