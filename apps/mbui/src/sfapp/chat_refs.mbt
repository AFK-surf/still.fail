// References to other chats in what is written (still.fail apps/android chat/screens/Composer.kt ChatRefs, RefMarks, the
// field's InputTransformation, ChatRefMenu, markPasted; web ChatRef.tsx): in the composer a short mark, `@[its title]`,
// drawn in the accent, its brackets unseen; sent, a link the core keeps for it until then. `@` and a few letters at
// the caret open a menu over the composer of the chats it finds (the core's `chatSearch`: this workspace's, on every
// station of it, then the viewer's other workspaces', each another's saying whose); one picked goes in as the mark the
// core makes of it (`chat.ref`). A backspace just after a mark takes it whole; a chat's link pasted as it is copied
// goes in as its mark. What the field holds is read as the core reads it, by sfbase's refs.mbt (the desktop's
// composer's too); the menu is the phone's.

///|
/// The menu over the composer (ChatRefMenu): 10 in from its sides, 8 over the capsule; its card 12 in, as round as the
/// capsule, at most 320 high.
// kept across runs: a value (no field of it changes)
let ref_menu_outer : @ui.Style = @ui.css("w=Full px=S2_5 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let ref_menu_card : @ui.Style = @ui.css("w=Full p=S3")

///|
/// Its heading: 引用对话 and the words typed, 13, 12 in, 6 under.
// kept across runs: a value (no field of it changes)
let ref_menu_head : @ui.Style = @ui.css("row w=Full pl=S3 pr=S3 pb=S1_5 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ref_menu_head_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_head_query : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// What it says in place of chats: 15, muted, 12 in, 6 over, 4 under.
// kept across runs: a value (no field of it changes)
let ref_menu_note_box : @ui.Style = @ui.css("w=Full pl=S3 pr=S3 pt=S1_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let ref_menu_note : @ui.TextStyle = @ui.text_style(size=Body, color=Muted, w=Full)

///|
/// A chat: 44 high at least, 12 and 8 in, its maker's mark in 16, 10 apart; rounded concentric with the card (its
/// ground, laid under it as a layer: the capsule's corner, 12 in).
// kept across runs: a value (no field of it changes)
let ref_menu_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=@sf.ref_row_min_h,
  px=S3,
  py=S2,
  gap=S2_5,
  align=ACenter,
  radius=Inner,
)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_mark : @ui.Style = @ui.css("w=S4 align=ACenter")

///|
/// Its title and whose it is (another workspace's: its name right after the title, as a tag; another station's: that
/// station's tag), 6 apart.
// kept across runs: a value (no field of it changes)
let ref_menu_title_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ref_menu_title_box : @ui.Style = @ui.css("")

///|
/// (weight(1f, fill = false): the title as wide as it is, cut short first, with an ellipsis)
// kept across runs: a value (no field of it changes)
let ref_menu_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ref_menu_ago : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The menu's most.
let ref_menu_max : Double = 320.0
