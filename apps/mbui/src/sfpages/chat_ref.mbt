// The `@` menu over the desktop's composer (ember web/src/ChatRef.tsx ChatRefMenu, Chat.tsx useComposerText's
// reference and its keys; ChatRef.css.ts refMenu, refHead, refQuery, refEmpty, refItem, refLogo, refTitleCell,
// refTitle, refChipStation, refTime): `@` and a few letters at the caret offer the workspace's chats, then the
// viewer's other workspaces' (the core's `chatSearch`); the one picked goes in as its mark. What the field's words hold
// (the `@words`, the marks) is sfbase's refs.mbt's, as the core reads it.

///|
/// The menu for draft `w` while its field (focused, the words not locked) is at `@` and a few letters, over the
/// composer `cap` and as wide (ChatRefMenu): its head (引用对话 and the words typed), then the chats they find, each its
/// agent's mark, its title (another workspace's or station's whose after it), when it was last active; or what it says
/// in their place. ↑ / ↓ choose (round), Enter or Tab (the field leaves them to it: ref_keys) or a press puts the one
/// chosen in; Escape closes it for this `@`. Whether it is open.
fn ref_menu(
  c : @ui.Ctx,
  src : Source,
  spec : ComposerSpec,
  w : Writing,
  cap : Int,
  focused : Bool,
) -> Bool {
  let key = ref_menu_key
  let into = workspace_of(spec.station)
  let open = match ref_found(src, spec, w, focused) {
    None => false
    Some((query, topic, chats)) => {
      let n = chats.length()
      let pick = fn(x : Json) {
        let item = @sfbase.chat_item(x)
        @sfbase.refs_pick(c, src, w.key, w.field, into, item.station, item.id, item.title, fn(why) {
          toast_later(@sf.t("web-main.composer.refFailed", args=[("title", item.title), ("error", why)]))
        })
      }
      // ↑ ↓ Enter Tab as each comes, before the field sees it: an Escape after them, before a frame, closes the menu,
      // not what they chose
      if n > 0 {
        c.on_key(key + "/" + w.key, fn(code, mods) {
          if mods != 0 {
            false
          } else if code == @ui.key_code_down || code == @ui.key_code_up {
            @sfbase.refs_active(w.key, n, by=if code == @ui.key_code_down { 1 } else { -1 }) |> ignore
            ref_keyed.val = w.key
            true
          } else if code == @ui.key_code_enter || code == @ui.key_tab {
            pick(chats[@sfbase.refs_active(w.key, n)])
            true
          } else {
            false
          }
        })
      }
      // (moved to by the keys since the frame before: in view where the menu scrolls)
      let keyed = ref_keyed.val == w.key
      if keyed {
        ref_keyed.val = ""
      }
      // Escape (or a press away from the composer): closed for this `@`, at the moment of what dismissed it
      let shown : Ref[Bool] = Ref(true)
      c.with_dismissed(fn(_) { @sfbase.refs_close(w.key) }, fn() {
        shown.val = @kit.popover(
          c,
          key,
          true,
          cap,
          side=Top,
          along=Start,
          offset=ref_menu_off,
          label=@sf.t("web-main.chatRef.title"),
          focus=false,
          look=fn(c, s, body) {
            let width = match c.rect_of(cap) {
              Some((_, _, cw, _)) => cw
              None => ref_menu_least
            }
            // (its chats scrolling past its most, or past what the window leaves them)
            c.box(style=ref_menu_box.then(@ui.style(w=Fixed(width))), glass=@sf.glass_floating(), fn() {
              @kit.in_room(c, s, key="composer/ref-list", most=ref_menu_max - 2.0 * @sf.panel_pad, body) |> ignore
            })
            |> ignore
          },
          fn() {
            c.box(style=@sf.full_width, fn() {
              ref_menu_body(c, query, topic, chats, @sfbase.refs_active(w.key, n), keyed, pick, w.key)
            })
            |> ignore
          },
        ).value
      })
      shown.val
    }
  }
  if !open {
    @kit.popover(c, key, false, cap, fn() {  }) |> ignore
  }
  open
}

