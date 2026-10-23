// What a right click in the wide frame's page offers, as the desktop app's own (ember apps/desktop/src/context-menu.mts:
// Electron shows none of its own): a link's (在浏览器中打开链接 and 复制链接), then the words picked (复制), a line between
// them; nothing where there is neither (the page's ground). The app's menu (wide_menu) at the pointer.

///|
/// The menu while it is open: where (the pointer), the link right clicked ("" none), the words picked then ("" none),
/// and the frame a link's opened it in (the page's right click under it, the same, opens nothing else).
priv struct WideContext {
  mut open : Bool
  mut x : Double
  mut y : Double
  mut link : String
  mut words : String
  mut frame : Int
}

///|
let wide_context : WideContext = { open: false, x: 0.0, y: 0.0, link: "", words: "", frame: -1 }

///|
/// A link in a message right clicked (what its words' rich text tells as held): its menu at the pointer, with what is
/// picked.
fn wide_context_link(c : @ui.Ctx, href : String) -> Unit {
  let (x, y, _) = c.pointer()
  wide_context_at(c, x, y, href)
  wide_context.frame = c.frame_number()
}

///|
fn wide_context_at(c : @ui.Ctx, x : Double, y : Double, link : String) -> Unit {
  wide_context.open = true
  wide_context.x = x
  wide_context.y = y
  wide_context.link = link
  wide_context.words = c.selected_text()
}

///|
/// A right click in the page (box `page`): the words picked's menu, where words are picked and no link's opened.
fn wide_context_page(c : @ui.Ctx, page : Int) -> Unit {
  match c.right_clicked(page) {
    Some((x, y)) if wide_context.frame != c.frame_number() && c.selected_text().trim(chars=" \n\t") != "" =>
      wide_context_at(c, x, y, "")
    _ => ()
  }
}

///|
/// The menu, while open: a link's items, the words', a line between; chosen, done and gone.
fn wide_context_menu(c : @ui.Ctx) -> Unit {
  let entries : Array[@kit.Entry] = []
  if wide_context.open {
    let link = wide_context.link
    if link.has_prefix("https://") || link.has_prefix("http://") {
      entries.push(@kit.menu_item("open", label=tr("desktop.contextMenu.openLink")))
    }
    if link != "" {
      entries.push(@kit.menu_item("copy-link", label=tr("desktop.contextMenu.copyLink")))
    }
    if wide_context.words.trim(chars=" \n\t") != "" {
      if entries.length() > 0 {
        entries.push(@kit.menu_separator())
      }
      entries.push(@kit.menu_item("copy", label=tr("desktop.contextMenu.copy")))
    }
  }
  if entries.is_empty() {
    wide_context.open = false
    wide_menu(c, "context-menu", false, 0, [], {}, context_menu_w) |> ignore
    return
  }
  let at = (wide_context.x, wide_context.y, 0.0, 0.0)
  let m = wide_menu(c, "context-menu", true, 0, entries, {}, context_menu_w, offset=0.0, at~)
  if !m.open {
    wide_context.open = false
  }
  match m.chosen {
    Some("open") => {
      let href = wide_context.link
      c.after_build("context-open", fn() { @ui.open_url(href) |> ignore })
    }
    Some("copy-link") => c.copy_text(wide_context.link)
    Some("copy") => c.copy_text(wide_context.words)
    _ => ()
  }
}

///|
/// The menu's least width (the system's menus' are about as wide).
let context_menu_w : Double = 180.0
