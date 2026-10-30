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
  // MBUI_PLATFORM=android: a phone's screen, as a phone's system has it (its screens drawn on a Mac: scripts/screens.sh
  // rec), and pointed at by a finger as a phone is; MBUI_POINTING=finger or mouse: pointed at so, whatever the system
  match @ui.env("MBUI_PLATFORM") {
    "android" => @ui.set_platform(Some(2))
    "ios" => @ui.set_platform(Some(1))
    "mac" => @ui.set_platform(Some(0))
    "windows" => @ui.set_platform(Some(3))
    _ => ()
  }
  match @ui.env("MBUI_POINTING") {
    "finger" => @ui.set_pointing(Some(Finger))
    "mouse" => @ui.set_pointing(Some(Mouse))
    _ => ()
  }
  let mode = @ui.env("MBUI_FIXTURE")
  // json: a screen as the core's JSON gives it (MBUI_FIXTURE_JSON, or _B64: src/sfapp/fixture_json.mbt), its pages opened
  // as it says
  let src = if mode == "json" {
    @sfapp.fixture_json(@hostapi.env_text("MBUI_FIXTURE_JSON"))
  } else {
    let src = @sffixture.fixture(mode)
    // MBUI_UPDATE=<version>: a newer build offered
    if @ui.env("MBUI_UPDATE") != "" {
      @sffixture.fixture_update(@ui.env("MBUI_UPDATE"))
    }
    // what the mode opens over Home before the first frame (src/sfapp/fixture.mbt: screens_wbtest.mbt opens the same)
    @sfapp.open_fixture_over(mode, src)
    // MBUI_SAID=1: what people, agents and stations wrote at its longest (src/sfapp/fixture_said.mbt)
    if @ui.env("MBUI_SAID") == "1" {
      @sffixture.said_longest_source(src)
    } else {
      src
    }
  }
  // no machine of its own among the made-up stations (the files' places list this machine's first): as the Tester has
  // none
  @sfdesk.set_this_machine("")
  // the faces the app carries (code's JetBrains Mono), as the app has them
  @sf.give_faces()
  @sfapp.host_setup()
  // Preview a native action once its system bar exists, without desktop clicks.
  let native_action = @ui.env("MBUI_NATIVE_ACTION")
  let action_sent = Ref(false)
  @ui.run("still.fail", fn(c) {
    if !action_sent.val && native_action != "" {
      for a in @sf.native_over.acts {
        if a.0 == native_action {
          action_sent.val = true
          (a.3)()
        }
      }
    }
    @sfapp.view(c, src)
  }, tree=@sfapp.app_tree(src))
}