///|
/// The draft whose `@` menu ↑ or ↓ chose another in since it was last built ("" none): what it shows it brings into
/// view.
let ref_keyed : Ref[String] = Ref("")

///|
/// The composer's `@` menu's key (its popover's; its panel `/panel`).
let ref_menu_key : String = "composer/ref-menu"

///|
/// What the menu of draft `w` offers while its field (`focused`, the words not locked) is at `@` and a few letters:
/// the words after the `@`, the core's `chatSearch` for them and the chats it found (this workspace's, on every station
/// of it, then the viewer's others', not the chat written in); None while it is in none.
fn ref_found(src : Source, spec : ComposerSpec, w : Writing, focused : Bool) -> (String, @sfbase.Topic, Array[Json])? {
  guard focused && !spec.locked && @sfbase.refs_at(w.key) is Some((_, query)) else { return None }
  let params : Map[String, Json] = {
    "scope": Json::string(workspace_of(spec.station)),
    "query": Json::string(query),
    "station": Json::string(spec.station),
    "limit": Json::number(ref_shown.to_double()),
    "elsewhere": Json::boolean(true),
  }
  if spec.session != "" {
    params["exclude"] = Json::string(spec.session)
  }
  let topic = @sfbase.refs_search(src, w.key, params)
  Some((query, topic, items(topic.value, "items")))
}

///|
/// The keys the field of draft `w` leaves to its menu: ↑ / ↓, Enter and Tab while it offers chats (the web's
/// preventDefault on them), none else.
fn ref_leaves(src : Source, spec : ComposerSpec, w : Writing, focused : Bool) -> Array[Int] {
  match ref_found(src, spec, w, focused) {
    Some((_, _, chats)) if chats.length() > 0 => ref_keys
    _ => []
  }
}

///|
/// The keys the field leaves to the menu while it is open (the web's preventDefault on them).
// kept across runs: a value (no field of it changes)
let ref_keys : Array[Int] = [@ui.key_code_up, @ui.key_code_down, @ui.key_code_enter, @ui.key_tab]

