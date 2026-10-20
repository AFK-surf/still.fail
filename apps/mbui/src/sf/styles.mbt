// still.fail's styles (mbui's docs/style.md): the few roles words have across the app, and the boxes every page
// lays out with, made of tokens alone (tokens.mbt has the numbers). A page says these, not sizes and colours; a role
// it lacks is added here, for every page, not named after one.

///|
/// A page's title (22/30.8, bold: Security.kt:473, NewChat.kt:183, Usage.kt:130, Workspaces.kt:191).
pub let title : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Fg)

///|
/// What is said under a title, before the rest (15/22, quieter: Security.kt:105, 106, 474).
pub let lead : @ui.TextStyle = @ui.text_style(size=lead_size, color=Subtle)

///|
/// Words of the body, a row's title (15/21: Android's 15sp with no line).
pub let body : @ui.TextStyle = @ui.text_style(size=Base, color=Fg)

///|
/// A file's or a link's card's name (15/20).
pub let card_title : @ui.TextStyle = @ui.text_style(size=card_title_size, color=Fg)

///|
/// A message's words (15/24.75).
pub let message : @ui.TextStyle = @ui.text_style(size=message_size, color=Fg)

///|
/// Small words (12/16.8: Android's 12sp with no line).
pub let caption : @ui.TextStyle = @ui.text_style(size=caption_size, color=Muted)

///|
/// A row's one line of small words in a list (12/16).
pub let row_caption : @ui.TextStyle = @ui.text_style(size=row_caption_size, color=Muted, wrap=false)

///|
/// A note: small words in lines that say how things stand (12/18, quiet: Security.kt:110, 485).
pub let note : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle)

///|
/// A note that says what went wrong.
pub let error_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger)

///|
/// A line of meta: what something is, a wait (13/18, muted).
pub let meta : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
/// Words in the code face (mono): their size, the font's own line.
pub let code : @ui.TextStyle = @ui.text_style(size=code_size, color=Fg)

///|
/// Modifiers laid over a role (`@sf.meta.then(@sf.bad)`): what went wrong, quieter, heavier, on one line, centred
/// across where it is.
pub let bad : @ui.TextStyle = @ui.text_style(color=Danger)

///|
pub let quiet : @ui.TextStyle = @ui.text_style(color=Muted)

///|
pub let strong : @ui.TextStyle = @ui.text_style(weight=Semibold)

///|
pub let one_line : @ui.TextStyle = @ui.text_style(wrap=false)

///|
pub let centered : @ui.TextStyle = @ui.text_style(w=Full, center=true)

///|
/// A page that holds a column a phone's width at most in its middle (phone_column), as far in from the window's
/// sides as a phone's page (28) where the window is narrower.
pub let phone_page : @ui.Style = @ui.style(row=true, w=Full, h=Full, px=S7, align=ACenter, justify=JCenter)

///|
/// The column in a phone_page: as wide as it, up to a phone's width.
pub let phone_column : @ui.Style = @ui.style(w=Full, max_w=phone_max)

///|
/// Things in a line, centred across it, a small gap between (an icon and its words, a label and its value).
pub let beside : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)
