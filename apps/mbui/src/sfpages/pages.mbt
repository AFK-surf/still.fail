// The pages, one for every tier and either input (docs/architecture.md: Pages): each drawn in the box it is given,
// what it does read from the input, never the tier; what it opens asked of the shell.

///|
/// What this package keeps put back as the app begins anew (its reset).
pub fn reset() -> Unit {
  hover_reset()
  message_reset()
  rows_reset()
  login_cards_reset()
  list_reset()
  menus_reset()
  steps_reset()
  composing_reset()
  triple_reset()
  recent_reset()
  attach_reset()
  chat_rows_reset()
  sidebar_reset()
  finder_reset()
  search_reset()
  marks_reset()
  news_reset()
  landing_reset()
  workspace_reset()
}