///|
fn ref_menu_body(
  c : @ui.Ctx,
  query : String,
  topic : @sfbase.Topic,
  chats : Array[Json],
  active : Int,
  keyed : Bool,
  pick : (Json) -> Unit,
  draft : String,
) -> Unit {
  c.box(style=ref_head, fn() {
    c.text(@sf.t("web-main.chatRef.title"), style=ref_head_words) |> ignore
    if query != "" {
      c.text(query, style=ref_query) |> ignore
    }
  })
  |> ignore
  if topic.value is None {
    c.box(style=ref_empty, fn() {
      if topic.error is Some(_) {
        c.text(@sf.t("web-main.chatRef.update", args=[("app", "still.fail")]), style=ref_empty_words) |> ignore
      } else {
        @sf.wait_line(c, @sf.t("common.reading"), key="chat-ref")
      }
    })
    |> ignore
    return
  }
  if chats.is_empty() {
    c.box(style=ref_empty, fn() {
      c.text(@sf.t(if query != "" { "web-main.chatRef.noMatch" } else { "web-main.chatRef.none" }), style=ref_empty_words)
      |> ignore
    })
    |> ignore
    return
  }
  for i, x in chats {
    let item = @sfbase.chat_item(x)
    let id = c.id("composer/ref/" + item.station + "\t" + item.id)
    // (put in as it is let go: an Escape after it, before a frame, closes the menu, not the choice)
    c.on_press(id, fn() { pick(x) })
    // (the pointer moving over a chat chooses it, as the keys do; resting, it leaves the keys' choice be)
    if c.hand_on(id) && i != active {
      @sfbase.refs_active(draft, chats.length(), to=i) |> ignore
    }
    // (moved to by the keys: in view where the menu scrolls)
    if keyed && i == active {
      c.show(id)
    }
    let b = c.box(style=(if i == active { ref_item_on } else { ref_item }).then(@sf.pick_high()), id~, fn() {
      c.box(style=ref_logo, fn() {
        match item.agents.get(0) {
          Some(a) => @sf.maker_mark(c, a.maker, a.runtime, ref_logo_size) |> ignore
          None => ()
        }
      })
      |> ignore
      c.box(style=ref_title_cell, fn() {
        c.text(item.title, style=ref_title) |> ignore
        // another workspace's: whose; another station's (the core says, `otherStation`): its mark and name (the row
        // keeps its three columns)
        let outside = text(Some(x), "outside")
        if outside != "" {
          c.box(style=ref_chip_station, fn() {
            @sf.workspace_badge(c, outside, text(Some(x), "outsideEmoji"), text(Some(x), "outsideIcon"), ref_chip_icon)
            c.text(outside, style=ref_chip_words) |> ignore
          })
          |> ignore
        } else if flag(Some(x), "otherStation") {
          c.box(style=ref_chip_station, fn() {
            @sf.station_mark(c, item.station_emoji, item.station_icon, ref_chip_icon, @sf.theme().p.muted)
            c.text(item.station_name, style=ref_chip_words) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      c.text(item.ago, style=ref_time) |> ignore
    })
    c.semantics(b, Button, id~, label=item.title, selected=i == active)
  }
}

///|
/// 8 over the composer (refMenu: bottom 8).
let ref_menu_off : Double = 8.0

///|
/// (laid out before the composer's box has been: the web's least composer)
let ref_menu_least : Double = 320.0

///|
/// How many chats it offers (SHOWN).
let ref_shown : Int = 8

///|
/// A chat's agent's mark (ModelLogo 14).
let ref_logo_size : Double = 14.0

///|
/// Another station's mark (StationMark 11).
let ref_chip_icon : Double = 11.0

///|
/// The menu (refMenu): a small panel's list, padded as one (panel_pad), its rows concentric, glass, a light shadow,
/// 320 high at most, scrolling.
// kept across runs: a value (no field of it changes)
let ref_menu_box : @ui.Style = @ui.style(p=@sf.room_of(@sf.panel_pad), radius=@sf.ref_menu_corner, shadow=Sm)

///|
/// (refMenu: maxHeight 320)
let ref_menu_max : Double = 320.0

///|
/// Its head (refHead): a small panel's heading (its words a row's padding in, as far under its top as a row's words, 4
/// over the chats), 6 between, the meta size, muted (refQuery: the words typed, the text's).
// kept across runs: a value (no field of it changes)
let ref_head : @ui.Style = @ui.css("row w=Full px=S2_5 pt=S1_5 pb=S1 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ref_head_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ref_query : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// What it says in place of chats (refEmpty): 6 by 10 in, the ui size, muted.
// kept across runs: a value (no field of it changes)
let ref_empty : @ui.Style = @ui.css("w=Full px=S2_5 py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ref_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// A chat (refItem): its mark in 16, its title, when; 10 apart, a menu's row (as far in; as high, the screen's:
/// @sf.pick_high), concentric with the menu; the one chosen on the hover's ground.
// kept across runs: a value (no field of it changes)
let ref_item : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=S2_5,
  py=@sf.room_of(@sf.menu_row_over),
  gap=S2_5,
  align=ACenter,
  radius=@sf.ref_item_corner,
)

///|
// kept across runs: a value (no field of it changes)
let ref_item_on : @ui.Style = ref_item.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let ref_logo : @ui.Style = @ui.css("w=S4 align=ACenter justify=JCenter")

///|
/// Its title and whose (refTitleCell, refTitle): the title cut short first.
// kept across runs: a value (no field of it changes)
let ref_title_cell : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ref_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
/// Whose it is (refChipStation): a pill 4 after the title, 1 by 6 in, the meta size, muted, on the hover's ground.
// kept across runs: a value (no field of it changes)
let ref_chip_station : @ui.Style = @ui.css("row ml=S1 px=S1_5 py=SPx gap=SPx radius=Full bg=Hover align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ref_chip_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// When (refTime): the meta size, muted.
// kept across runs: a value (no field of it changes)
let ref_time : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)
