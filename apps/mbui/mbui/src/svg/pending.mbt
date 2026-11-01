// Text's place in the paint server pass (paint_server.rs): its flattened paths, by its bounding box.

///|
fn text_uses_context_bbox(t : SText) -> Bool {
  uses_context_bbox(t.flattened)
}

///|
fn update_text_paint_servers(t : SText, cts : @skia.Transform, cbbox : @skia.Rect?, cache : Cache) -> Unit {
  update_paint_servers(t.flattened, cts, cbbox, Some(t.bounding_box), cache)
}


