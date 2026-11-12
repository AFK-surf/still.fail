// What lies over a chat's pane on the desktop round its composer (still.fail web/src/Chat.tsx useSelectionQuote, ChatSide.tsx
// useChatDrop, DropHint; ChatPage.css.ts dropHint; keymap.ts composer.focus, panel.close): a passage of a message
// picked (with the mouse its pill, with a finger its handles and bar: sfbase's pick.mbt) quoted into the chat's draft;
// a row of the 文件 tab carried over the pane frosting it under the composer, let go there into the draft; the
// chat's own keys.

///|
/// Over chat `r`'s pane `pane` (its draft `draft`; `room`, what the composer keeps at its foot), after its composer:
/// what is picked in its messages, what is carried over it.
fn chat_layers(c : @ui.Ctx, src : Source, r : ChatRef, draft : String, room : Double) -> Unit {
  @sfbase.pick_layer(c, list_key(r), bar_foot, room, @sfbase.mouse_picks(), fn(author, words, ts, role) {
    c.tell("pick/quote", fn() {
      writing_quote(src, writing(src, draft), {
        "author": Json::string(author),
        "text": Json::string(words),
        "ts": Json::string(ts),
        "role": Json::string(role),
      })
    })
  })
}

///|
/// A row of the 文件 tab carried over box `pane` (DropHint): the pane frosted over under the
/// composer, the row's mark twice a card's and 松开以添加到消息 in its middle; let go there, into draft `draft` on
/// `station` (useChatDrop: named by its path, or as a file where the chat says so).
pub fn chat_drop(c : @ui.Ctx, src : Source, station : String, draft : String, pane : Int) -> Unit {
  match tab_take_drop(c) {
    Some((item, x, y)) if inside(c.rect_of(pane), x, y) =>
      c.tell("chat-drop/" + draft, fn() {
        writing_drop(src, writing(src, draft), station, [@sfpages.dropped_of(item)], @sfpages.drops_as_files(src, draft))
      })
    _ => ()
  }
}

///|
/// The hint while a row of the 文件 tab is carried over box `pane`: drawn only (what it is let go on is the tab's to
/// say).
pub fn drop_hint(c : @ui.Ctx, pane : Int) -> Unit {
  let item = match dragged() {
    Some(i) => i
    None => return
  }
  let (px, py, _) = c.pointer()
  if !inside(c.rect_of(pane), px, py) {
    return
  }
  let l = c.layer(fn() {
    c.layer(fn() { c.box(style=drop_ground, glass=@sf.glass_floating(), fn() {  }) |> ignore }) |> ignore
    c.box(style=drop_hint_box, fn() {
      let mark = c.box(fn() {
        if item.dir {
          @sf.icon(c, "folder", size=drop_folder, color=@sf.theme().p.muted) |> ignore
        } else {
          @sf.file_tile(c, item.name)
        }
      })
      c.look(mark, @ui.look(scale=2.0))
      c.text(@sf.t("web-main.composer.dropHere"), style=drop_hint_words) |> ignore
    })
    |> ignore
  })
  c.draw_only(l)
  c.stratum(l, Cover)
}

///|
/// Whether (x, y) is in the rectangle, where there is one.
fn inside(r : (Double, Double, Double, Double)?, x : Double, y : Double) -> Bool {
  match r {
    Some((rx, ry, rw, rh)) => x >= rx && x < rx + rw && y >= ry && y < ry + rh
    None => false
  }
}

///|
/// Chat `r`'s composer given the keyboard (Space with no field focused: 回到输入框), its draft's field (writing's), as
/// the key is pressed.
fn composer_focus(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  c.focus_field(writing(src, r.station + ":" + r.session).field)
}

///|
/// Esc in the open chat, after the frame's (not taken by what the frame opened), at its moment: to ⌘F's bar (the
/// keyboard let go: `blur`), then what is picked, then the side panel's tabs all closed (keymap.ts panel.close), but
/// where a file in the viewer is in front (sfbase's viewer_tab.mbt). Whether it took it.
fn chat_escape(src : Source, blur : () -> Unit) -> Bool {
  guard app.nav.top() is Chat(r) else { return false }
  if find_chat() != "" {
    find_forget()
    blur()
  } else if @sfbase.pk.ts != "" {
    @sfbase.pick_clear()
  } else if side_now(src, r).0.length() > 0 && @sfbase.view_tab_file(side_now(src, r).1) is None {
    // (a file in the viewer in front stays: Escape is the whole window's preview's way out, not its tab's)
    side_change(src, r, "clear", None)
  } else {
    return false
  }
  true
}

///|
/// The ground of the pane while a row is carried over it: all of it, frosted as the composer.
// kept across runs: a value (no field of it changes)
let drop_ground : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What is said in its middle: its mark over its words, 16 apart less what the mark grows by (a card's, twice).
// kept across runs: a value (no field of it changes)
let drop_hint_box : @ui.Style = @ui.css("w=Full h=Full gap=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let drop_hint_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// A folder's mark there, as large as a card's sheet.
let drop_folder : Double = 30.0
