// What is not ported yet: images, text and filters. Each is replaced by its port as it lands.

///|
priv struct Filter {
  id : String
  rect : @skia.NonZeroRect
}

///|
fn convert_filters(doc : SDoc, node : Int, state : State, object_bbox : @skia.NonZeroRect?, cache : Cache) -> Array[Filter]? {
  ignore((doc, node, state, object_bbox, cache))
  Some([])
}

///|
fn convert_image(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  ignore((doc, node, state, cache, parent))
}

///|
fn convert_text(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  ignore((doc, node, state, cache, parent))
}

///|
fn text_uses_context_bbox(t : SText) -> Bool {
  ignore(t)
  false
}

///|
fn update_text_paint_servers(t : SText, cts : @skia.Transform, cbbox : @skia.Rect?, cache : Cache) -> Unit {
  update_paint_servers(t.flattened, cts, cbbox, Some(t.bounding_box), cache)
}

///|
fn apply_filter(filter : Filter, ts : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  ignore((filter, ts, pixmap))
}

///|
fn render_image(image : SImage, ts : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  ignore((image, ts, pixmap))
}
