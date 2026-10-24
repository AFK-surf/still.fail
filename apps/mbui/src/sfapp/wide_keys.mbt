// The keys of the pages in the wide frame's pane still in this package (the frame's own and the open chat's are sfdesk's
// keys.mbt, chat_layers.mbt, which give them these after theirs: Pages.keys): 奏's (DecisionDesk.tsx chat.prev /
// chat.next); and what the open chat offers ⌘K (Pages.offered).

///|
/// The pane's page's keys, read after the frame's: `escape`, Esc pressed and not taken by what the frame opened.
fn page_keys(c : @ui.Ctx, src : Source, w : Workspace, escape : Bool) -> Unit {
  // (as kept on this device: settings' 快捷键, keymap.mbt)
  let prefs = (src.topic)("prefs", {}).value
  // 奏: the decision before or after the one it shows (DecisionDesk.tsx step)
  if app.nav.top() is Decisions {
    if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
      decision_step(src, w, -1)
    }
    if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
      decision_step(src, w, 1)
    }
  }
  ignore(escape)
}

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
