// 31-places (e2e/traces/places.trace): the bottom bar's places: 文件 tapped (its page in place of the chats', the ball
// going to it); the bar drawn up into the panel of the other bar and let go on 用量 there (that bar in view, 用量's
// page); 已归档 tapped; the panel again, the chats picked in it (the first bar back in view). The bar chosen kept as the
// workspace's on the device (prefs.set barsBy).

///|
test "31-places" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("places"), seed~)
    f.see("端到端测试")
    f.tap("icon:folder")
    // 文件's page in from the side the ball goes to; the ball there
    f.run_for(@ui.move_most_ms)
    f.see("=文件")
    f.gone("端到端测试")
    f.tap("icon:chats")
    f.run_for(@ui.move_most_ms)
    f.see("端到端测试")
    // drawn up slowly (the run's second: no fling), let go over the other bar's 用量
    f.drag("icon:chats", 0.0, -64.0, steps=bar_draw_steps)
    f.run_for(@sfapp.switch_fade_ms)
    f.see("=用量")
    f.tap("icon:archive")
    f.run_for(@ui.move_most_ms)
    f.see("=已归档")
    f.drag("icon:chart", 0.0, -64.0, steps=bar_draw_steps)
    f.run_for(@sfapp.switch_fade_ms)
    f.see("端到端测试")
    // the bottom bar's springs and tweens to their declared end (the ball's ride on the bar chosen included)
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}

///|
/// A finger drawing the bar up into the panel as the runs do (`dragon 0 -64 1000`): a move each frame, a second's
/// worth of them.
let bar_draw_steps : Int = 60
