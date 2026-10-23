// still.fail's Home over made-up chats, with no core (src/sfapp/fixture.mbt, chat_fixture.mbt): what the screenshots
// compare (scripts/shots.sh home, web-home, chat, web-chat) on every run the same. MBUI_FIXTURE (?MBUI_FIXTURE= on
// the web) picks what it shows: home (the default), signin, loading, empty; chat, chat-loading, chat-long (the first
// row's chat open over Home); files, drive…, reader… (the drive's pages, src/sfapp/drive_fixture.mbt); newchat,
// newchat-station, newchat-model (a new chat, its sheets), home-bars (the bottom bar's panel of the other bars),
// home-sheet (the workspaces' sheet), place (the 文件 place); settings, settings-<page> (a page of the settings over
// it: src/sfapp/settings/fixture.mbt), -dark after either for the dark theme; chat-flash, chat-flash-mine (the chat
// opened at a message from a notification, flashing), settings-notify-off (settings, notifications off); chat-cards,
// chat-answering (the chat's card answered and 保留 failed a moment ago; an option under way); chat-screens (links to a
// station's screens and its 共享调试 as their cards, a tab's live).

///|
fn main {
  // no core here: the real core's answers to its pure calls, kept (src/sfkept)
  @sf.kept_call.val = Some(@sfkept.answer)
  // MBUI_DARK=1: the dark theme
  if @ui.env("MBUI_DARK") == "1" {
    @sf.set_dark(Some(true))
  }
  let mode = @ui.env("MBUI_FIXTURE")
  // json: a screen as the core's JSON gives it (MBUI_FIXTURE_JSON, or _B64: client/fixtures/screens, the file still.fail's
  // Android app draws it from too; scripts/android-ref.sh), its pages opened as it says
  let src = if mode == "json" {
    @sfapp.fixture_json(@hostapi.env_text("MBUI_FIXTURE_JSON"))
  } else {
    let src = @sfapp.fixture(mode)
    // what the mode opens over Home before the first frame (src/sfapp/fixture.mbt: src/sfscreens opens the same)
    @sfapp.open_fixture_mode(mode)
    src
  }
  // the faces the app carries (code's JetBrains Mono), as the app has them
  @sf.give_faces()
  @sfapp.host_setup()
  @ui.run("still.fail", fn(c) { @sfapp.view(c, src) })
}
