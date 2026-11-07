///|
extern "js" fn png_status() -> Int =
  #| () => globalThis.mbuiSvg ? 1 : (globalThis.mbuiSvgFailed ? -1 : 0)

///|
fn png_ready() -> Bool? {
  match png_status() { 0 => None; 1 => Some(true); _ => Some(false) }
}
