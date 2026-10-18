// still.fail's Home over made-up chats, with no core (src/sfapp/fixture.mbt, chat_fixture.mbt): what the screenshots
// compare (scripts/shots.sh home, web-home, chat, web-chat) on every run the same. MBUI_FIXTURE (?MBUI_FIXTURE= on
// the web) picks what it shows: home (the default), signin, loading, empty; chat, chat-loading, chat-long (the first
// row's chat open over Home).

///|
fn main {
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
  @ui.run("still.fail", fn(c) { @sfapp.view(c, src) })
}
