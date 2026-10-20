// 65-wide-places (e2e/traces/wide-places.trace: 1280 × 800): the rail's places: 文件 (the sidebar the stations'
// folders, the test station's home read through the core), the chats again, settings (the sidebar its list, 外观 its
// first page): 深色 there turns the app dark at once (prefs.set appearance dark), 跟随系统 back (appearance system).

///|
test "65-wide-places" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_wide_places, seed~, w=1280.0, h=800.0)
    f.see("新建对话")
    f.tap("icon:folder")
    f.see("主目录")
    f.tap("icon:chats")
    f.see("新建对话")
    f.tap("icon:settings")
    f.see("返回会话")
    f.see("跟随系统")
    f.tap("=深色")
    assert_true(@sf.theme().dark)
    f.tap("=跟随系统", top=true)
    f.tap("返回会话")
    f.see("新建对话")
    // 外观's segmented choices: their thumbs chase last frame's layout on a spring
    f.end(unsettled_ok="sfapp/settings/parts.mbt:508 外观页分段选择的滑块用 c.spring 追上一帧的布局、自己要帧（等 app 迁移）")
  })
}
