// A replay takes what its core says as the app does on a device (sfcore's listen, both): a topic's change and the
// answers of the calls sfapp's core_taking names as they come, not left for the frame. Replayed otherwise, every
// message waits for a frame that a device's would not, and what the replays find of when things happen is of an app
// no device runs (the coordinator of the migration, 2026-11-11).

///|
test "a replay takes the core's messages as a device does" {
  let f = @sfreplay.Flow::start(@sfreplay.trace("send-text"))
  assert_true(@ui.message_said_on("core"))
  let (said, unread, _) = @sfapp.core_taking()
  for name in said + unread {
    assert_true(@core.taken_as_they_come(name), msg=name)
  }
  ignore(f)
  @core.Replay::detach()
}
