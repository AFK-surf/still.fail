// 36-archive-restore (e2e/traces/archive-restore.trace): a chat archived by alice's other device (chat.archive) leaves
// Home; Home's filter → 已归档: it is there, by day. Restored from its row (还原): it leaves the archive.

///|
test "36-archive-restore" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_archive_restore, seed~)
    f.see("端到端测试")
    f.gone("要归档的对话 083209")
    f.tap("icon:filter")
    f.see("=已归档")
    f.tap("=已归档")
    // the archive pushed over Home
    f.run_for(@ui.nav_push_ms)
    f.see("要归档的对话 083209")
    f.see("归档前的回复 083209")
    f.tap("icon:retry", top=true)
    f.gone("要归档的对话 083209")
    // the bottom bar at its end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
