// Made by scripts/cm-tokens.mjs from Comma's design tokens (AFK-surf/Cue c51cb708e7,
// clients/packages/ui/src/tokens): do not edit, run it again when they change. What each is: tokens.mbt.

///|
/// Comma's colours in one appearance (semantic's text_, border_, fg_, bg_; the components' by their names), each
/// 0xRRGGBBAA: `light` and `dark`.
pub(all) struct Colors {
  text_primary : Int64
  text_secondary : Int64
  text_tertiary : Int64
  text_quaternary : Int64
  text_white : Int64
  text_disabled : Int64
  text_placeholder : Int64
  text_claude : Int64
  text_codex : Int64
  text_brand_primary : Int64
  text_brand_secondary : Int64
  text_brand_tertiary : Int64
  text_error_primary : Int64
  text_warning_primary : Int64
  text_success_primary : Int64
  border_primary : Int64
  border_menu_primary : Int64
  border_secondary : Int64
  border_tertiary : Int64
  border_disabled : Int64
  border_brand : Int64
  border_brand_solid : Int64
  border_error : Int64
  border_error_solid : Int64
  fg_primary : Int64
  fg_secondary : Int64
  fg_tertiary : Int64
  fg_quaternary : Int64
  fg_quinary : Int64
  fg_quinary_hover : Int64
  fg_senary : Int64
  fg_button : Int64
  fg_button_active : Int64
  fg_button_secondary : Int64
  fg_white : Int64
  fg_disabled : Int64
  fg_brand_primary : Int64
  fg_error_primary : Int64
  fg_warning_primary : Int64
  fg_warning_secondary : Int64
  fg_success_primary : Int64
  bg_primary : Int64
  bg_popup_primary : Int64
  bg_popup_secondary : Int64
  bg_secondary : Int64
  bg_secondary_hover : Int64
  bg_tertiary : Int64
  bg_quaternary : Int64
  bg_quaternary_hover : Int64
  bg_active : Int64
  bg_disabled : Int64
  bg_overlay : Int64
  bg_brand_primary : Int64
  bg_brand_secondary : Int64
  bg_brand_solid : Int64
  bg_brand_solid_hover : Int64
  bg_error_primary : Int64
  bg_error_solid : Int64
  bg_warning_primary : Int64
  bg_warning_solid : Int64
  bg_success_primary : Int64
  bg_success_solid : Int64
  bg_toggle : Int64
  bg_toggle_hover : Int64
  bg_window : Int64
  bg_claude : Int64
  bg_codex : Int64
  bg_gpt : Int64
  toast_text_primary : Int64
  toast_text_secondary : Int64
  toast_icon_primary : Int64
  button_primary_bg : Int64
  button_primary_bg_hover : Int64
  button_primary_border : Int64
  button_primary_border_hover : Int64
  button_primary_fg : Int64
  button_primary_fg_hover : Int64
  button_secondary_bg : Int64
  button_secondary_border : Int64
  button_secondary_fg : Int64
  button_secondary_color_bg : Int64
  button_secondary_color_bg_hover : Int64
  button_secondary_color_border : Int64
  button_secondary_color_border_hover : Int64
  button_secondary_color_fg : Int64
  button_secondary_color_fg_hover : Int64
  button_tertiary_fg : Int64
  button_tertiary_fg_hover : Int64
  button_tertiary_bg_hover : Int64
  button_tertiary_color_fg : Int64
  button_tertiary_color_fg_hover : Int64
  button_tertiary_color_bg_hover : Int64
  button_primary_error_bg : Int64
  button_primary_error_bg_hover : Int64
  button_primary_error_border : Int64
  button_primary_error_border_hover : Int64
  button_primary_error_fg : Int64
  button_primary_error_fg_hover : Int64
  dialog_bg : Int64
  dialog_shortcut_on_primary_bg : Int64
  dialog_shortcut_on_primary_text : Int64
  menu_hover_error : Int64
  toggle_button_fg_disabled : Int64
  slider_handle_bg : Int64
  slider_handle_border : Int64
  avatar_bg : Int64
  avatar_profile_photo_border : Int64
  tooltip_bg : Int64
  tooltip_border : Int64
  tooltip_text : Int64
  tooltip_supporting_text : Int64
  tooltip_shortcut_bg : Int64
  tooltip_shortcut_text : Int64
  ai_input_header_icon_primary : Int64
  ai_input_header_text_primary : Int64
  ai_input_header_text_secondary : Int64
  ai_input_panel_icon_primary : Int64
  ai_input_panel_icon_disabled : Int64
  ai_input_panel_icon_fg : Int64
  ai_input_panel_icon_warning : Int64
  ai_input_panel_text_primary : Int64
  ai_input_panel_text_placeholder : Int64
  ai_input_panel_text_warning : Int64
  ai_input_panel_bg_input : Int64
  ai_input_panel_bg_tag : Int64
  ai_input_panel_text_attachment_primary : Int64
  ai_input_panel_text_attachment_secondary : Int64
  ai_input_panel_bg_disabled : Int64
  ai_input_panel_bg_attachment : Int64
  panel_bg_file : Int64
  markdown_text_primary : Int64
  markdown_text_secondary : Int64
  markdown_text_tool_primary : Int64
  markdown_audio_control_primary : Int64
  markdown_text_inline_primary : Int64
  markdown_text_inline_code : Int64
  markdown_bg_inline_code : Int64
  markdown_text_link : Int64
  markdown_bg_message : Int64
  markdown_bg_table : Int64
  markdown_border_table : Int64
  markdown_bg_tool : Int64
  markdown_icon_primary : Int64
  markdown_bg_icon_hover : Int64
  markdown_image_bg_primary : Int64
  markdown_image_hover : Int64
  markdown_image_icon_primary : Int64
  markdown_image_bar_border : Int64
  markdown_sound_video_icon_primary : Int64
  markdown_sound_video_text_primary : Int64
  markdown_sound_video_bg_hover : Int64
  markdown_sound_video_bg_player_bar : Int64
  markdown_sound_video_bg_progress : Int64
  markdown_sound_video_bg_tracker : Int64
  markdown_sound_video_bar_border : Int64
  markdown_sound_video_bg_preview : Int64
  main_panel_bg : Int64
  main_panel_item_bg : Int64
  plugin_bg_button : Int64
  plugin_border : Int64
  plugin_row_bg_hover : Int64
  todo_kanban_bg_card_primary : Int64
  todo_kanban_bg_column_primary : Int64
  todo_list_bg_needs_review_main : Int64
  todo_list_bg_done : Int64
  todo_list_bg_cancel : Int64
  todo_list_bg_group_fade : Int64
  sidebar_text_primary : Int64
  sidebar_text_secondary : Int64
  sidebar_text_tertiary : Int64
  sidebar_bg_selection : Int64
  sidebar_text_highlight : Int64
  sidebar_icon_primary : Int64
  sidebar_icon_secondary : Int64
  sidebar_icon_disabled : Int64
  sidebar_bg_item : Int64
  scrollbar_bg : Int64
  utility_gray_50 : Int64
  utility_gray_200 : Int64
  utility_gray_300 : Int64
  utility_gray_700 : Int64
  utility_brand_50 : Int64
  utility_brand_100 : Int64
  utility_brand_200 : Int64
  utility_brand_300 : Int64
  utility_brand_400 : Int64
  utility_brand_700 : Int64
  utility_error_50 : Int64
  utility_error_200 : Int64
  utility_error_300 : Int64
  utility_error_700 : Int64
  utility_warning_50 : Int64
  utility_warning_200 : Int64
  utility_warning_300 : Int64
  utility_warning_700 : Int64
  utility_success_50 : Int64
  utility_success_200 : Int64
  utility_success_300 : Int64
  utility_success_700 : Int64
  utility_blue_50 : Int64
  utility_blue_200 : Int64
  utility_blue_300 : Int64
  utility_blue_700 : Int64
  utility_indigo_50 : Int64
  utility_indigo_200 : Int64
  utility_indigo_300 : Int64
  utility_indigo_700 : Int64
  utility_purple_50 : Int64
  utility_purple_200 : Int64
  utility_purple_300 : Int64
  utility_purple_700 : Int64
  utility_pink_50 : Int64
  utility_pink_200 : Int64
  utility_pink_300 : Int64
  utility_pink_700 : Int64
  utility_orange_50 : Int64
  utility_orange_200 : Int64
  utility_orange_300 : Int64
  utility_orange_700 : Int64
}

