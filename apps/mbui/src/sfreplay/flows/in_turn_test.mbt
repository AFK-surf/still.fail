// Flows run one after another in one program, as the package's run has them (moon test: one process, its files in its
// own order): what one leaves behind is never the next one's. Each pair here is one that the next did trip on.

///|
test "84-connect after 86-decisions: the decisions page the run before left open drops its draft in that run, not in this" {
  @sfreplay.orders(fn(seed) { flow_86_decisions(seed) })
  @sfreplay.orders(fn(seed) { flow_84_connect(seed) })
}

///|
test "02-home-new-chat after 67-lock-wait: Home's catching up the run before left showing is gone with that run" {
  @sfreplay.orders(fn(seed) { flow_67_lock_wait(seed) })
  @sfreplay.orders(fn(seed) { flow_02_home_new_chat(seed) })
}
