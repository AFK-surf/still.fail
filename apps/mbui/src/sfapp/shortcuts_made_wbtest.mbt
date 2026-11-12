// 快捷键 made once in the app's own frames (narrow_made, tape_made, pane_made): what it records is its own while it is
// the page on top of the stack.

///|
test "快捷键 made once, on each screen: recording, another page put over it (it kept on the stack under), the next key press none of its; the shortcuts back; come back to, it records none" {
  for w in [390.0, 800.0, 1000.0, 1280.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~)
    // (opened as the settings' list opens it: pushed on the settings, shown)
    app.nav.replace(Settings)
    app.nav.push(Setting(@settings.Route::Shortcuts))
    @sfbase.show_chosen()
    t.run_for(@ui.move_most_ms)
    // (on the tape, the page brought over to be used: its cover pressed, bring_page)
    @sfdesk.bring_page()
    t.run_for(@ui.move_most_ms)
    let at = "\{w}"
    // (its keys in the window, to be pressed)
    let keys = t.get(Button, label=@sf.t("web-main.keymap.chat.switch")).rect
    assert_true(keys.0 >= 0.0 && keys.0 + keys.2 <= w, msg="\{at}: its keys at \{Repr(keys)}")
    t.click(Button, label=@sf.t("web-main.keymap.chat.switch"))
    t.frame()
    assert_eq(@settings.keys_recording.get(), "chat.switch", msg=at)
    // another page over it: it records none, the shortcuts back as they were
    app.nav.push(Setting(@settings.Route::About))
    t.run_for(@ui.move_most_ms)
    assert_eq(@settings.keys_recording.get(), "", msg=at)
    let mod = if @ui.keys_system() == 0 { @ui.mod_cmd } else { @ui.mod_ctrl }
    t.key(@ui.key_of_char('j'), mods=mod)
    t.frame()
    assert_eq(named(calls, "keys.set").length(), 0, msg=at)
    // and the shortcuts do what they do again: ⌘⇧+ the window's words larger
    let width = t.ctx().window_size().0
    t.key(@ui.key_of_char('+'), mods=@ui.mod_cmd | @ui.mod_shift_key)
    t.frame()
    assert_true(t.ctx().window_size().0 < width, msg="\{at}: zoomed in")
    // back to it: still none
    app.nav.pop() |> ignore
    t.run_for(@ui.move_most_ms)
    assert_eq(@settings.keys_recording.get(), "", msg=at)
    assert_true(t.find("按下新的快捷键…") is None, msg=at)
  }
}
