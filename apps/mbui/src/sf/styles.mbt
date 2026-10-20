// still.fail's styles (mbui's docs/style.md): the few roles words have across the app, and the boxes every page
// lays out with, made of tokens alone (tokens.mbt has the numbers). A page says these, not sizes and colours; a role
// it lacks is added here, for every page, not named after one.

///|
/// A page's title (22/28, bold).
pub let title : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Fg)

///|
/// What is said under a title, before the rest (15/22, quieter).
pub let lead : @ui.TextStyle = @ui.text_style(size=Base, color=Subtle)

///|
/// Words of the body (15/22).
pub let body : @ui.TextStyle = @ui.text_style(size=Base, color=Fg)

///|
/// A note: a small line that says how things stand (12/18, quiet).
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