///|
/// Comma's colours, light.
pub let light : Colors = {
  text_primary: 0x1A1B1EFFL,
  text_secondary: 0x4A4C50FFL,
  text_tertiary: 0x5B5E63FFL,
  text_quaternary: 0x7F8286FFL,
  text_white: 0xFFFFFFFFL,
  text_disabled: 0xB6B8BBFFL,
  text_placeholder: 0xB6B8BBFFL,
  text_claude: 0xD97757FFL,
  text_codex: 0x706FFCFFL,
  text_brand_primary: 0x02092BFFL,
  text_brand_secondary: 0x062389FFL,
  text_brand_tertiary: 0x092FC0FFL,
  text_error_primary: 0xD92D20FFL,
  text_warning_primary: 0xF79009FFL,
  text_success_primary: 0x079455FFL,
  border_primary: 0xDFE0E2FFL,
  border_menu_primary: 0xB6B8BBFFL,
  border_secondary: 0xF1F1F1FFL,
  border_tertiary: 0xF5F5F5FFL,
  border_disabled: 0xDFE0E2FFL,
  border_brand: 0x3B7CFFFFL,
  border_brand_solid: 0x092FC0FFL,
  border_error: 0xFDA29BFFL,
  border_error_solid: 0xD92D20FFL,
  fg_primary: 0x1A1B1EFFL,
  fg_secondary: 0x4A4C50FFL,
  fg_tertiary: 0x5B5E63FFL,
  fg_quaternary: 0x7F8286FFL,
  fg_quinary: 0xB6B8BBFFL,
  fg_quinary_hover: 0x7F8286FFL,
  fg_senary: 0xDFE0E2FFL,
  fg_button: 0xFFFFFFFFL,
  fg_button_active: 0xDFE0E2FFL,
  fg_button_secondary: 0xFFFFFFFFL,
  fg_white: 0xFFFFFFFFL,
  fg_disabled: 0xB6B8BBFFL,
  fg_brand_primary: 0x092FC0FFL,
  fg_error_primary: 0xD92D20FFL,
  fg_warning_primary: 0xDC6803FFL,
  fg_warning_secondary: 0xF79009FFL,
  fg_success_primary: 0x079455FFL,
  bg_primary: 0xFFFFFFFFL,
  bg_popup_primary: 0xFFFFFFFFL,
  bg_popup_secondary: 0xFFFFFFFFL,
  bg_secondary: 0xFAFAFAFFL,
  bg_secondary_hover: 0xF5F5F5FFL,
  bg_tertiary: 0xF5F5F5FFL,
  bg_quaternary: 0xF1F1F1FFL,
  bg_quaternary_hover: 0xF1F1F1FFL,
  bg_active: 0xFAFAFAFFL,
  bg_disabled: 0xF5F5F5FFL,
  bg_overlay: 0x111213FFL,
  bg_brand_primary: 0xB8DDFFFFL,
  bg_brand_secondary: 0x8CBFFFFFL,
  bg_brand_solid: 0x205BFFFFL,
  bg_brand_solid_hover: 0x1040F2FFL,
  bg_error_primary: 0xFEF3F2FFL,
  bg_error_solid: 0xD92D20FFL,
  bg_warning_primary: 0xFFFAEBFFL,
  bg_warning_solid: 0xDC6803FFL,
  bg_success_primary: 0xECFDF3FFL,
  bg_success_solid: 0x079455FFL,
  bg_toggle: 0xDFE0E2FFL,
  bg_toggle_hover: 0xF1F1F1FFL,
  bg_window: 0xF5F5F5FFL,
  bg_claude: 0xF1CDC1FFL,
  bg_codex: 0xCDCCFFFFL,
  bg_gpt: 0xE2E9EDFFL,
  toast_text_primary: 0x222326FFL,
  toast_text_secondary: 0x7F8286FFL,
  toast_icon_primary: 0x5B5E63FFL,
  button_primary_bg: 0x205BFFFFL,
  button_primary_bg_hover: 0x1040F2FFL,
  button_primary_border: 0x1040F2FFL,
  button_primary_border_hover: 0x092FC0FFL,
  button_primary_fg: 0xFFFFFFFFL,
  button_primary_fg_hover: 0xFFFFFFFFL,
  button_secondary_bg: 0xFFFFFFFFL,
  button_secondary_border: 0xDFE0E2FFL,
  button_secondary_fg: 0x222326FFL,
  button_secondary_color_bg: 0xFFFFFFFFL,
  button_secondary_color_bg_hover: 0xB8DDFFFFL,
  button_secondary_color_border: 0x3B7CFFFFL,
  button_secondary_color_border_hover: 0x3B7CFFFFL,
  button_secondary_color_fg: 0x1040F2FFL,
  button_secondary_color_fg_hover: 0x062389FFL,
  button_tertiary_fg: 0x5B5E63FFL,
  button_tertiary_fg_hover: 0x4A4C50FFL,
  button_tertiary_bg_hover: 0xFAFAFAFFL,
  button_tertiary_color_fg: 0x062389FFL,
  button_tertiary_color_fg_hover: 0x041756FFL,
  button_tertiary_color_bg_hover: 0xB8DDFFFFL,
  button_primary_error_bg: 0xD92D20FFL,
  button_primary_error_bg_hover: 0xB42318FFL,
  button_primary_error_border: 0xD92D20FFL,
  button_primary_error_border_hover: 0xB42318FFL,
  button_primary_error_fg: 0xFFFFFFFFL,
  button_primary_error_fg_hover: 0xFFFFFFFFL,
  dialog_bg: 0xFFFFFFFFL,
  dialog_shortcut_on_primary_bg: 0xFFFFFF29L,
  dialog_shortcut_on_primary_text: 0xFFFFFFEBL,
  menu_hover_error: 0xFEF3F2FFL,
  toggle_button_fg_disabled: 0xFAFAFAFFL,
  slider_handle_bg: 0xFFFFFFFFL,
  slider_handle_border: 0x092FC0FFL,
  avatar_bg: 0xF5F5F5FFL,
  avatar_profile_photo_border: 0xFFFFFFFFL,
  tooltip_bg: 0x27282BFFL,
  tooltip_border: 0x343538FFL,
  tooltip_text: 0xF6F6F6FFL,
  tooltip_supporting_text: 0xD1D1D1FFL,
  tooltip_shortcut_bg: 0x54565AFFL,
  tooltip_shortcut_text: 0xD1D1D1FFL,
  ai_input_header_icon_primary: 0x5B5E63FFL,
  ai_input_header_text_primary: 0x000000FFL,
  ai_input_header_text_secondary: 0x7F8286FFL,
  ai_input_panel_icon_primary: 0x7F8286FFL,
  ai_input_panel_icon_disabled: 0xDFE0E2FFL,
  ai_input_panel_icon_fg: 0xFFFFFFFFL,
  ai_input_panel_icon_warning: 0xF79009FFL,
  ai_input_panel_text_primary: 0x000000FFL,
  ai_input_panel_text_placeholder: 0xB6B8BBFFL,
  ai_input_panel_text_warning: 0xF79009FFL,
  ai_input_panel_bg_input: 0xFFFFFFFFL,
  ai_input_panel_bg_tag: 0x000000FFL,
  ai_input_panel_text_attachment_primary: 0x1A1B1EFFL,
  ai_input_panel_text_attachment_secondary: 0x7F8286FFL,
  ai_input_panel_bg_disabled: 0xF5F5F5FFL,
  ai_input_panel_bg_attachment: 0xFFFFFFFFL,
  panel_bg_file: 0xF1F1F1FFL,
  markdown_text_primary: 0x1A1B1EFFL,
  markdown_text_secondary: 0x7F8286FFL,
  markdown_text_tool_primary: 0x7F8286FFL,
  markdown_audio_control_primary: 0x5B5E63FFL,
  markdown_text_inline_primary: 0x1A1B1EFFL,
  markdown_text_inline_code: 0x912018FFL,
  markdown_bg_inline_code: 0xF1F1F1FFL,
  markdown_text_link: 0x3B7CFFFFL,
  markdown_bg_message: 0xF1F1F1FFL,
  markdown_bg_table: 0xF5F5F5FFL,
  markdown_border_table: 0xDFE0E2FFL,
  markdown_bg_tool: 0xFFFFFFFFL,
  markdown_icon_primary: 0x7F8286FFL,
  markdown_bg_icon_hover: 0xF1F1F1FFL,
  markdown_image_bg_primary: 0xFFFFFFB2L,
  markdown_image_hover: 0x0000001AL,
  markdown_image_icon_primary: 0x4A4C50FFL,
  markdown_image_bar_border: 0xDFE0E2FFL,
  markdown_sound_video_icon_primary: 0xDFE0E2FFL,
  markdown_sound_video_text_primary: 0xDFE0E2FFL,
  markdown_sound_video_bg_hover: 0xFFFFFF33L,
  markdown_sound_video_bg_player_bar: 0x000000B2L,
  markdown_sound_video_bg_progress: 0xB6B8BBFFL,
  markdown_sound_video_bg_tracker: 0xFDFDFDFFL,
  markdown_sound_video_bar_border: 0x5B5E63FFL,
  markdown_sound_video_bg_preview: 0x000000FFL,
  main_panel_bg: 0xFDFDFDFFL,
  main_panel_item_bg: 0xFFFFFFFFL,
  plugin_bg_button: 0xFFFFFFFFL,
  plugin_border: 0xFFFFFFFFL,
  plugin_row_bg_hover: 0xF1F1F1FFL,
  todo_kanban_bg_card_primary: 0xFFFFFFFFL,
  todo_kanban_bg_column_primary: 0xFAFAFAFFL,
  todo_list_bg_needs_review_main: 0xF0EDE6FFL,
  todo_list_bg_done: 0xE2EDE8FFL,
  todo_list_bg_cancel: 0xF2ECEBFFL,
  todo_list_bg_group_fade: 0xFAFAFAFFL,
  sidebar_text_primary: 0x222326FFL,
  sidebar_text_secondary: 0x4A4C50FFL,
  sidebar_text_tertiary: 0x7F8286FFL,
  sidebar_bg_selection: 0xF5F5F5FFL,
  sidebar_text_highlight: 0x111213FFL,
  sidebar_icon_primary: 0x7F8286FFL,
  sidebar_icon_secondary: 0x7F8286FFL,
  sidebar_icon_disabled: 0xB6B8BBFFL,
  sidebar_bg_item: 0xDFE0E2FFL,
  scrollbar_bg: 0xDFE0E2FFL,
  utility_gray_50: 0xFAFAFAFFL,
  utility_gray_200: 0xF1F1F1FFL,
  utility_gray_300: 0xDFE0E2FFL,
  utility_gray_700: 0x4A4C50FFL,
  utility_brand_50: 0xB8DDFFFFL,
  utility_brand_100: 0x8CBFFFFFL,
  utility_brand_200: 0x619EFFFFL,
  utility_brand_300: 0x3B7CFFFFL,
  utility_brand_400: 0x205BFFFFL,
  utility_brand_700: 0x062389FFL,
  utility_error_50: 0xFEF3F2FFL,
  utility_error_200: 0xFECDCAFFL,
  utility_error_300: 0xFDA29BFFL,
  utility_error_700: 0xB42318FFL,
  utility_warning_50: 0xFFFAEBFFL,
  utility_warning_200: 0xFEDF89FFL,
  utility_warning_300: 0xFEC84BFFL,
  utility_warning_700: 0xB54708FFL,
  utility_success_50: 0xECFDF3FFL,
  utility_success_200: 0xABEFC6FFL,
  utility_success_300: 0x75E0A7FFL,
  utility_success_700: 0x067647FFL,
  utility_blue_50: 0xEFF8FFFFL,
  utility_blue_200: 0xB2DDFFFFL,
  utility_blue_300: 0x84CAFFFFL,
  utility_blue_700: 0x175CD3FFL,
  utility_indigo_50: 0xEEF4FFFFL,
  utility_indigo_200: 0xC7D7FEFFL,
  utility_indigo_300: 0xA4BCFDFFL,
  utility_indigo_700: 0x3538CDFFL,
  utility_purple_50: 0xF4F3FFFFL,
  utility_purple_200: 0xD9D6FEFFL,
  utility_purple_300: 0xBDB4FEFFL,
  utility_purple_700: 0x5925DCFFL,
  utility_pink_50: 0xFDF2FAFFL,
  utility_pink_200: 0xFCCEEEFFL,
  utility_pink_300: 0xFAA7E0FFL,
  utility_pink_700: 0xC11574FFL,
  utility_orange_50: 0xFEF6EEFFL,
  utility_orange_200: 0xF9DBAFFFL,
  utility_orange_300: 0xF7B27AFFL,
  utility_orange_700: 0xB93815FFL,
}

