// The pages, one for every tier and either input (docs/architecture.md: Pages): each drawn in the box it is given,
// what it does read from the input, never the tier; what it opens asked of the shell.

///|
/// What the pages give sfbase as the app starts: a station's login card and the card to share, for the settings'
/// core (@sfbase.settings_core). Said once (reset runs only as a Tester starts).
fn init {
  @sfbase.login_card_of.val = fn(c, core, station, id, marked) { login_card(c, core, station, id, marked~) }
  @sfbase.share_card_of.val = share_card_open
}

///|
/// What this package keeps put back as the app begins anew (its reset).
pub fn reset() -> Unit {
  hover_reset()
  message_reset()
  rows_reset()
  login_cards_reset()
  relay_focus_reset()
  publish_reset()
  xsharing_reset()
  list_reset()
  menus_reset()
  steps_reset()
  composing_reset()
  triple_reset()
  recent_reset()
  chat_rows_reset()
  sidebar_reset()
  finder_reset()
  search_reset()
  marks_reset()
  news_reset()
  landing_reset()
  workspace_reset()
  outside_reset()
  new_chat_reset()
}
