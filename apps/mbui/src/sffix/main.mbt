// still.fail's Home over made-up chats, with no core (src/sfapp/fixture.mbt, chat_fixture.mbt): what the screenshots
// compare (scripts/shots.sh home, web-home, chat, web-chat) on every run the same. MBUI_FIXTURE (?MBUI_FIXTURE= on
// the web) picks what it shows: home (the default), signin, loading, empty; chat, chat-loading, chat-long (the first
// row's chat open over Home); files, drive…, reader… (the drive's pages, src/sfapp/drive_fixture.mbt); newchat,
// newchat-station, newchat-model (a new chat, its sheets), home-bars (the bottom bar's panel of the other bars),
// home-sheet (the workspaces' sheet), place (the 文件 place); settings, settings-<page> (a page of the settings over
// it: src/sfapp/settings/fixture.mbt), -dark after either for the dark theme; chat-flash, chat-flash-mine (the chat
// opened at a message from a notification, flashing), settings-notify-off (settings, notifications off); chat-cards,
// chat-answering (the chat's card answered and 保留 failed a moment ago; an option under way).

///|
fn main {
  // MBUI_DARK=1: the dark theme
  if @ui.env("MBUI_DARK") == "1" {
    @sf.set_dark(Some(true))
  }
  let mode = @ui.env("MBUI_FIXTURE")
  let src = @sfapp.fixture(mode)
  let rich : @sfapp.ChatRef = {
    station: "ws1/st1",
    session: "s-c1",
    title: "整理发布清单",
    station_name: "Studio",
  }
  if mode == "chat-flash" || mode == "chat-flash-mine" {
    // opened from a notification at a message (Ana's, or yours), its flash held at its peak (slice 10's)
    @sfapp.open_chat_at(rich, if mode == "chat-flash" { 4.0 } else { 6.0 }, held=true)
  } else if mode.has_prefix("chat") {
    @sfapp.open_chat(rich)
    // the cards' states (chat_fixture.mbt): chat-cards, chat-answering
    @sfapp.open_cards_fixture(mode)
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
  // a device not yet confirmed in the workspace's safe mode: lock-waiting, lock-finding, lock-code, lock-wrong (its
  // waiting page in the chats' place), lock-security (its security page)
  if mode == "lock-security" {
    @sfapp.open_setting(@settings.fixture_page("settings-security"))
  }
  @sfapp.desktop_window()
  @ui.run("still.fail", fn(c) { @sfapp.view(c, src) })
}