///|
/// Comma's colours, dark.
pub let dark : Colors = {
  text_primary: 0xF6F6F6FFL,
  text_secondary: 0xD1D1D1FFL,
  text_tertiary: 0xA4A5A9FFL,
  text_quaternary: 0xA4A5A9FFL,
  text_white: 0xFFFFFFFFL,
  text_disabled: 0x7E8187FFL,
  text_placeholder: 0x7E8187FFL,
  text_claude: 0xD97757FFL,
  text_codex: 0x9594FCFFL,
  text_brand_primary: 0xF6F6F6FFL,
  text_brand_secondary: 0xD1D1D1FFL,
  text_brand_tertiary: 0xA4A5A9FFL,
  text_error_primary: 0xF97066FFL,
  text_warning_primary: 0xFDB022FFL,
  text_success_primary: 0x47CD89FFL,
  border_primary: 0x343538FFL,
  border_menu_primary: 0x54565AFFL,
  border_secondary: 0x27282BFFL,
  border_tertiary: 0x27282BFFL,
  border_disabled: 0x343538FFL,
  border_brand: 0x205BFFFFL,
  border_brand_solid: 0x1040F2FFL,
  border_error: 0xF97066FFL,
  border_error_solid: 0xF04438FFL,
  fg_primary: 0xFFFFFFFFL,
  fg_secondary: 0xD1D1D1FFL,
  fg_tertiary: 0xA4A5A9FFL,
  fg_quaternary: 0xA4A5A9FFL,
  fg_quinary: 0x7E8187FFL,
  fg_quinary_hover: 0xA4A5A9FFL,
  fg_senary: 0x54565AFFL,
  fg_button: 0x343538FFL,
  fg_button_active: 0x54565AFFL,
  fg_button_secondary: 0x27282BFFL,
  fg_white: 0xFFFFFFFFL,
  fg_disabled: 0x7E8187FFL,
  fg_brand_primary: 0x1040F2FFL,
  fg_error_primary: 0xF04438FFL,
  fg_warning_primary: 0xF79009FFL,
  fg_warning_secondary: 0xFDB022FFL,
  fg_success_primary: 0x17B26AFFL,
  bg_primary: 0x0F0F10FFL,
  bg_popup_primary: 0x18191BFFL,
  bg_popup_secondary: 0x27282BFFL,
  bg_secondary: 0x18191BFFL,
  bg_secondary_hover: 0x27282BFFL,
  bg_tertiary: 0x27282BFFL,
  bg_quaternary: 0x343538FFL,
  bg_quaternary_hover: 0x343538FFL,
  bg_active: 0x27282BFFL,
  bg_disabled: 0x27282BFFL,
  bg_overlay: 0x27282BFFL,
  bg_brand_primary: 0x1040F2FFL,
  bg_brand_secondary: 0x3B7CFFFFL,
  bg_brand_solid: 0x3B7CFFFFL,
  bg_brand_solid_hover: 0x1040F2FFL,
  bg_error_primary: 0xF04438FFL,
  bg_error_solid: 0xD92D20FFL,
  bg_warning_primary: 0xF79009FFL,
  bg_warning_solid: 0xDC6803FFL,
  bg_success_primary: 0x17B26AFFL,
  bg_success_solid: 0x079455FFL,
  bg_toggle: 0x7F8286FFL,
  bg_toggle_hover: 0xB6B8BBFFL,
  bg_window: 0x0F0F10FFL,
  bg_claude: 0x6A2E1BFFL,
  bg_codex: 0x4746AAFFL,
  bg_gpt: 0x353A3DFFL,
  toast_text_primary: 0xFAFAFAFFL,
  toast_text_secondary: 0xD1D1D1FFL,
  toast_icon_primary: 0xDFE0E2FFL,
  button_primary_bg: 0x205BFFFFL,
  button_primary_bg_hover: 0x1040F2FFL,
  button_primary_border: 0x1040F2FFL,
  button_primary_border_hover: 0x092FC0FFL,
  button_primary_fg: 0xFFFFFFFFL,
  button_primary_fg_hover: 0xFFFFFFFFL,
  button_secondary_bg: 0x18191BFFL,
  button_secondary_border: 0x343538FFL,
  button_secondary_fg: 0xD1D1D1FFL,
  button_secondary_color_bg: 0x18191BFFL,
  button_secondary_color_bg_hover: 0x27282BFFL,
  button_secondary_color_border: 0x343538FFL,
  button_secondary_color_border_hover: 0x343538FFL,
  button_secondary_color_fg: 0xD1D1D1FFL,
  button_secondary_color_fg_hover: 0xF1F1F1FFL,
  button_tertiary_fg: 0xA4A5A9FFL,
  button_tertiary_fg_hover: 0xEDEDEDFFL,
  button_tertiary_bg_hover: 0x27282BFFL,
  button_tertiary_color_fg: 0xD1D1D1FFL,
  button_tertiary_color_fg_hover: 0xF1F1F1FFL,
  button_tertiary_color_bg_hover: 0x27282BFFL,
  button_primary_error_bg: 0xD92D20FFL,
  button_primary_error_bg_hover: 0xB42318FFL,
  button_primary_error_border: 0xD92D20FFL,
  button_primary_error_border_hover: 0xB42318FFL,
  button_primary_error_fg: 0xFFFFFFFFL,
  button_primary_error_fg_hover: 0xFFFFFFFFL,
  dialog_bg: 0x1A1B1EFFL,
  dialog_shortcut_on_primary_bg: 0xFFFFFF29L,
  dialog_shortcut_on_primary_text: 0xFFFFFFEBL,
  menu_hover_error: 0x55160CFFL,
  toggle_button_fg_disabled: 0x54565AFFL,
  slider_handle_bg: 0x1040F2FFL,
  slider_handle_border: 0x0F0F10FFL,
  avatar_bg: 0x27282BFFL,
  avatar_profile_photo_border: 0x0F0F10FFL,
  tooltip_bg: 0x27282BFFL,
  tooltip_border: 0x343538FFL,
  tooltip_text: 0xF6F6F6FFL,
  tooltip_supporting_text: 0xD1D1D1FFL,
  tooltip_shortcut_bg: 0x54565AFFL,
  tooltip_shortcut_text: 0xD1D1D1FFL,
  ai_input_header_icon_primary: 0xB6B8BBFFL,
  ai_input_header_text_primary: 0xF5F5F5FFL,
  ai_input_header_text_secondary: 0xA4A5A9FFL,
  ai_input_panel_icon_primary: 0xB6B8BBFFL,
  ai_input_panel_icon_disabled: 0x4A4C50FFL,
  ai_input_panel_icon_fg: 0xFFFFFFFFL,
  ai_input_panel_icon_warning: 0xF79009FFL,
  ai_input_panel_text_primary: 0xF5F5F5FFL,
  ai_input_panel_text_placeholder: 0x7F8286FFL,
  ai_input_panel_text_warning: 0xF79009FFL,
  ai_input_panel_bg_input: 0x27282BFFL,
  ai_input_panel_bg_tag: 0x54565AFFL,
  ai_input_panel_text_attachment_primary: 0xF6F6F6FFL,
  ai_input_panel_text_attachment_secondary: 0x7E8187FFL,
  ai_input_panel_bg_disabled: 0x343538FFL,
  ai_input_panel_bg_attachment: 0x343538FFL,
  panel_bg_file: 0x343538FFL,
  markdown_text_primary: 0xF6F6F6FFL,
  markdown_text_secondary: 0xA4A5A9FFL,
  markdown_text_tool_primary: 0x7E8187FFL,
  markdown_audio_control_primary: 0xB6B8BBFFL,
  markdown_text_inline_primary: 0xDFE0E2FFL,
  markdown_text_inline_code: 0xF97066FFL,
  markdown_bg_inline_code: 0x222326FFL,
  markdown_text_link: 0x619EFFFFL,
  markdown_bg_message: 0x343538FFL,
  markdown_bg_table: 0x343538FFL,
  markdown_border_table: 0x4A4C50FFL,
  markdown_bg_tool: 0x18191BFFL,
  markdown_icon_primary: 0xB6B8BBFFL,
  markdown_bg_icon_hover: 0x343538FFL,
  markdown_image_bg_primary: 0x0C111DB2L,
  markdown_image_hover: 0xFFFFFF1AL,
  markdown_image_icon_primary: 0xDFE0E2FFL,
  markdown_image_bar_border: 0x343538FFL,
  markdown_sound_video_icon_primary: 0xDFE0E2FFL,
  markdown_sound_video_text_primary: 0xDFE0E2FFL,
  markdown_sound_video_bg_hover: 0xFFFFFF33L,
  markdown_sound_video_bg_player_bar: 0x0C111DB2L,
  markdown_sound_video_bg_progress: 0x5B5E63FFL,
  markdown_sound_video_bg_tracker: 0xFAFAFAFFL,
  markdown_sound_video_bar_border: 0x54565AFFL,
  markdown_sound_video_bg_preview: 0x000000FFL,
  main_panel_bg: 0x18191BFFL,
  main_panel_item_bg: 0x27282BFFL,
  plugin_bg_button: 0x54565AFFL,
  plugin_border: 0x27282BFFL,
  plugin_row_bg_hover: 0x343538FFL,
  todo_kanban_bg_card_primary: 0x18191BFFL,
  todo_kanban_bg_column_primary: 0x0F0F10FFL,
  todo_list_bg_needs_review_main: 0x3B3423FFL,
  todo_list_bg_done: 0x233E31FFL,
  todo_list_bg_cancel: 0x4C2F2DFFL,
  todo_list_bg_group_fade: 0x27282BFFL,
  sidebar_text_primary: 0xB6B8BBFFL,
  sidebar_text_secondary: 0xD1D1D1FFL,
  sidebar_text_tertiary: 0x7F8286FFL,
  sidebar_bg_selection: 0x494C50FFL,
  sidebar_text_highlight: 0xFFFFFFFFL,
  sidebar_icon_primary: 0xB6B8BBFFL,
  sidebar_icon_secondary: 0xB6B8BBFFL,
  sidebar_icon_disabled: 0x494C50FFL,
  sidebar_bg_item: 0x222326FFL,
  scrollbar_bg: 0x7E8187FFL,
  utility_gray_50: 0x18191BFFL,
  utility_gray_200: 0x343538FFL,
  utility_gray_300: 0x54565AFFL,
  utility_gray_700: 0xD1D1D1FFL,
  utility_brand_50: 0x00010BFFL,
  utility_brand_100: 0x02092BFFL,
  utility_brand_200: 0x041756FFL,
  utility_brand_300: 0x062389FFL,
  utility_brand_400: 0x092FC0FFL,
  utility_brand_700: 0x3B7CFFFFL,
  utility_error_50: 0x55160CFFL,
  utility_error_200: 0x912018FFL,
  utility_error_300: 0xFDA29BFFL,
  utility_error_700: 0xFDA29BFFL,
  utility_warning_50: 0x4E1D09FFL,
  utility_warning_200: 0x93370DFFL,
  utility_warning_300: 0xFEC84BFFL,
  utility_warning_700: 0xFEC84BFFL,
  utility_success_50: 0x053321FFL,
  utility_success_200: 0x085D3AFFL,
  utility_success_300: 0x75E0A7FFL,
  utility_success_700: 0x75E0A7FFL,
  utility_blue_50: 0x102A56FFL,
  utility_blue_200: 0x1849A9FFL,
  utility_blue_300: 0x84CAFFFFL,
  utility_blue_700: 0x84CAFFFFL,
  utility_indigo_50: 0x1F235BFFL,
  utility_indigo_200: 0x2D31A6FFL,
  utility_indigo_300: 0xA4BCFDFFL,
  utility_indigo_700: 0xA4BCFDFFL,
  utility_purple_50: 0x27115FFFL,
  utility_purple_200: 0x4A1FB8FFL,
  utility_purple_300: 0xBDB4FEFFL,
  utility_purple_700: 0xBDB4FEFFL,
  utility_pink_50: 0x4E0D30FFL,
  utility_pink_200: 0x9E165FFFL,
  utility_pink_300: 0xFAA7E0FFL,
  utility_pink_700: 0xFAA7E0FFL,
  utility_orange_50: 0x511C10FFL,
  utility_orange_200: 0x932F19FFL,
  utility_orange_300: 0xF7B27AFFL,
  utility_orange_700: 0xF7B27AFFL,
}

