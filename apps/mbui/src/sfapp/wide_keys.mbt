// What the open chat offers ⌘K (Pages.offered); its keys and the frame's are sfdesk's (keys.mbt, chat_layers.mbt).

///|
/// What the open chat offers ⌘K (the keys' actions its page answers: ChatPage.tsx chat.find, chat.jobs).
fn chat_offered(c : @ui.Ctx, src : Source) -> Array[@sfdesk.Offered] {
  let prefs = (src.topic)("prefs", {}).value
  let keys = fn(action : String) { @settings.key_label(prefs, action) }
  match app.nav.top() {
    Chat(r) =>
      [
        {
          id: "chat.find",
          group: "",
          label: "",
          words: "",
          icon: "search",
          keys: keys("chat.find"),
          typed: false,
          run: fn() { find_open(c, r) },
        },
        {
          id: "chat.jobs",
          group: "",
          label: "",
          words: "",
          icon: "web",
          keys: keys("chat.jobs"),
          typed: false,
          run: fn() { @sfdesk.open_jobs_pop() },
        },
      ]
    _ => []
  }
}
