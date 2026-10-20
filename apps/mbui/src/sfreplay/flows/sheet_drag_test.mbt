// 32-sheet-drag (e2e/traces/sheet-drag.trace): a sheet dragged by its top: the workspaces' sheet opened from the
// name (70%), drawn up to nearly all the screen (94%), dragged down past 30%: closed. Then a new chat's station sheet
// (half the screen, not draggable): dragged down a little it comes back, past 80 it closes; opened again, its
// station tapped (newChat.pick).

///|
test "32-sheet-drag" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_sheet_drag, seed~)
    f.see("端到端测试")
    f.tap("=Dev")
    f.run_to(@kit.sheet_rest("sheet"))
    f.see("切换 workspace")
    f.drag("切换 workspace", 0.0, -300.0, steps=sheet_drag_steps)
    f.run_to(@kit.sheet_rest("sheet"))
    f.drag("切换 workspace", 0.0, 640.0, steps=sheet_drag_steps)
    f.run_to(@kit.sheet_rest("sheet"))
    f.gone("切换 workspace")
    f.tap("icon:ling")
    f.run_for(@ui.nav_rise_ms)
    f.see("想让 agent 做什么？")
    f.tap("=studio")
    f.run_to(@kit.sheet_rest("sheet"))
    f.see("选择运行的 station")
    f.drag("选择运行的 station", 0.0, 40.0, steps=sheet_flick_steps)
    f.run_to(@kit.sheet_rest("sheet"))
    f.see("选择运行的 station")
    f.drag("选择运行的 station", 0.0, 200.0, steps=sheet_flick_steps)
    f.run_to(@kit.sheet_rest("sheet"))
    f.gone("选择运行的 station")
    f.tap("=studio")
    f.run_to(@kit.sheet_rest("sheet"))
    f.tap("=studio", top=true)
    f.run_to(@kit.sheet_rest("sheet"))
    f.gone("选择运行的 station")
    f.tap("=取消")
    f.run_for(@ui.nav_rise_ms)
    f.see("端到端测试")
    // the bottom bar's springs and tweens to their declared end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}

///|
/// The runs' drags on a sheet's top: `dragon … 400` (a move a frame, 400 ms of them) and `dragon … 300`.
let sheet_drag_steps : Int = 25

///|
let sheet_flick_steps : Int = 19