///|
/// A role of type: its size and line in points, and how far apart its letters are set (ems).
pub(all) struct TypeRole {
  size : Double
  line : Double
  tracking : Double
}

///|
pub let yellow_500 : Int64 = 0xEAAA08FFL

///|
pub let error_500 : Int64 = 0xF04438FFL

///|
pub let type_micro : TypeRole = { size: 11.0, line: 16.0, tracking: 0.0 }

///|
pub let type_mini : TypeRole = { size: 12.0, line: 18.0, tracking: 0.0 }

///|
pub let type_small : TypeRole = { size: 13.0, line: 20.0, tracking: 0.0 }

///|
pub let type_regular : TypeRole = { size: 15.0, line: 24.0, tracking: 0.0 }

///|
pub let type_large : TypeRole = { size: 18.0, line: 28.0, tracking: -0.01 }

///|
pub let type_title3 : TypeRole = { size: 20.0, line: 30.0, tracking: -0.01 }

///|
pub let type_title2 : TypeRole = { size: 24.0, line: 32.0, tracking: -0.02 }

///|
pub let type_title1 : TypeRole = { size: 36.0, line: 44.0, tracking: -0.02 }

///|
pub let weight_regular : Int = 450

///|
pub let weight_medium : Int = 500

///|
pub let weight_semibold : Int = 600

