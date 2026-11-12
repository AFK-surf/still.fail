///|
/// How the app takes what its core says (sfcore's listen, on a device and in a replay alike): the calls whose answers
/// change only signals (a draft's words told and a ref asked at the caret as each key is typed, sfbase's calls_said),
/// those whose answers nobody reads (a remote screen's acknowledgements), and the calls whose values change nothing a
/// frame reads (a remote screen's frames and sound, sfpages' screen.mbt).
pub fn core_taking() -> (Array[String], Array[String], Array[(String, (Json) -> Bool)]) {
  (@sfbase.calls_said(), @sfpages.screen_unread_calls(), [("screen.view", @sfpages.screen_value_quiet)])
}
