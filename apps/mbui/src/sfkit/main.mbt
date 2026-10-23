// still.fail's parts in mbui, on their own (moved out of mbui's demo, whose MBUI_SCREEN=kit and glass they were):
// the kit (rich text, Markdown, pages: kit.mbt) and, with MBUI_SCREEN=glass, frosted and liquid glass over bands of
// colour (glass.mbt). MBUI_DARK=1: the dark theme.

///|
fn main {
  // no core here: the real core's answers to its pure calls, kept (src/sfkept)
  @sf.kept_call.val = Some(@sfkept.answer)
  if @ui.env("MBUI_DARK") == "1" {
    @sf.set_dark(Some(true))
  }
  if @ui.env("MBUI_SCREEN") == "glass" {
    @ui.run("MoonBit UI 玻璃", glass_view)
  } else {
    @ui.run("MoonBit UI 组件", kit_view)
  }
}
