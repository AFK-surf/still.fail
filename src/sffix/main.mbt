// still.fail's Home over made-up chats, with no core (src/sfapp/fixture.mbt): what the screenshots compare
// (scripts/shots.sh home, web-home) on every run the same. MBUI_FIXTURE (?MBUI_FIXTURE= on the web) picks what it
// shows: home (the default), signin, loading, empty.

///|
fn main {
  let src = @sfapp.fixture(@host.env("MBUI_FIXTURE"))
  @ui.run("still.fail", fn(c) { @sfapp.view(c, src) })
}
