// still.fail's styles (mbui's ui/style.mbt): the few roles words have across the app, and the boxes every page
// lays out with, made of tokens alone (tokens.mbt has the numbers). A page says these, not sizes and colours; a role
// it lacks is added here, for every page, not named after one.

///|
/// A page's title (22/30.8).
pub let title : @ui.TextStyle = @ui.text_style(size=Heading, weight=Bold, color=Fg)

///|
/// What is said under a title, before the rest (15/22, 106, 474).
pub let lead : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, color=Subtle)

///|
/// Words of the body, a row's title (15/21: Android's 15sp with no line).
pub let body : @ui.TextStyle = @ui.text_style(size=Body, color=Fg)

///|
/// A file's or a link's card's name (15/20).
pub let card_title : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, color=Fg)

///|
/// A file's or a link's card's second line under its name (11/16, muted, on one line).
pub let card_line : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// A message's words (15/24.75).
pub let message : @ui.TextStyle = @ui.text_style(size=Body, leading=message_line, color=Fg)

///|
/// Small words (12/16.8: Android's 12sp with no line).
pub let caption : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
/// What says more about something: a row's second line, a page's account of itself (13/18.2, muted).
pub let secondary : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
/// A row's value at its end (14/19.6, muted).
pub let value : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// A note: small words in lines that say how things stand (12/18, 485).
pub let note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle)

///|
/// A line of meta: what something is, a wait (13/18, muted).
pub let meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// Words in the code face (mono): their size, the font's own line.
pub let code : @ui.TextStyle = @ui.text_style(size=Ui, leading=Font, color=Fg)

///|
/// A paragraph of the body's words, in lines a little apart.
pub let paragraph : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, color=Fg)

///|
/// Back in a bar: where it goes back to, in a link's ink (C.link).
pub let back : @ui.TextStyle = @ui.text_style(size=Title, color=Link, wrap=false)

///|
/// A page's large title, on one line, its letters 0.6 closer (32/44.8).
pub let large_title : @ui.TextStyle = @ui.text_style(
  size=Display,
  weight=Bold,
  color=Fg,
  tracking=large_title_tracking,
  wrap=false,
)

///|
/// Modifiers laid over a role (`@sf.meta.then(@sf.bad)`): what went wrong, what is lacking, quieter, heavier, on one
/// line, centred across where it is.
pub let bad : @ui.TextStyle = @ui.text_style(color=Danger)

///|
pub let lacking : @ui.TextStyle = @ui.text_style(color=WarnInk)

///|
pub let quiet : @ui.TextStyle = @ui.text_style(color=Muted)

///|
pub let strong : @ui.TextStyle = @ui.text_style(weight=Semibold)

///|
pub let one_line : @ui.TextStyle = @ui.text_style(wrap=false)

///|
/// Words in the accent: its ink (AccentText), which reads on the page; the accent itself is a mark's, a fill's.
pub let accent : @ui.TextStyle = @ui.text_style(color=AccentText)

///|
/// A link's words (the accent in the dark: ui_theme's `link`).
pub let link : @ui.TextStyle = @ui.text_style(color=Link)

///|
/// Quieter still than `quiet` (the subtle grey).
pub let quieter : @ui.TextStyle = @ui.text_style(color=Subtle)

///|
/// In lines, over a role on one line.
pub let in_lines : @ui.TextStyle = @ui.text_style(wrap=true)

///|
/// As wide as where it is.
pub let full_width : @ui.Style = @ui.css("w=Full")

///|
pub let centered : @ui.TextStyle = @ui.text_style(w=Full, center=true)

///|
/// Words as wide as where they are (wrapped to it).
pub let full_words : @ui.TextStyle = @ui.text_style(w=Full)

///|
/// Things in a line, centred across it, a small gap between (an icon and its words, a label and its value).
pub let beside : @ui.Style = @ui.css("row gap=S2 align=ACenter")

