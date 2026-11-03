// A page's settings (page.mbt's setting, setting_link, settings) as nodes of the window's tree: wide, the rows of one
// list card, each its title and what it is for at its start, its control at its end; narrow, a section each, its title
// over its control, what it is for under it.

///|
/// A setting (setting's) in `parent`: wide, a row of its list card (settings_node's), its title (setting_title), `note`
/// quieter under it, what `control` makes at its end across their middle (wide_control_row_node); narrow, a section of
/// its own, its title over what `control` makes, `note` under it.
pub fn setting_node(
  parent : @view.View,
  title : () -> String,
  control : (@view.View) -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  if look_node(parent) is Wide {
    wide_control_row_node(parent, title, note, setting_title, control)
    return
  }
  section_node(parent, title, fn(sec) {
    control(sec)
    sec.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
  })
}

///|
/// A setting kept on a page of its own (setting_link's) in `parent`: its `title`, what it is for (`note`) and what it is
/// now (`value`), pressed to open its page (`press`). Wide: a row of its list card, a link's (link_row_node), its title
/// a setting's with its note under it, what it is now and the chevron at its end; narrow: a section of its own, its
/// title over a card of one row saying what it is now (the chevron at its end), what it is for under it.
pub fn setting_link_node(
  parent : @view.View,
  title : () -> String,
  value : () -> String,
  press : () -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  if look_node(parent) is Wide {
    link_row_node(parent, title, press, value~, note~, title_style=setting_title())
    return
  }
  section_node(parent, title, fn(sec) {
    group_node(sec, fn(g) { link_row_node(g, value, press) })
    sec.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
  })
}

///|
/// A page's settings (settings'): the keys of the blocks they are on, laid out `look`: wide, one (its list card, all of
/// them its rows: settings_node), narrow, one each (`keys`).
pub fn settings_blocks(look : Look, keys : Array[String]) -> Array[String] {
  match look {
    Wide => [settings_card_key]
    Narrow => keys
  }
}

///|
/// The block settings_blocks names wide.
pub let settings_card_key : String = "settings"

///|
/// A page's settings on the block `key` names (settings_blocks'): wide, its list card, each of `keys` a row of it made
/// by `setting`; narrow, the one `key` is.
pub fn settings_node(
  parent : @view.View,
  key : String,
  keys : () -> Array[String],
  setting : (@view.View, String) -> Unit,
) -> Unit {
  if key == settings_card_key && look_node(parent) is Wide {
    group_node(parent, fn(g) { g.each(keys, fn(k) { k }, fn(r, k) { setting(r, @signals.untracked(fn() { k.get() })) }) })
    return
  }
  setting(parent, key)
}
