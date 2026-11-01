// What is not ported yet: text. Replaced by its port as it lands.

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


