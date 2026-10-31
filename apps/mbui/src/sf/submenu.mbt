// A panel's row opening the next menu alongside it. Its edge is panel_pad inside
// its parent; offset includes that inset so the two panel edges stay panel_pad apart.

///|
let submenu_hover : Ref[String] = Ref("")

///|
pub fn submenu_row(c : @ui.Ctx, key : String, label : String, items : Array[MenuItem?]) -> Unit {
  let row = key + "/row"
  let id = c.id(row)
  if c.rect_of(id) is None {
    if menu_now() == key { menu_set("") }
    if submenu_hover.val == key { submenu_hover.val = "" }
  }
  let pressed = menu_item(c, label, key=row, end="chevron-right")
  if layout(c.window_size().0) == Small {
    if pressed { menu(items, from=Of(id), title=label) }
    return
  }
  let hovered = pointer_rests() && c.hovered(id)
  let entered = hovered && submenu_hover.val != key
  if hovered { submenu_hover.val = key } else if submenu_hover.val == key { submenu_hover.val = "" }
  if pressed || (c.has_focus(id) && c.take_key(if c.rtl() { @ui.key_code_left } else { @ui.key_code_right })) || entered {
    menu_set(key)
  }
  if menu_items(c, key, id, items, submenu=true, side=Right, along=Start, offset=panel_pad + panel_pad) {
    menu_set(key)
  }
}
