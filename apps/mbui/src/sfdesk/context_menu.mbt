// What a right click in the desktop's window offers, as the desktop app's own (ember apps/desktop/src/context-menu.mts:
// Electron shows none of its own): a link's (在浏览器中打开链接 and 复制链接), an image's (复制图片), then the words: a
// field's editing (剪切, 复制, 粘贴, 全选, each as it can be done now), elsewhere the words picked (复制); a line between
// them; nothing where there is none of these (the page's ground). A message of a chat's list right clicked, 复制消息链接
// and 分享这一轮 at its end (its link, its turn shared as a picture: sfbase's share_offered, the same two its ⋯ offers).
// The library's menu (@sf.dropdown) at the pointer.

///|
/// The menu while it is open: where (the pointer), the link right clicked ("" none), the image (its source, "" none),
/// the field (its id, 0 none), the words picked then ("" none), and the frame something in the page opened it in (the
/// page's right click under it, the same, opens nothing else), and what shares the turn of the message right clicked
/// (None: none). What is under way once chosen: the clipboard read for 粘贴 (into that field), the image's pixels read
/// for 复制图片.
pub struct ContextMenu {
  mut open : Bool
  mut x : Double
  mut y : Double
  mut link : String
  mut image : String
  mut field : Int
  mut words : String
  mut frame : Int
  mut copying : String
  mut share : (() -> Unit)?
  mut share_link : String
}

///|
pub let context : ContextMenu = {
  open: false,
  x: 0.0,
  y: 0.0,
  link: "",
  image: "",
  field: 0,
  words: "",
  frame: -1,
  copying: "",
  share: None,
  share_link: "",
}

///|
fn context_reset() -> Unit {
  context.open = false
  context.frame = -1
  context.copying = ""
  context.share = None
  context.share_link = ""
}

///|
/// A link in a message right clicked (what its words' rich text tells as held): its menu at the pointer, with what is
/// picked.
pub fn context_link(c : @ui.Ctx, href : String) -> Unit {
  let (x, y, _) = c.pointer()
  // (in an image's link too: the image's said with it)
  let image = if context.frame == c.frame_number() { context.image } else { "" }
  context_at(c, x, y, link=href, image~)
}

///|
/// An image in a message right clicked (box `id`, its picture from `src`): its menu at the pointer.
pub fn context_image(c : @ui.Ctx, id : Int, src : String) -> Unit {
  match c.right_clicked(id) {
    Some((x, y)) if src != "" && src != "!" => {
      let link = if context.frame == c.frame_number() { context.link } else { "" }
      context_at(c, x, y, link~, image=src)
    }
    _ => ()
  }
}

///|
fn context_at(c : @ui.Ctx, x : Double, y : Double, link? : String = "", image? : String = "") -> Unit {
  context.open = true
  context.x = x
  context.y = y
  context.link = link
  context.image = image
  context.field = 0
  context.words = c.selected_text()
  context.frame = c.frame_number()
  context.share = None
  context.share_link = ""
}

///|
/// A right click in the page (box `page`): the words picked's menu, where words are picked and nothing in the page
/// that has a menu of its own was right clicked (Ctx::menu_asked: a message's image is its own menu's alone).
pub fn context_page(c : @ui.Ctx, page : Int) -> Unit {
  match c.menu_asked(page) {
    Some((x, y)) if context.frame != c.frame_number() && c.selected_text().trim(chars=" \n\t") != "" =>
      context_at(c, x, y)
    _ => ()
  }
}

