// 50-bar-glass (e2e/traces/bar-glass.trace): the bottom bar, all glass: 文件 tapped and the chats again, the notch's
// icon swapping between 令 and 文件's ＋ (a short scale and fade); drawn up into the panel and let go on 奏 there: that
// bar slides down into the bar's place, and 用量 tapped on it as it lands is 用量's at once (laid out where it lands
// from the first frame); the panel again, the chats picked in it.

///|
test "50-bar-glass" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("bar-glass"), seed~)
    f.see("端到端测试")
    f.tap("icon:folder")
    f.see("=文件")
    // the notch's icon swapping to 文件's ＋, the page and the ball going
    f.run_for(@sfapp.icon_swap_ms)
    f.tap("icon:chats")
    f.run_for(@sfapp.icon_swap_ms)
    f.see("端到端测试")
    f.drag("icon:chats", 0.0, -64.0, steps=bar_draw_steps)
    // 用量 tapped where it lands, as the bar chosen comes down
    f.tap_at(133.0, -50.0)
    f.see("=用量")
    f.run_for(@ui.move_most_ms)
    // the bar chosen lands on its own spring, untouched by a finger: the panel is drawn up again once it has
    f.run_to(@sfapp.bar_landed())
    f.drag("icon:zou", 0.0, -64.0, steps=bar_draw_steps)
    f.run_for(@sfapp.switch_fade_ms)
    f.see("端到端测试")
    // the bottom bar's springs and tweens to their declared end (the ball's ride on the bar chosen included)
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
