// References to other chats in what is written (ember apps/android chat/screens/Composer.kt ChatRefs, RefMarks, the
// field's InputTransformation, ChatRefMenu, markPasted; web ChatRef.tsx): in the composer a short mark, `@[its title]`,
// drawn in the accent, its brackets unseen; sent, a link the core keeps for it until then. `@` and a few letters at
// the caret open a menu over the composer of the chats it finds (the core's `chatSearch`: this workspace's, on every
// station of it, then the viewer's other workspaces', each another's saying whose); one picked goes in as the mark the
// core makes of it (`chat.ref`). A backspace just after a mark takes it whole; a chat's link pasted as it is copied
// goes in as its mark. What the field holds is read as the core reads it, by sfbase's refs.mbt (the desktop's
// composer's too); the menu is the phone's.

///|
/// Words the app put in draft `d`'s field itself (kept, put back, given up as sent): put there, taken as they are, not
/// as written (Android's InputTransformation sees the user's edits only; what the app puts in goes as it is).
fn ref_field_put(d : Draft, words : String, caret? : Int) -> Unit {
  @sfbase.refs_put(d.key, d.field, words, caret?)
  d.text.set(words)
}

// ── the `@` menu ────────────────────────────────────────────────────────

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

///|
/// `@` and a few letters at the caret of the field (focused, nothing selected, words to send not locked): the chats
/// they find over the composer; one picked goes in as its mark, in the `@words`' place, a space after it.
fn chat_ref_menu(c : @ui.Ctx, src : Source, d : Draft, station : String, here : String, key : String, locked : Bool) -> Unit {
  let found = if c.editor_focused(key) && !locked { @sfbase.refs_at(d.key) } else { None }
  guard found is Some((_, query)) else { return }
  let params : Map[String, Json] = {
    "scope": Json::string(workspace_of(station)),
    "query": Json::string(query),
    "station": Json::string(station),
    "limit": Json::number(8.0),
    "elsewhere": Json::boolean(true),
  }
  if here != "" {
    params["exclude"] = Json::string(here)
  }
  let topic = (src.topic)("chatSearch", params)
  let chats = match topic.value {
    Some(v) => items(Some(v), "items")
    None => []
  }
  c.box(style=ref_menu_outer, fn() {
    c.box(style=ref_menu_card, id=ref_menu_id(c, d.key), fn() {
      let g = c.layer(fn() { floating_ground(c, Fill(1.0)) |> ignore })
      c.draw_only(g)
      c.capped("chat-ref/" + d.key, ref_menu_max - 24.0, fn() {
        c.box(style=@sf.full_width, fn() {
          c.box(style=ref_menu_head, fn() {
            c.text(tr("android-chat.ref.title"), style=ref_menu_head_words) |> ignore
            if query != "" {
              c.text(query, style=ref_menu_head_query) |> ignore
            }
          })
          |> ignore
          if topic.value is None && topic.error is Some(_) {
            c.box(style=ref_menu_note_box, fn() {
              c.text(fill("android-chat.ref.update", [("app", "still.fail")]), style=ref_menu_note) |> ignore
            })
            |> ignore
          } else if topic.value is None {
            c.box(style=ref_menu_note_box, fn() { @sf.wait_line(c, tr("common.reading"), key="chat-ref") })
            |> ignore
          } else if chats.is_empty() {
            c.box(style=ref_menu_note_box, fn() {
              c.text(
                tr(if query != "" { "android-chat.ref.none.match" } else { "android-chat.ref.none" }),
                style=ref_menu_note,
              )
              |> ignore
            })
            |> ignore
          } else {
            for x in chats {
              let item = chat_item(x)
              let outside = text(Some(x), "outside")
              let id = c.id("chat-ref/" + item.station + "/" + item.id)
              if c.clicked(id) {
                ref_pick(c, src, d, station, item)
              }
              c.box(style=ref_menu_row, id~, fn() {
                c.box(style=ref_menu_mark, fn() {
                  match item.agents.get(0) {
                    Some(a) => @sf.maker_mark(c, a.maker, a.runtime, 14.0) |> ignore
                    None => ()
                  }
                })
                |> ignore
                c.box(style=ref_menu_title_line, fn() {
                  c.box(style=ref_menu_title_box, fn() { c.text(item.title, style=ref_menu_title) |> ignore }) |> ignore
                  if outside != "" {
                    c.box(style=words_tag, fn() { c.text(outside, style=words_tag_words) |> ignore }) |> ignore
                  } else if flag(Some(x), "otherStation") {
                    station_tag(c, {
                      address: item.station,
                      name: item.station_name,
                      emoji: item.station_emoji,
                      icon: item.station_icon,
                      via: "",
                    })
                  }
                })
                |> ignore
                if item.ago != "" {
                  c.text(item.ago, style=ref_menu_ago) |> ignore
                }
                // Composer.kt ChatRefMenu: clip(Smooth(concentric(ComposerCorner, 12))).clickable
                @motion.ripple(c, id, @sf.inner_corner(composer_corner, 12.0))
              })
              |> ignore
            }
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A chat picked in the menu: its mark from the core (`chat.ref`, which keeps its link until it is sent), in the
/// `@words`' place if they are still there, a space after it, the caret after that; the menu closed for this `@`.
/// Failing, a toast says why.
fn ref_pick(c : @ui.Ctx, src : Source, d : Draft, station : String, item : ChatItem) -> Unit {
  @sfbase.refs_pick(c, src, d.key, d.field, workspace_of(station), item.station, item.id, item.title, fn(why) {
    say(c, fill("android-chat.ref.failed", [("error", why)]))
  })
}

///|
/// The menu's box (a draft's): the composer's own, as its capsule is, for what a press outside the composer lets go of.
fn ref_menu_id(c : @ui.Ctx, key : String) -> Int {
  c.id("chat-ref-menu/" + key)
}
