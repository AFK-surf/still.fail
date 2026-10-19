// still.fail's Home over made-up chats, with no core (src/sfapp/fixture.mbt, chat_fixture.mbt): what the screenshots
// compare (scripts/shots.sh home, web-home, chat, web-chat) on every run the same. MBUI_FIXTURE (?MBUI_FIXTURE= on
// the web) picks what it shows: home (the default), signin, loading, empty; chat, chat-loading, chat-long (the first
// row's chat open over Home); files, drive…, reader… (the drive's pages, src/sfapp/drive_fixture.mbt); newchat,
// newchat-station, newchat-model (a new chat, its sheets), home-bars (the bottom bar's panel of the other bars),
// home-sheet (the workspaces' sheet), place (the 文件 place); settings, settings-<page> (a page of the settings over
// it: src/sfapp/settings/fixture.mbt), -dark after either for the dark theme.

///|
fn main {
  // MBUI_DARK=1: the dark theme
  if @host.env("MBUI_DARK") == "1" {
    @sf.set_dark(Some(true))
  }
  let mode = @host.env("MBUI_FIXTURE")
  let src = @sfapp.fixture(mode)
  if mode.has_prefix("chat") {
    @sfapp.open_chat({
      station: "ws1/st1",
      session: "s-c1",
      title: "整理发布清单",
      station_name: "Studio",
    })
  }
  // the drive's pages (src/sfapp/drive_fixture.mbt): files, drive…, reader…
  @sfapp.open_drive_fixture(mode)
  // slice 8's (src/sfapp/decide_fixture.mbt): the 奏 page, a history, a chat's sheets
  @sfapp.open_fixture(mode)
  // a new chat (with its sheets), the bar's panel, a place: newchat_fixture.mbt
  @sfapp.open_mode(mode)
  if mode.has_prefix("settings") {
    @sfapp.open_setting(@settings.fixture_page(mode))
  }
  @ui.run("still.fail", fn(c) { @sfapp.view(c, src) })
}