///|
pub let weight_bold : Int = 700

///|
pub let space_none : Double = 0.0

///|
pub let space_xxs : Double = 2.0

///|
pub let space_xs : Double = 4.0

///|
pub let space_sm : Double = 6.0

///|
pub let space_md : Double = 8.0

///|
pub let space_lg : Double = 12.0

///|
pub let space_xl : Double = 16.0

///|
pub let space_2xl : Double = 20.0

///|
pub let space_3xl : Double = 24.0

///|
pub let space_4xl : Double = 32.0

///|
pub let space_5xl : Double = 40.0

///|
pub let space_6xl : Double = 48.0

///|
pub let space_7xl : Double = 64.0

///|
pub let space_8xl : Double = 80.0

///|
pub let space_9xl : Double = 96.0

///|
pub let space_10xl : Double = 128.0

///|
pub let space_11xl : Double = 160.0

///|
pub let radius_none : Double = 0.0

///|
pub let radius_xxs : Double = 2.0

///|
pub let radius_xs : Double = 4.0

///|
pub let radius_sm : Double = 6.0

///|
pub let radius_md : Double = 8.0

///|
pub let radius_lg : Double = 10.0

///|
pub let radius_xl : Double = 12.0

///|
pub let radius_2xl : Double = 16.0

///|
pub let radius_3xl : Double = 20.0

