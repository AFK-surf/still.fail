// Flows run one after another in one program, as the package's run has them (moon test: one process, its files in its
// own order): what one leaves behind is never the next one's. Each pair here is one that the next did trip on.

///|
test "84-connect after 86-decisions: the decisions page the run before left open drops its draft in that run, not in this" {
  @sfreplay.orders(flow_86_decisions)
  @sfreplay.orders(flow_84_connect)
}

///|
test "02-home-new-chat after 67-lock-wait: Home's catching up the run before left showing is gone with that run" {
  @sfreplay.orders(flow_67_lock_wait)
  @sfreplay.orders(flow_02_home_new_chat)
}
