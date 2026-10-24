// The keys of the pages in the wide frame's pane still in this package (the frame's own are sfdesk's keys.mbt, which
// gives them these after it: Pages.keys): the open chat's (keymap.ts chat.jobs, panel.close; Chat.tsx's ↑ / ↓ in an
// empty composer and composer.focus; ChatFind.tsx's Esc), 奏's (DecisionDesk.tsx chat.prev / chat.next); and what the
// open chat offers ⌘K (Pages.offered).

///|
/// The pane's page's keys, read after the frame's: `escape`, Esc pressed and not taken by what the frame opened.
fn page_keys(c : @ui.Ctx, src : Source, w : Workspace, escape : Bool) -> Unit {
  // (as kept on this device: settings' 快捷键, keymap.mbt)
  let prefs = (src.topic)("prefs", {}).value
  let pressed = fn(action : String) { @settings.action_pressed(c, prefs, action) }
  // 奏: the decision before or after the one it shows (DecisionDesk.tsx step)
  if app.nav.top() is Decisions {
    if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
      decision_step(src, w, -1)
    }
    if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
      decision_step(src, w, 1)
    }
  }
  if pressed("chat.jobs") && app.nav.top() is Chat(_) {
    @sfdesk.toggle_jobs_pop()
  }
  if escape {
    if @sfdesk.find_chat() != "" {
      @sfdesk.find_forget()
      c.blur()
    } else if pk.ts != "" {
      pick_clear()
    } else {
      // the chat's side panel closed, all its tabs (keymap.ts panel.close)
      match app.nav.top() {
        Chat(r) if side_now(r).0.length() > 0 => side_change(r, "clear", None)
        _ => ()
      }
    }
  }
  // ↑ / ↓ with the cursor in an empty composer: the chat above or below, as the list shows them now (Chat.tsx
  // useComposerText goToNeighbour)
  match app.nav.top() {
    Chat(r) if c.editor_focused(field_key) && !@sfdesk.switcher_open() =>
      match drafts.get(draft_key(r)) {
        Some(d) if d.text == "" => {
          if c.key_pressed(@ui.key_code_up, in_field=true) {
            @sfdesk.neighbour(src, w, desk_pages(), -1)
          } else if c.key_pressed(@ui.key_code_down, in_field=true) {
            @sfdesk.neighbour(src, w, desk_pages(), 1)
          }
        }
        _ => ()
      }
    _ => ()
  }
  // Space with no field focused: back to the composer (回到输入框)
  if !c.field_focused() && pressed("composer.focus") && !@sfdesk.switcher_open() {
    if app.nav.top() is Chat(_) {
      focus_composer.val = true
    }
  }
}

///|
/// The composer to take the keyboard at the chat page's next drawing (Space with no field focused: 回到输入框).
let focus_composer : Ref[Bool] = Ref(false)

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