///|
pub let radius_4xl : Double = 24.0

///|
pub let radius_full : Double = 9999.0

///|
pub let shadow_xs : (Double, Double, Int64) = (1.0, 1.0, 0x1018280DL)

///|
pub let shadow_sm : (Double, Double, Int64) = (1.5, 1.0, 0x1018281AL)

///|
pub let shadow_md : (Double, Double, Int64) = (4.0, 4.0, 0x1018281AL)

///|
pub let shadow_lg : (Double, Double, Int64) = (8.0, 12.0, 0x10182814L)

///|
pub let shadow_xl : (Double, Double, Int64) = (12.0, 20.0, 0x10182814L)

///|
pub let shadow_2xl : (Double, Double, Int64) = (24.0, 24.0, 0x1018282EL)

///|
pub let shadow_3xl : (Double, Double, Int64) = (32.0, 32.0, 0x10182824L)

///|
pub let shadow_dark_xs : (Double, Double, Int64) = (1.0, 1.0, 0x00000052L)

///|
pub let shadow_dark_sm : (Double, Double, Int64) = (1.5, 1.0, 0x0000007AL)

///|
pub let shadow_dark_md : (Double, Double, Int64) = (4.0, 4.0, 0x0000007AL)

///|
pub let shadow_dark_lg : (Double, Double, Int64) = (8.0, 12.0, 0x00000066L)

