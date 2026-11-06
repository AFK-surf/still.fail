// What lies over a chat's pane on the desktop round its composer (ember web/src/ChatSide.tsx useChatDrop, DropHint;
// ChatPage.css.ts dropHint; keymap.ts panel.close): a row of the 文件 tab carried over the pane frosting it under the
// composer, let go there into the draft. (What is picked of a message, quoted into the draft: the messages' own,
// sfpages' pick_node.mbt.)

///|
/// A row of the 文件 tab carried over box `pane` (DropHint, ChatPage.css.ts dropHint): the pane frosted over under the
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
  let (old_x, old_y, _) = c.pointer()
  let (px, py) = match drive_node_position.get() {
    Some(p) if drive_node_window.val => p
    _ => (old_x, old_y)
  }
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
/// Esc in the open chat, after the frame's (`escape`: pressed, not taken by what the frame opened): to ⌘F's bar, then
/// what is picked, then the side panel's tabs all closed (keymap.ts panel.close). Whether it took it.
fn chat_escape(c : @ui.Ctx, src : Source, escape : Bool) -> Bool {
  guard escape && app.nav.top() is Chat(r) else { return false }
  if find_chat() != "" {
    find_forget()
    c.blur()
  } else if @sfbase.pk.ts != "" {
    @sfbase.pick_clear()
  } else if side_now(src, r).0.length() > 0 {
    c.tell("chat/panel-close", fn() { side_change(src, r, "clear", None) })
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
