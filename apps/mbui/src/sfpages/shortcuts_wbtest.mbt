// 快捷键 (shortcuts.mbt) alone, made once, at each width, with a finger and with a mouse: each group's actions and their
// keys; new keys by pressing them.

///|
test "快捷键, at each width and with either hand: each group's actions and their keys" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Shortcuts, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("快捷键") is Some(_), msg=at)
    assert_true(t.find("快速切换对话") is Some(_), msg=at)
    assert_true(t.find("点击快捷键，再按下新的组合") is Some(_), msg=at)
    // none changed: nothing to put back
    assert_true(t.find("全部恢复默认") is None && t.find("恢复默认") is None, msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}

///|
test "快捷键 made once, at each width and with either hand: an action's keys pressed, the next key press is its new keys; Esc leaves them, ⌫ clears them; keys another had moved here, said so; 恢复默认, 全部恢复默认; left, it records none" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let calls : Array[Json] = []
    let t = setting_tester(Shortcuts, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) { if name == "keys.set" { calls.push(params) } ; (s.call)(name, params, done) } }
    })
    // (the command key where the keys are a Mac's, else Ctrl: Mod either way)
    let mod = if @ui.keys_system() == 0 { @ui.mod_cmd } else { @ui.mod_ctrl }
    let switch_ = @sf.t("web-main.keymap.chat.switch")
    let next = @sf.t("web-main.keymap.chat.next")
    // pressed: it records, saying so; Esc: its keys as they were, nothing asked
    t.click(Button, label=switch_)
    t.draw()
    assert_eq(keys_recording.get(), "chat.switch", msg=at)
    assert_true(t.find("按下新的快捷键…") is Some(_), msg=at)
    t.key(@ui.key_escape)
    assert_eq(keys_recording.get(), "", msg=at)
    assert_true(t.find("按下新的快捷键…") is None && calls.length() == 0, msg=at)
    // pressed again: ⌘J (Ctrl+J) its keys now
    t.click(Button, label=switch_)
    t.draw()
    t.key(@ui.key_of_char('j'), mods=mod)
    assert_eq(keys_recording.get(), "", msg=at)
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(field(Some(calls[0]), "action"), Some(Json::string("chat.switch")), msg=at)
    assert_eq(field(Some(calls[0]), "keys"), Some(Json::array([Json::string("Mod+J")])), msg=at)
    t.draw()
    // changed: 恢复默认 on its row, 全部恢复默认 for all of them
    assert_true(t.find("恢复默认") is Some(_) && t.find("全部恢复默认") is Some(_), msg=at)
    // the same keys for another: moved there from it, the core's words said
    t.click(Button, label=next)
    t.draw()
    t.key(@ui.key_of_char('j'), mods=mod)
    t.draw()
    assert_eq(field(Some(calls[1]), "action"), Some(Json::string("chat.next")), msg=at)
    assert_true(app.toast.get().words.contains("移到这里"), msg="\{at}: \{app.toast.get().words}")
    // ⌫: none
    t.click(Button, label=next)
    t.draw()
    t.key(1)
    assert_eq(field(Some(calls[2]), "keys"), Some(Json::array([])), msg=at)
    t.draw()
    // its own again (快速切换对话's, the first of the two changed); every one's
    let resets = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "恢复默认" && !s.hidden })
    assert_eq(resets.length(), 2, msg=at)
    let (rx, ry, rw, rh) = resets[0].rect
    t.tap(rx + rw / 2.0, ry + rh / 2.0)
    t.draw()
    assert_eq(field(Some(calls[3]), "action"), Some(Json::string("chat.switch")), msg=at)
    assert_eq(field(Some(calls[3]), "keys"), Some(Json::null()), msg=at)
    t.click(Button, label="全部恢复默认")
    t.draw()
    assert_eq(field(Some(calls[4]), "action"), None, msg=at)
    t.draw()
    assert_true(t.find("全部恢复默认") is None, msg=at)
    // recording, the page left: it records none
    t.click(Button, label=switch_)
    t.draw()
    assert_eq(keys_recording.get(), "chat.switch", msg=at)
    app.nav.pop() |> ignore
    t.run_for(@ui.move_most_ms)
    assert_eq(keys_recording.get(), "", msg=at)
  }
}