///|
pub let shadow_dark_xl : (Double, Double, Int64) = (12.0, 20.0, 0x00000066L)

///|
pub let shadow_dark_2xl : (Double, Double, Int64) = (24.0, 24.0, 0x0000008FL)

///|
pub let shadow_dark_3xl : (Double, Double, Int64) = (32.0, 32.0, 0x00000085L)

///|
pub let focus_brand : (Double, Int64) = (4.0, 0x1040F23DL)

///|
pub let focus_gray : (Double, Int64) = (4.0, 0x98A2B324L)

///|
pub let focus_error : (Double, Int64) = (4.0, 0xF044383DL)

///|
pub let ms_feedback_in : Double = 120.0

///|
pub let ms_state_change : Double = 150.0

///|
pub let ms_feedback_out : Double = 180.0

///|
pub let ms_press_travel : Double = 50.0

///|
pub let ms_press_recoil : Double = 150.0

///|
pub let ms_tooltip_enter : Double = 150.0

///|
pub let ms_tooltip_exit : Double = 125.0

///|
pub let ms_tooltip_handoff : Double = 80.0

///|
pub let ms_hover_card_enter : Double = 190.0

///|
pub let ms_hover_card_exit : Double = 140.0

///|
pub let ms_icon_swap : Double = 250.0

