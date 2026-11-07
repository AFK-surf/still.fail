///|
impl @hostapi.Host for Native with png_ready(_) { png_ready() }

///|
impl @hostapi.Host for Native with png_writer(_, width, height) {
  match @svgrender.PngEncoder::new(width, height) {
    None => None
    Some(writer) => Some(@hostapi.PngWriter::{
      add: fn(bytes, count) { writer.add(bytes, count) },
      finish: fn() { writer.finish() },
      close: fn() { writer.close() },
    })
  }
}
