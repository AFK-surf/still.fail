// The pages, one for every tier and either input (docs/architecture.md: Pages): each drawn in the box it is given,
// what it does read from the input, never the tier; what it opens asked of the shell.

///|
/// What the pages give sfbase as the app starts: a station's login card and the card to share, for the settings'
/// core (@sfbase.settings_core); and the library where a picture made in it goes (@sf.picture_out_by: a table's).
/// Said once (reset runs only as a Tester starts).
fn init {
  @sfbase.login_card_of.val = fn(c, core, station, id, marked) { login_card(c, core, station, id, marked~) }
  @sfbase.share_card_of.val = share_card_open
  @sfbase.screen_made_stream.val = screen_fixture_stream
  @sf.picture_out_by.val = fn(c, png, said) { picture_out(c, png, copy_said=said) }
}

///|
/// What this package keeps put back as the app begins anew (its reset).
pub fn reset() -> Unit {
  screen_fix_mode.val = ""
  screen_fix_heard.val = None
  screens_open.clear()
  screen_uis.clear()
  screens_made.val = 0
  hover_reset()
  message_reset()
  rows_reset()
  login_cards_reset()
  relay_focus_reset()
  publish_reset()
  xsharing_reset()
  list_reset()
  menus_reset()
  things_reset()
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
  changelog_reset()
  font_setting_reset()
  notify_page_reset()
  usage_reset()
  desk_dialogs.val = 0
  vault_reset()
  vault_item_reset()
  mine_filter_open.clear()
  connect_reset()
  outflow_left.clear()
  new_connect_reset()
  station_cards_reset()
  station_page_reset()
  profile_page_reset()
  local_menu.val = false
  memory_doc_reset()
  signin_reset()
  fx_policy_up.val = ""
  fx_vault_add_up.val = false
  fx_spread_up.val = false
}