///|
pub let ms_dialog_enter : Double = 250.0

///|
pub let ms_dialog_exit : Double = 200.0

///|
pub let ms_image_filmstrip : Double = 400.0

///|
pub let ms_reveal_item : Double = 100.0

///|
pub let ms_reveal_stagger : Double = 30.0

///|
pub let ms_spatial_move : Double = 200.0

///|
pub let ms_reply_draw : Double = 600.0

///|
pub let ms_reply_thread_enter : Double = 380.0

///|
pub let ms_reply_thread_exit : Double = 280.0

///|
pub let ms_menu_enter : Double = 120.0

///|
pub let ms_menu_exit : Double = 80.0

///|
pub let ms_pointer_intent : Double = 100.0

///|
pub let ms_submenu_open_delay : Double = 80.0

///|
pub let ms_submenu_close_delay : Double = 80.0

///|
pub let ms_login_stage_enter : Double = 750.0

///|
pub let ms_login_stage_exit : Double = 380.0

///|
pub let ms_caret_blink : Double = 1100.0

///|
pub let ms_loading_shine : Double = 1600.0

///|
pub let ms_task_status_spin : Double = 2400.0

///|
pub let ms_toast_enter : Double = 250.0

///|
pub let ms_toast_exit : Double = 200.0

///|
pub let ms_progress_fill : Double = 900.0

///|
pub let ms_panel_enter : Double = 150.0

///|
pub let ms_panel_exit : Double = 100.0

///|
pub let ms_state_swap_exit : Double = 100.0

///|
pub let ms_state_swap_enter : Double = 150.0

///|
pub let ms_disclosure_turn : Double = 100.0

///|
pub let ms_picture_in_picture_enter : Double = 250.0

///|
pub let ms_picture_in_picture_exit : Double = 150.0

///|
pub let ms_routine_dismiss_fade : Double = 120.0

///|
pub let ms_routine_dismiss_close : Double = 220.0

///|
pub let ms_routine_cleared_enter : Double = 320.0

///|
pub let ms_tab_close_fade : Double = 120.0

///|
pub let ms_onboarding_dim : Double = 3000.0

///|
pub let ms_onboarding_logo_enter : Double = 900.0

///|
pub let ms_onboarding_intro_part_enter : Double = 700.0

///|
pub let ms_onboarding_intro_stagger : Double = 280.0

///|
pub let ms_onboarding_auto_start : Double = 8000.0

///|
pub let ms_onboarding_logo_travel : Double = 640.0

///|
pub let ms_onboarding_first_line : Double = 400.0

///|
pub let ms_onboarding_bubble_stagger : Double = 2500.0

///|
pub let ms_onboarding_settle : Double = 440.0

///|
pub let ms_onboarding_reply_beat : Double = 1000.0

///|
pub let ms_onboarding_welcome_beat : Double = 1200.0

///|
pub let ms_onboarding_shortcut_beat : Double = 3500.0

///|
pub let ms_onboarding_sweep : Double = 1000.0

///|
pub let ms_onboarding_exit : Double = 600.0

///|
pub let ms_onboarding_shortcut_done : Double = 800.0

///|
pub let ms_onboarding_key_hint : Double = 3000.0

///|
pub let ms_onboarding_light_shift : Double = 1200.0

///|
pub let ms_onboarding_light_drift : Double = 30000.0

///|
pub let ease_icon_swap : (Double, Double, Double, Double) = (0.420, 0.000, 0.580, 1.000)

///|
pub let ease_generated_media_swap : (Double, Double, Double, Double) = (0.770, 0.000, 0.175, 1.000)

///|
pub let ease_spatial_move : (Double, Double, Double, Double) = (0.770, 0.000, 0.175, 1.000)

///|
pub let ease_smooth_out : (Double, Double, Double, Double) = (0.160, 1.000, 0.300, 1.000)

///|
pub let ease_surface_smooth_out : (Double, Double, Double, Double) = (0.220, 1.000, 0.360, 1.000)

///|
pub let ease_drawer : (Double, Double, Double, Double) = (0.320, 0.720, 0.000, 1.000)

///|
pub let ease_soft_in_out : (Double, Double, Double, Double) = (0.400, 0.000, 0.200, 1.000)

///|
pub let ease_press_travel : (Double, Double, Double, Double) = (0.050, 0.000, 0.550, 0.850)

///|
pub let ease_press_recoil : (Double, Double, Double, Double) = (0.250, 0.300, 0.250, 1.320)

///|
pub let ease_sharp_in : (Double, Double, Double, Double) = (0.400, 0.000, 1.000, 1.000)

///|
pub let ease_contextual_icon : (Double, Double, Double, Double) = (0.200, 0.000, 0.000, 1.000)

///|
pub let ease_calm_in_out : (Double, Double, Double, Double) = (0.370, 0.000, 0.630, 1.000)

///|
pub let ease_calm_out : (Double, Double, Double, Double) = (0.330, 1.000, 0.680, 1.000)

///|
pub let ease_light_sweep : (Double, Double, Double, Double) = (0.650, 0.000, 0.350, 1.000)
