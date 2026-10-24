// Shared welcome/credential presentation. Colours and type resolve in login_theme's scoped roles;
// these styles do not know about authentication or the app's state.

///|
pub let login_action : @ui.Style = @ui.style(
  row=true, w=Full, min_h=login_control_min, px=S4, py=S3, radius=login_pill_radius,
  bg=Surface, border=B1, border_color=Fg, align=ACenter, justify=JCenter,
  disabled=@ui.patch(opacity=O50),
)

///|
pub let login_primary_action : @ui.Style = login_action.then(@ui.style(bg=Fg))

///|
pub let login_action_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Semibold, center=true, w=Full, color=Fg)

///|
pub let login_primary_words : @ui.TextStyle = login_action_words.then(@ui.text_style(color=Bg))

///|
pub let login_page : @ui.Style = @ui.style(w=Full, p=S6, align=ACenter)

///|
pub let login_column : @ui.Style = @ui.style(w=Full, max_w=phone_max, gap=S4)

///|
pub let login_title : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Fg, w=Full)

///|
pub let login_welcome_title : @ui.TextStyle = login_title.then(@ui.text_style(center=true))

///|
pub let login_body : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, w=Full)

///|
pub let login_explanation : @ui.TextStyle = login_body.then(@ui.text_style(color=Muted))

///|
pub let login_welcome_body : @ui.TextStyle = login_explanation.then(@ui.text_style(center=true))

///|
pub let login_hint : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
pub let login_notice : @ui.Style = @ui.style(w=Full, p=S4, radius=Xl, bg=Card)

///|
pub let login_field_label : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Semibold, color=Fg, w=Full)

///|
pub let login_field : @ui.Style = @ui.style(w=Full, min_h=login_control_min, px=S4, py=S3_5, radius=Xl, border=B1, border_color=Border)

///|
pub let login_error : @ui.TextStyle = login_body.then(@ui.text_style(color=Danger))