///|
/// The menu, while open: a link's items, an image's, the words'; chosen, done (what reads first, once read) and gone.
pub fn context_menu(c : @ui.Ctx) -> Unit {
  // a field right clicked anywhere: its editing
  match c.field_right_clicked() {
    Some((id, x, y)) => {
      context.open = true
      context.x = x
      context.y = y
      context.link = ""
      context.image = ""
      context.field = id
      context.words = ""
      context.frame = c.frame_number()
      context.share = None
      context.share_link = ""
    }
    None => ()
  }
  // a message right clicked: its turn offered with what else is there (its link, its picture, the words picked: told
  // the menu in the same frame), or alone. (A chat's list is built after the frame's overlays: an offer of the frame
  // before is taken as it comes.)
  match @sfbase.share_offered.val {
    Some((at, x, y, go, link)) => {
      @sfbase.share_offered.val = None
      // (not over a field right clicked)
      if (at == c.frame_number() || at == c.frame_number() - 1) && !(context.frame == at && context.field != 0) {
        if context.frame != at {
          context_at(c, x, y)
        }
        context.share = Some(go)
        context.share_link = link
      }
    }
    None => ()
  }
  context_pending(c)
  let entries : Array[@kit.Entry] = []
  let group = fn() {
    if entries.length() > 0 {
      entries.push(@kit.menu_separator())
    }
  }
  if context.open {
    let link = context.link
    if link.has_prefix("https://") || link.has_prefix("http://") {
      entries.push(@kit.menu_item("open", label=@sf.t("desktop.contextMenu.openLink")))
    }
    if link != "" {
      entries.push(@kit.menu_item("copy-link", label=@sf.t("desktop.contextMenu.copyLink")))
    }
    if context.image != "" {
      group()
      entries.push(@kit.menu_item("copy-image", label=@sf.t("desktop.contextMenu.copyImage")))
    }
    if context.field != 0 {
      let can = c.field_can(context.field)
      group()
      for x in [
        ("cut", @hostapi.text_menu_cut, "desktop.contextMenu.cut"),
        ("copy-field", @hostapi.text_menu_copy, "desktop.contextMenu.copy"),
        ("paste", @hostapi.text_menu_paste, "desktop.contextMenu.paste"),
        ("select-all", @hostapi.text_menu_select_all, "desktop.contextMenu.selectAll"),
      ] {
        entries.push(@kit.menu_item(x.0, label=@sf.t(x.2), disabled=(can & x.1) == 0))
      }
    } else if context.words.trim(chars=" \n\t") != "" {
      group()
      entries.push(@kit.menu_item("copy", label=@sf.t("desktop.contextMenu.copy")))
    }
    if context.share is Some(_) {
      group()
      if context.share_link != "" {
        entries.push(@kit.menu_item("copy-message-link", label=@sf.t("web-main.chat.copyMessageLink")))
      }
      entries.push(@kit.menu_item("share-turn", label=@sf.t("web-main.chat.shareTurn")))
    }
  }
  if entries.is_empty() {
    context.open = false
    @sf.dropdown(c, "context-menu", false, 0, [], {}, context_menu_w) |> ignore
    return
  }
  let at = (context.x, context.y, 0.0, 0.0)
  let m = @sf.dropdown(c, "context-menu", true, 0, entries, context_icons, context_menu_w, offset=0.0, at~)
  if !m.open {
    context.open = false
  }
  let field = context.field
  match m.chosen {
    Some("open") => {
      let href = context.link
      c.tell("context-open", fn() { @ui.open_url(href) |> ignore })
    }
    Some("copy-link") => c.copy_text(context.link)
    Some("copy-message-link") => {
      c.copy_text(context.share_link)
      @sfbase.say(c, @sf.t("common.link.copied"))
    }
    Some("copy") => c.copy_text(context.words)
    Some("copy-image") => context.copying = context.image
    Some("share-turn") =>
      match context.share {
        Some(go) => go()
        None => ()
      }
    Some("cut") => c.field_edit(field, @hostapi.text_menu_cut)
    Some("copy-field") => c.field_edit(field, @hostapi.text_menu_copy)
    Some("select-all") => c.field_edit(field, @hostapi.text_menu_select_all)
    // (as ⌘V: a picture on the clipboard put in as a file, else its words)
    Some("paste") => c.field_paste(field)
    _ => ()
  }
}

///|
/// What a choice reads first, taken once it is read: the image's pixels onto the clipboard as a picture (Electron's
/// copyImage: the picture decoded, as PNG). (粘贴's clipboard is read by the field: Ctx::field_paste.)
fn context_pending(c : @ui.Ctx) -> Unit {
  if context.copying != "" {
    match c.image_pixels(context.copying, image_copy_px) {
      // (onto the clipboard once the frame is built: a build let go of tells nothing)
      @ui.PixelsRead(w, h, rgba) =>
        c.after_build("context-copy-image", fn() {
          context.copying = ""
          @ui.clipboard_set_png(@pixels.png(w, h, unpremultiplied(rgba)))
        })
      @ui.PixelsFailed => context.copying = ""
      @ui.PixelsComing => ()
    }
  }
}

///|
/// Each item's mark, as the same item has it in a ⋯ (a message's: sfbase's message_items): what it does to a link, an
/// image, words picked, a message. A field's editing has none (剪切 and 全选 have no mark of their own; the four go
/// alone, in a field's menu).
let context_icons : Map[String, String] = {
  "open": "external",
  "copy-link": "link",
  "copy-image": "copy",
  "copy": "copy",
  "copy-message-link": "link",
  "share-turn": "photo",
}

///|
/// The menu's least width (the system's menus' are about as wide).
let context_menu_w : Double = 180.0
