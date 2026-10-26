// 自动决策 (web/src/AutomaticDecisions.tsx; the narrow app's mobile/AutomaticDecisions.tsx), one page in every frame:
// the decision points, each a row to its page.

///|
/// 自动决策 (AutomaticDecisions; the narrow app's AutomaticDecisionsScreen): the point a decision is made at (the
/// completion of a turn), what it does, how many stations have it on (the core's `settings`), a row to its page.
pub fn decisions_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let said = (core.topic)("settings", { "scope": Json::string(here.workspace) }).value
  @sf.page(c, on_back=core.pop, frame~, "auto-decisions", @sf.t("web-pages.automaticDecisions.title"), about=@sf.t("web-pages.automaticDecisions.choosePoint"), [
    fn() {
      @sf.group(c, fn() {
        if @sf.link_row(c, "auto-completion",
            @sf.t("web-pages.automaticDecisions.completion"),
            note=@sf.t(if look == Narrow { "web-pages.automaticDecisions.completionShort" } else { "web-pages.automaticDecisions.completionNote" }),
            value=text(said, "decisionsText"),
          ) {
          (core.push)(AutoCompletion)
        }
      })
    },
  ])
}
