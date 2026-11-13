// Comma's parts in mbui (src/cm), on one page: each in its hierarchies, sizes and states, as Comma's Storybook shows
// them, to set beside it (MBUI_CM_PAGE=more: the floating parts and the rest; MBUI_CM_OPEN one of them open: src/pages). MBUI_DARK=1: the dark look. MBUI_CM_FONT: Inter's variable file (Comma's face; Cue's
// clients/apps/android/app/src/main/res/font/inter_variable.ttf), else the system's.

///|
fn main {
  if @ui.env("MBUI_DARK") == "1" {
    @cm.set_dark(Some(true))
  } else {
    @cm.set_dark(Some(false))
  }
  let font = @ui.env("MBUI_CM_FONT")
  if font != "" {
    ignore(@hostapi.face_add(@hostapi.face_ui, font, 0))
  }
  let (more, open) = (@ui.env("MBUI_CM_PAGE") == "more", @ui.env("MBUI_CM_OPEN"))
  @ui.run("Comma 组件", fn(_c) {  }, tree=fn(root) { @pages.page(root, more~, open~) })
}

