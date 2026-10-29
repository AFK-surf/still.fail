// 35-station-rename (e2e/traces/station-rename.trace): Settings → Station → the test station's page → "…" → 重命名:
// the new name on its page and in the list at once (station.rename); named back after. Its menu and the name asked are
// the presenters' (sheets on a phone).

///|
test "35-station-rename" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("station-rename"), seed~)
    f.see("端到端测试")
    f.tap("icon:settings")
    f.run_for(@ui.move_most_ms)
    f.tap("=Station")
    f.run_for(@ui.move_most_ms)
    f.tap("=studio")
    f.run_for(@ui.move_most_ms)
    f.see("概览")
    for name in ["e2e-082939", "studio"] {
      f.tap("icon:more")
      f.run_to(@kit.sheet_rest("sf-present"))
      // (the menu's 重命名, the higher: the rename sheet before may still be sinking under it, its title the same words;
      // the words alone, not 已重命名 said above the menu by the rename before, which a scripted run took for it)
      f.tap("=重命名", top=true)
      f.run_to(@kit.sheet_rest("sf-present"))
      f.see("station 名称")
      f.clear()
      f.type_text(name)
      f.tap("=保存")
      // said as the rename is answered (settings' act), which may come before the new name is shown or after
      f.see("已重命名")
      f.run_to(@kit.sheet_rest("sf-present"))
      f.see("=" + name)
    }
    // 已重命名 said for its time from the frame that took the last rename's answer, then gone (at a slower pace the name
    // can come after its time is out: it is going or gone by then)
    let from = f.answer_taken("workspace.renameStation")
    assert_true(from >= 0.0)
    let out = from + @sfapp.toast_ms
    if f.t.time() < out {
      f.run_for(out - f.t.time())
      // (its time out at the last frame: it starts going with the one after)
      f.t.draw()
    }
    f.run_to_rest("toast")
    f.end()
  })
}
