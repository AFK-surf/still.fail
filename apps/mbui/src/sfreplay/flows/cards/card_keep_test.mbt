// 71-card-keep (e2e/traces/card-keep.trace): 保留 under the agent's last all-done post (Chat.kt ArchiveUnder): the chat
// kept (chat.keep, 已保留… said); the two buttons go (280 ms, ArchiveEase) and the bar's 归档 with them.

///|
test "71-card-keep" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_card_keep, seed~)
    // (made by alice's other device before the app starts: a live run's step, the trace has what came of it)
    f.before("peer create 保留用的对话 083209 post:这件事也做完了 083209")
    f.before("wait-chat 保留用的对话 083209")
    f.see("保留用的对话 083209")
    f.see("这件事也做完了 083209")
    f.tap("保留用的对话 083209")
    f.run_for(@ui.nav_push_ms)
    f.see("归档此对话")
    f.see("icon:archive")
    f.tap_now("=保留") |> ignore
    // kept (chat.keep, 已保留 said): the buttons go on ArchiveEase's 280 ms from the frame that took the chat's change
    // (no longer archivable), the bar's 归档 with them (Chat.kt ArchiveUnder, ChatBar)
    let end = f.until_moving("under/archive/")
    let from = f.message_taken(fn(m) { m.stringify().contains("\"archivable\"") })
    assert_eq(end, from + @sfapp.archive_ms)
    assert_eq(f.t.rest_of("bar-archive/"), end)
    f.see("已保留")
    f.gone("=归档此对话")
    f.gone("icon:archive")
    // fading and shrinking to 85% about their top's middle on ArchiveEase (Chat.kt ArchiveUnder's), as the run's motion
    // log had them; gone at rest, their room closed with them
    assert_eq(@sfapp.archive_scale, 0.85)
    f.shrinks("归档此对话", to=@sfapp.archive_scale, ease=@sfapp.archive_ease, ms=@sfapp.archive_ms, rest=end)
    // 已保留 said for its time, then gone
    f.run_for(@sfapp.toast_ms - (f.t.time() - from))
    // (its time out at the last frame: it starts going with the one after)
    f.t.draw()
    f.run_to_rest("toast")
    f.end()
  })
}

