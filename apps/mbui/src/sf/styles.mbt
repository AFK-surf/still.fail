// still.fail's styles (mbui's docs/style.md): the few roles words have across the app, and the boxes every page
// lays out with, made of tokens alone (tokens.mbt has the numbers). A page says these, not sizes and colours; a role
// it lacks is added here, for every page, not named after one.

///|
/// A page's title (22/30.8, bold: Security.kt:473, NewChat.kt:183, Usage.kt:130, Workspaces.kt:191).
pub let title : @ui.TextStyle = @ui.text_style(size=Heading, weight=Bold, color=Fg)

///|
/// What is said under a title, before the rest (15/22, quieter: Security.kt:105, 106, 474).
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
/// A row's one line of small words in a list (12/16).
pub let row_caption : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, color=Muted, wrap=false)

///|
/// A note: small words in lines that say how things stand (12/18, quiet: Security.kt:110, 485).
pub let note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle)

///|
/// A note that says what went wrong.
pub let error_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger)

///|
/// A line of meta: what something is, a wait (13/18, muted).
pub let meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// Words in the code face (mono): their size, the font's own line.
pub let code : @ui.TextStyle = @ui.text_style(size=Ui, leading=Font, color=Fg)

///|
/// A paragraph of the body's words, in lines a little apart (15/22: Security.kt:105 Para).
pub let paragraph : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, color=Fg)

///|
/// Back in a bar: where it goes back to, in a link's ink (17/23.8: Parts.kt:491 NavBack, C.link).
pub let back : @ui.TextStyle = @ui.text_style(size=Title, color=Link, wrap=false)

///|
/// A compact bar's title, on one line (16/22.4, semibold: Parts.kt:527 NavBar).
pub let bar_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, wrap=false)

///|
/// A page's large title, on one line, its letters 0.6 closer (32/44.8, bold: Parts.kt:559 LargeTitle).
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
pub let lacking : @ui.TextStyle = @ui.text_style(color=Warn)

///|
pub let quiet : @ui.TextStyle = @ui.text_style(color=Muted)

///|
pub let strong : @ui.TextStyle = @ui.text_style(weight=Semibold)

///|
pub let one_line : @ui.TextStyle = @ui.text_style(wrap=false)

///|
pub let accent : @ui.TextStyle = @ui.text_style(color=Accent)

///|
/// A link's words (Theme.kt C.link: the accent's darker ink on paper, the accent in the dark: ui_theme's `link`).
pub let link : @ui.TextStyle = @ui.text_style(color=Link)

///|
/// Quieter still than `quiet` (the subtle grey).
pub let quieter : @ui.TextStyle = @ui.text_style(color=Subtle)

///|
/// In lines, over a role on one line.
pub let in_lines : @ui.TextStyle = @ui.text_style(wrap=true)

///|
/// A page's words in from its sides as a card's (20), a little under them.
pub let page_words : @ui.Style = @ui.css("w=Full px=S5 pb=S1")

///|
/// A page's words under a card, in from its sides as the card's words (20), a little over them.
pub let under_card_words : @ui.Style = @ui.css("w=Full px=S5 pt=S1_5")

///|
/// As wide as where it is.
pub let full_width : @ui.Style = @ui.css("w=Full")

///|
pub let centered : @ui.TextStyle = @ui.text_style(w=Full, center=true)

///|
/// Words as wide as where they are (wrapped to it).
pub let full_words : @ui.TextStyle = @ui.text_style(w=Full)

///|
/// A page that holds a column a phone's width at most in its middle (phone_column), as far in from the window's
/// sides as a phone's page (28) where the window is narrower.
pub let phone_page : @ui.Style = @ui.css("row w=Full h=Full px=S7 align=ACenter justify=JCenter")

///|
/// The column in a phone_page: as wide as it, up to a phone's width.
pub let phone_column : @ui.Style = @ui.style(w=Full, max_w=phone_max)

///|
/// Things in a line, centred across it, a small gap between (an icon and its words, a label and its value).
pub let beside : @ui.Style = @ui.css("row gap=S2 align=ACenter")

