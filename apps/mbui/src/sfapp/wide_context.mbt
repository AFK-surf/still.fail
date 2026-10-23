// What a right click in the wide frame offers, as the desktop app's own (ember apps/desktop/src/context-menu.mts:
// Electron shows none of its own): a link's (在浏览器中打开链接 and 复制链接), an image's (复制图片), then the words: a
// field's editing (剪切, 复制, 粘贴, 全选, each as it can be done now), elsewhere the words picked (复制); a line between
// them; nothing where there is none of these (the page's ground). The app's menu (wide_menu) at the pointer.

///|
/// The menu while it is open: where (the pointer), the link right clicked ("" none), the image (its source, "" none),
/// the field (its id, 0 none), the words picked then ("" none), and the frame something in the page opened it in (the
/// page's right click under it, the same, opens nothing else). What is under way once chosen: the clipboard read for
/// 粘贴 (into that field), the image's pixels read for 复制图片.
priv struct WideContext {
  mut open : Bool
  mut x : Double
  mut y : Double
  mut link : String
  mut image : String
  mut field : Int
  mut words : String
  mut frame : Int
  mut copying : String
}

///|
let wide_context : WideContext = {
  open: false,
  x: 0.0,
  y: 0.0,
  link: "",
  image: "",
  field: 0,
  words: "",
  frame: -1,
  copying: "",
}

///|
fn wide_context_reset() -> Unit {
  wide_context.open = false
  wide_context.frame = -1
  wide_context.copying = ""
}

///|
/// A link in a message right clicked (what its words' rich text tells as held): its menu at the pointer, with what is
/// picked.
fn wide_context_link(c : @ui.Ctx, href : String) -> Unit {
  let (x, y, _) = c.pointer()
  // (in an image's link too: the image's said with it)
  let image = if wide_context.frame == c.frame_number() { wide_context.image } else { "" }
  wide_context_at(c, x, y, link=href, image~)
}

///|
/// An image in a message right clicked (box `id`, its picture from `src`): its menu at the pointer.
fn wide_context_image(c : @ui.Ctx, id : Int, src : String) -> Unit {
  match c.right_clicked(id) {
    Some((x, y)) if src != "" && src != "!" => {
      let link = if wide_context.frame == c.frame_number() { wide_context.link } else { "" }
      wide_context_at(c, x, y, link~, image=src)
    }
    _ => ()
  }
}

///|
fn wide_context_at(c : @ui.Ctx, x : Double, y : Double, link? : String = "", image? : String = "") -> Unit {
  wide_context.open = true
  wide_context.x = x
  wide_context.y = y
  wide_context.link = link
  wide_context.image = image
  wide_context.field = 0
  wide_context.words = c.selected_text()
  wide_context.frame = c.frame_number()
}

///|
/// A right click in the page (box `page`): the words picked's menu, where words are picked and nothing in the page
/// opened one.
fn wide_context_page(c : @ui.Ctx, page : Int) -> Unit {
  match c.right_clicked(page) {
    Some((x, y)) if wide_context.frame != c.frame_number() && c.selected_text().trim(chars=" \n\t") != "" =>
      wide_context_at(c, x, y)
    _ => ()
  }
}

///|
/// The menu, while open: a link's items, an image's, the words'; chosen, done (what reads first, once read) and gone.
fn wide_context_menu(c : @ui.Ctx) -> Unit {
  // a field right clicked anywhere: its editing
  match c.field_right_clicked() {
    Some((id, x, y)) => {
      wide_context.open = true
      wide_context.x = x
      wide_context.y = y
      wide_context.link = ""
      wide_context.image = ""
      wide_context.field = id
      wide_context.words = ""
      wide_context.frame = c.frame_number()
    }
    None => ()
  }
  wide_context_pending(c)
  let entries : Array[@kit.Entry] = []
  let group = fn() {
    if entries.length() > 0 {
      entries.push(@kit.menu_separator())
    }
  }
  if wide_context.open {
    let link = wide_context.link
    if link.has_prefix("https://") || link.has_prefix("http://") {
      entries.push(@kit.menu_item("open", label=tr("desktop.contextMenu.openLink")))
    }
    if link != "" {
      entries.push(@kit.menu_item("copy-link", label=tr("desktop.contextMenu.copyLink")))
    }
    if wide_context.image != "" {
      group()
      entries.push(@kit.menu_item("copy-image", label=tr("desktop.contextMenu.copyImage")))
    }
    if wide_context.field != 0 {
      let can = c.field_can(wide_context.field)
      group()
      for x in [
        ("cut", @hostapi.text_menu_cut, "desktop.contextMenu.cut"),
        ("copy-field", @hostapi.text_menu_copy, "desktop.contextMenu.copy"),
        ("paste", @hostapi.text_menu_paste, "desktop.contextMenu.paste"),
        ("select-all", @hostapi.text_menu_select_all, "desktop.contextMenu.selectAll"),
      ] {
        entries.push(@kit.menu_item(x.0, label=tr(x.2), disabled=(can & x.1) == 0))
      }
    } else if wide_context.words.trim(chars=" \n\t") != "" {
      group()
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
  let field = wide_context.field
  match m.chosen {
    Some("open") => {
      let href = wide_context.link
      c.after_build("context-open", fn() { @ui.open_url(href) |> ignore })
    }
    Some("copy-link") => c.copy_text(wide_context.link)
    Some("copy") => c.copy_text(wide_context.words)
    Some("copy-image") => wide_context.copying = wide_context.image
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
fn wide_context_pending(c : @ui.Ctx) -> Unit {
  if wide_context.copying != "" {
    match c.image_pixels(wide_context.copying, image_copy_px) {
      @ui.PixelsRead(w, h, rgba) => {
        wide_context.copying = ""
        @ui.clipboard_set_png(@pixels.png(w, h, unpremultiplied(rgba)))
      }
      @ui.PixelsFailed => wide_context.copying = ""
      @ui.PixelsComing => ()
    }
  }
}

///|
/// Pixels with their colours as they are (the host's are premultiplied by their alpha, a PNG's not).
fn unpremultiplied(rgba : FixedArray[Byte]) -> FixedArray[Byte] {
  let out = FixedArray::make(rgba.length(), b'\x00')
  let n = rgba.length() / 4
  for i in 0..<n {
    let k = i * 4
    let a = rgba[k + 3].to_int()
    for j in 0..<3 {
      let v = rgba[k + j].to_int()
      let u = if a == 0 { 0 } else { (v * 255 + a / 2) / a }
      out[k + j] = (if u > 255 { 255 } else { u }).to_byte()
    }
    out[k + 3] = rgba[k + 3]
  }
  out
}

///|
/// The picture copied at most this many pixels on its long side.
let image_copy_px : Int = 4096

///|
/// The menu's least width (the system's menus' are about as wide).
let context_menu_w : Double = 180.0
