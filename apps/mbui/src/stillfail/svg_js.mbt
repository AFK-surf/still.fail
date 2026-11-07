// The browser starts downloading SVG after the app; its completion is a host message.
///|
extern "js" fn svg_loaded() -> Bool =
  #| () => !!globalThis.mbuiSvg

///|
fn prepare_svg() -> Unit {
  @ui.set_vector_pictures_ready(if svg_loaded() { Some(true) } else { None })
  @ui.on_message("mbui.svg", fn(status, _) {
    @ui.set_vector_pictures_ready(Some(status == "ready"))
  })
}
