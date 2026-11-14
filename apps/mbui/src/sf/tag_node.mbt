// A short tag of words on a small ground of its own (a runtime's on 账号's page, a plan's on 添加账号's): 18 high, round,
// the hover's ground; its words grow with the system's size of words, and the tag with them.

///|
/// Node `tag` made a tag (ui.tsx's runtimeTag: 18 high, 4 in, round, the hover's ground) holding `words` as they say it
/// now, the caption's size, medium, muted, on one line: as high as their line where the system's size of words draws
/// it higher than 18 (box_at).
#callsite(autofill(loc))
pub fn tag_node(tag : @view.View, words : () -> String, loc~ : SourceLoc) -> Unit {
  style_node(tag, fn() { box_at(tag_kept, tag_box, tag_h, tag_words, tag.words_scale()) }, loc~)
  words_node(tag, words, fn() { tag_words }, loc~) |> ignore
}

///|
/// A tag's height as said (tag_box's h=S4_5).
// kept across runs: a value
let tag_h : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let tag_box : @ui.Style = @ui.css("row h=S4_5 px=S1 gap=SPx align=ACenter radius=Base bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let tag_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: the last theme and size of words a tag was asked at and its style (box_at), worked out again for any
// other
let tag_kept : Ref[WordsBoxKept?] = Ref(None)
