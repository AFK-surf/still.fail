// 47-service-page (e2e/traces/service-page.trace): a web service an agent started (e2e/fake: serve: job_start with a
// port), its page from the chat's jobs: the page drawn by a web view whose every request goes through the core to the
// station (station.preview: its HTML, its stylesheet, what its script fetches; the view's requests as the run's host
// made them, on its record: mbui's site lines), where it is typed in the bar (b.html), back in the page's own history,
// shown at a phone's width (its bar's ⋯, its sizes' sheet), left by its bar's 对话. (19107: the service's port as the run's local still.fail gives it,
// e2e-E's: E2E_PORT + 7.)

///|
test "47-service-page" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("service-page"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("开个网页 201409 serve:e2e-web|19107|网页开好了 201409")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    // the agent's words once its service is up, under the person's
    f.see_n(2, "网页开好了 201409")
    // the chat's jobs: its sheet raised
    f.tap("icon:web")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("服务")
    // the service: its page pushed, the site view loading it
    f.tap("在线")
    f.run_to(@ui.nav_rest())
    f.see("=e2e-web")
    // the page as the site view asks for it through the core (station.preview): its HTML, its stylesheet, its data
    f.answered("station.preview", 3)
    // a second page typed in the bar, then back in the page's own history: the bar says where it is
    f.tap("icon:web")
    // (the address taking the typing once the tap has put it there: Ctx::focus_editor, told as the frame's builds end)
    f.field("/")
    f.clear()
    f.type_text("/b.html")
    f.enter()
    // the second page asked for and given
    f.answered("station.preview", 4)
    f.tap("icon:arrow-left")
    f.gone("/b.html")
    // its size from the bar's ⋯ (a phone's, its one row under the page), in the presenters' sheet
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("页面尺寸")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("手机")
    f.run_to(@kit.sheet_rest("sf-present"))
    // left by its bar's 对话 (the system's back would step the page back first while it has a page behind it, as the
    // view says: service_link_wbtest.mbt)
    f.tap("=对话")
    f.run_to(@ui.nav_rest())
    f.see("网页开好了 201409")
    f.end()
  })
}
