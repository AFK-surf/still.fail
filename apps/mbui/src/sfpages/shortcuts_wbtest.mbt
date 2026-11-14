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

///|
test "快捷键, at each width and with either hand: how a message is sent, Enter 发送 or ⌘ Enter 发送 (prefs sendKey), the keys that send and make a new line said under it as chosen" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let sets : Array[Json] = []
    let t = setting_tester(Shortcuts, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) { if name == "prefs.set" { sets.push(params) } ; (s.call)(name, params, done) } }
    })
    let mac = @ui.platform() == 0
    let (by_mod, sends, lines) = if mac {
      ("⌘ Enter 发送", "发送 ⌘↩，换行 ↩ / ⇧↩", "发送 ↩，换行 ⇧↩")
    } else {
      ("Ctrl+Enter 发送", "发送 Ctrl+↩，换行 ↩ / Shift+↩", "发送 ↩，换行 Shift+↩")
    }
    assert_true(t.find("发送消息") is Some(_), msg=at)
    assert_true(t.find("Enter 发送") is Some(_) && t.find(by_mod) is Some(_), msg=at)
    assert_true(t.find(lines) is Some(_), msg=at)
    t.click(Radio, label=by_mod)
    t.draw()
    assert_eq(sets.length(), 1, msg=at)
    assert_eq(field(Some(sets[0]), "sendKey"), Some(Json::string("mod")), msg=at)
    assert_true(t.find(sends) is Some(_), msg=at)
    t.click(Radio, label="Enter 发送")
    t.draw()
    assert_eq(field(Some(sets[1]), "sendKey"), Some(Json::null()), msg=at)
    assert_true(t.find(lines) is Some(_), msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}

///|
test "快捷键, at each width and with either hand: every action's name drawn, wider than nothing; its keys beside it while its line has the room for both, else on a line of their own under it at its end" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Shortcuts, w, platform~, h=2400.0)
    let word = fn(f : (String) -> Bool) {
      match t.words().search_by(fn(x) { f(x.0) }) {
        Some(i) => t.words()[i]
        None => ("", 0.0, 0.0, 0.0, 0.0, 0.0)
      }
    }
    // (every action the page lists, by its name where the names are, as 新建对话's: drawn, wider than nothing, on one
    // line as that is)
    let new = word(fn(s) { s == @sf.t("web-main.keymap.chat.new") })
    let named = fn(name : String) {
      match t.words().search_by(fn(x) { x.0 == name && (x.1 - new.1).abs() < 0.5 }) {
        Some(i) => t.words()[i]
        None => ("", 0.0, 0.0, 0.0, 0.0, 0.0)
      }
    }
    for a in @sffixture.fx_key_actions {
      // (not one the page lists: none of its own to show, or only worth a key: keymap.ts UNLISTED)
      if a.4 == "no" || @sffixture.fx_key_unlisted.contains(a.0) {
        continue
      }
      let name = @sf.t("web-main.keymap.\{a.0}")
      let n = named(name)
      assert_true(n.0 == name && n.3 > 0.0 && n.4 == new.4, msg="\{at}: \{name} at \{Repr(n)}, 新建对话 at \{Repr(new)}")
    }
    // 放大界面's keys, the longest (the only ones with an =): beside it where the line has the room for both, the
    // middle of its line; else under it, at the line's end as 新建对话's are
    let n = named(@sf.t("web-main.keymap.zoom.in"))
    let keys = word(fn(s) { s.contains("=") })
    assert_true(keys.3 > 0.0, msg="\{at}: \{Repr(t.words())}")
    let mid = fn(x : (String, Double, Double, Double, Double, Double)) { x.2 + x.4 / 2.0 }
    let button = fn(x : (String, Double, Double, Double, Double, Double)) {
      match t.drawn_rects().search_by(fn(r) { r.0 <= x.1 && x.1 + x.3 <= r.0 + r.2 && r.1 <= x.2 && x.2 + x.4 <= r.1 + r.3 && r.3 < 40.0 }) {
        Some(i) => t.drawn_rects()[i]
        None => (0.0, 0.0, 0.0, 0.0, 0L)
      }
    }
    let new_keys = word(fn(s) { s.has_suffix("N") && s != n.0 })
    let (b, nb) = (button(keys), button(new_keys))
    assert_true(b.2 > 0.0 && nb.2 > 0.0, msg="\{at}: its keys' button \{Repr(b)}, 新建对话's \{Repr(nb)}")
    if w >= 720.0 {
      assert_true((mid(keys) - mid(n)).abs() < 0.5 && keys.1 > n.1 + n.3, msg="\{at}: its name at \{Repr(n)}, its keys at \{Repr(keys)}")
    } else {
      if platform == 2 {
        assert_true(keys.2 >= n.2 + n.4, msg="\{at}: its name at \{Repr(n)}, its keys at \{Repr(keys)}")
      }
      if keys.2 >= n.2 + n.4 {
        assert_true((b.0 + b.2 - (nb.0 + nb.2)).abs() < 0.5, msg="\{at}: its keys' button \{Repr(b)}, 新建对话's \{Repr(nb)}")
      }
    }
  }
}
