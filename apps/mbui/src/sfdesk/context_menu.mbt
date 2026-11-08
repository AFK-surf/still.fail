// What a right click in the desktop's window offers, as the desktop app's own (still.fail apps/desktop/src/context-menu.mts:
// Electron shows none of its own): a link's (在浏览器中打开链接 and 复制链接), an image's (复制图片), then the words: a
// field's editing (剪切, 复制, 粘贴, 全选, each as it can be done now), elsewhere the words picked (复制); a line between
// them; nothing where there is none of these (the page's ground). A message of a chat's list right clicked offers its
// words, link and turn's picture at the end (sfbase's share_offered, the same actions its ⋯ offers).
// The library's menu (@sf.dropdown) at the pointer.

///|
/// The menu while it is open: where (the pointer: the right click's place, which says the right click it is open for:
/// context_opened_at), the link right clicked ("" none), the image (its source, "" none), the field (its id, 0 none),
/// the words picked then ("" none), and what shares the turn of the message right clicked (None: none). What is under
/// way once chosen: the clipboard read for 粘贴 (into that field), the image's pixels read for 复制图片.
pub struct ContextMenu {
  mut open : Bool
  mut x : Double
  mut y : Double
  mut link : String
  mut image : String
  mut field : Int
  mut words : String
  mut copying : String
  mut share : (() -> Unit)?
  mut share_link : String
  mut share_words : String
  mut share_key : String
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
  copying: "",
  share: None,
  share_link: "",
  share_words: "",
  share_key: "",
}

///|
/// Whether the menu is open for the right click made at (x, y): opened there by what else that right click asked (the
/// page's right click under an image's, a message's turn offered with the words picked in it), whichever part said it
/// first, and wherever in the frame each is built (a chat's list after the overlays). One right click, one place, as
/// each that reads it has it (Ctx::menu_asked, Ctx::right_clicked, Ctx::field_right_clicked: the same); another made
/// there while the menu shows is the same menu's, what is under it the same.
fn context_opened_at(x : Double, y : Double) -> Bool {
  context.open && context.x == x && context.y == y
}

///|
/// Told as the menu is opened (context_at): what shows it, built apart from what was right clicked (another old view's),
/// follows it.
// kept across runs: a count told, nothing reads what it is (only that it changed)
let context_told : @signals.Signal[Int] = @signals.signal(0)

///|
/// The menu opened at (x, y) by what is right clicked in a page (context_at), told to what shows it.
fn context_asked(c : @ui.Ctx, x : Double, y : Double, link? : String = "", image? : String = "") -> Unit {
  context_at(c, x, y, link~, image~)
  context_told.set(@signals.untracked(fn() { context_told.get() }) + 1)
}

///|
fn context_reset() -> Unit {
  context.open = false
  context.copying = ""
  context.share = None
  context.share_link = ""
  context.share_words = ""
  context.share_key = ""
}

///|
/// A link in a message right clicked (what its words' rich text tells as held): its menu at the pointer, with what is
/// picked.
pub fn context_link(c : @ui.Ctx, href : String) -> Unit {
  let (x, y, _) = c.pointer()
  // (in an image's link too: the image's said with it)
  let image = if context_opened_at(x, y) { context.image } else { "" }
  context_asked(c, x, y, link=href, image~)
}

///|
/// An image in a message right clicked (box `id`, its picture from `src`): its menu at the pointer.
pub fn context_image(c : @ui.Ctx, id : Int, src : String) -> Unit {
  match c.right_clicked(id) {
    Some((x, y)) if src != "" && src != "!" => {
      let link = if context_opened_at(x, y) { context.link } else { "" }
      context_asked(c, x, y, link~, image=src)
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
  context.share = None
  context.share_link = ""
  context.share_words = ""
  context.share_key = ""
}

///|
/// A right click in the page (box `page`): the words picked's menu, where words are picked and nothing in the page
/// that has a menu of its own was right clicked (Ctx::menu_asked: a message's image is its own menu's alone).
pub fn context_page(c : @ui.Ctx, page : Int) -> Unit {
  match c.menu_asked(page) {
    Some((x, y)) if !context_opened_at(x, y) && c.selected_text().trim(chars=" \n\t") != "" =>
      context_asked(c, x, y)
    _ => ()
  }
}

///|
/// A page made once (node `v`, the tree's), as an old view's page is in its frame (page_one's c.selectable and
/// context_page): its words in pieces picked with the mouse (@ui.words_picked), and a right click in it the words
/// picked's menu, where nothing in it that takes a press of its own was right clicked (Tree::menu_at: the topmost that
/// does is asked), as the click's event, at its moment.
pub fn context_node(v : @view.View) -> Unit {
  @ui.words_picked(v)
  v.on_menu(fn(m) {
    let c = @ui.current()
    if !context_opened_at(m.wx, m.wy) && c.selected_text().trim(chars=" \n\t") != "" {
      context_asked(c, m.wx, m.wy)
    }
  })
  |> ignore
}

///|
/// The menu, while open: a link's items, an image's, the words'; chosen, done (what reads first, once read) and gone.
pub fn context_menu(c : @ui.Ctx) -> Unit {
  // (built again as the menu is opened or a message's turn offered, wherever that was built)
  context_told.get() |> ignore
  @sfbase.share_offered_told.get() |> ignore
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
      context.share = None
      context.share_link = ""
      context.share_words = ""
      context.share_key = ""
    }
    None => ()
  }
  // a message right clicked: its turn offered with what else that right click opened the menu for (its link, its
  // picture, the words picked: context_opened_at), or alone. (A chat's list is built after the frame's overlays: its
  // offer is taken as it is told, share_offered_told, the menu's then, built again for it.)
  match @sfbase.share_offered.val {
    Some((x, y, go, link, words, key)) => {
      @sfbase.share_offered.val = None
      // (not over a field right clicked)
      if !(context_opened_at(x, y) && context.field != 0) {
        if !context_opened_at(x, y) {
          context_at(c, x, y)
        }
        context.share = Some(go)
        context.share_link = link
        context.share_words = words
        context.share_key = key
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
      if context.share_words.trim(chars=" \n\t") != "" {
        entries.push(@kit.menu_item("copy-message", label=@sf.t("web-main.chat.copyMessage")))
      }
      if context.share_link != "" {
        entries.push(@kit.menu_item("copy-message-link", label=@sf.t("web-main.chat.copyMessageLink")))
      }
      entries.push(@kit.menu_item("share-turn", label=@sf.t("web-main.chat.selectMessages")))
    }
  }
  if entries.is_empty() {
    context.open = false
    context_lit()
    @sf.dropdown(c, "context-menu", false, 0, [], {}, context_menu_w) |> ignore
    return
  }
  let at = (context.x, context.y, 0.0, 0.0)
  // (dismissed, closed at the moment of what dismissed it: Escape, a press beside it)
  let menu : Ref[@kit.Menu?] = Ref(None)
  c.with_dismissed(
    fn(_) {
      context.open = false
      context_lit()
    },
    fn() {
      menu.val = Some(@sf.dropdown(c, "context-menu", true, 0, entries, context_icons, context_menu_w, offset=0.0, at~))
    },
  )
  let m = menu.val.unwrap()
  if m.chosen is Some(_) {
    context.open = false
  }
  context_lit()
  let field = context.field
  match m.chosen {
    Some("open") => {
      let href = context.link
      c.tell("context-open", fn() { @ui.open_url(href) |> ignore })
    }
    Some("copy-link") => c.copy_text(context.link)
    Some("copy-message") => {
      c.copy_text(context.share_words)
      @sfbase.say(c, @sf.t("common.copied"))
    }
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
/// The message the menu is open for told (sfbase's message_menu): its row lit while it is, none once it is gone.
fn context_lit() -> Unit {
  @sfbase.message_menu.set(if context.open && context.share is Some(_) { context.share_key } else { "" })
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
// kept across runs: a value (nothing is put in it or taken out)
let context_icons : Map[String, String] = {
  "open": "external",
  "copy-link": "link",
  "copy-image": "copy",
  "copy": "copy",
  "copy-message": "copy",
  "copy-message-link": "link",
  "share-turn": "check-circle",
}

///|
/// The menu's least width (the system's menus' are about as wide).
let context_menu_w : Double = 180.0
