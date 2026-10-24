// What a message's link and picture offer, held with a finger or right clicked with a mouse (c.menu_asked, the rich
// text's held link): one menu for both, the presenters' (@sf.menu: a sheet with a finger short of Large, else a small
// panel at the pointer). A link: open it, copy it; a picture: copy it (read whole, onto the clipboard as a PNG).
// What a choice does is done in the frame after it, by the list that offered it (menus_frame).

///|
/// What a menu's choice left to do: a link to open, words to copy, a picture to copy.
priv struct MenuDoing {
  mut open : String
  mut copy : String
  mut image : String
  mut offered : String
}

///|
let menu_doing : MenuDoing = { open: "", copy: "", image: "", offered: "" }

///|
/// The picture whose menu was last opened ("" none).
pub fn offered_image() -> String {
  menu_doing.offered
}

///|
fn menus_reset() -> Unit {
  menu_doing.open = ""
  menu_doing.copy = ""
  menu_doing.image = ""
  menu_doing.offered = ""
}

///|
/// A link in a message held or right clicked: its menu at the pointer.
fn link_held(c : @ui.Ctx, href : String) -> Unit {
  // (the press is the link's menu's, not a passage's pick)
  pk.taken_at = c.press().frame
  let (x, y, _) = c.pointer()
  // on a touch device the phone's words (Links.kt), on a computer the desktop's (its context menu's); held by a finger,
  // felt as it opens
  let finger = @sf.touch_system()
  @sf.menu_held(c, "link") |> ignore
  let items : Array[@sf.MenuItem?] = []
  if href.has_prefix("https://") || href.has_prefix("http://") {
    items.push(
      Some(
        @sf.menu_item_of(
          @sf.t(if finger { "common.link.open" } else { "desktop.contextMenu.openLink" }),
          fn() { menu_doing.open = href },
          icon="external",
        ),
      ),
    )
  }
  items.push(
    Some(
      @sf.menu_item_of(
        @sf.t(if finger { "common.link.copy" } else { "desktop.contextMenu.copyLink" }),
        fn() { menu_doing.copy = href },
        icon="copy",
      ),
    ),
  )
  @sf.menu(items, from=@sf.at_point(x, y))
}

///|
/// A picture in a message (box `id`, its image `src`) held or right clicked: its menu there, as a passage's (pick.mbt):
/// 引用 into the chat's draft (`quote`, where it is a message's), then copy it.
fn image_menu(c : @ui.Ctx, id : Int, src : String, quote? : (() -> Unit)? = None) -> Unit {
  match c.menu_asked(id) {
    Some((x, y)) => {
      menu_doing.offered = src
      // held with a finger: the press is the menu's (lifting it opens nothing), felt
      if @sf.menu_held(c, "image") {
        // (the press is the picture's menu's, not a passage's pick)
        pk.taken_at = c.press().frame
      }
      let items : Array[@sf.MenuItem?] = []
      match quote {
        Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
        None => ()
      }
      if src != "" && src != "!" {
        items.push(Some(@sf.menu_item_of(@sf.t("desktop.contextMenu.copyImage"), fn() { menu_doing.image = src }, icon="copy")))
      }
      if items.length() > 0 {
        @sf.menu(items, from=@sf.at_point(x, y))
      }
    }
    _ => ()
  }
}

///|
/// What a menu's choice left, done: a link opened by the system once the frame is built, words copied, a picture read
/// whole and put on the clipboard (as Electron's copyImage: decoded, as PNG) once it is read.
fn menus_frame(c : @ui.Ctx) -> Unit {
  if menu_doing.open != "" {
    let href = menu_doing.open
    menu_doing.open = ""
    c.after_build("menu-open", fn() { @ui.open_url(href) |> ignore })
  }
  if menu_doing.copy != "" {
    c.copy_text(menu_doing.copy)
    menu_doing.copy = ""
    say(c, @sf.t("common.link.copied"))
  }
  if menu_doing.image != "" {
    match c.image_pixels(menu_doing.image, image_copy_px) {
      @ui.PixelsRead(w, h, rgba) =>
        c.after_build("menu-copy-image", fn() {
          menu_doing.image = ""
          @ui.clipboard_set_png(@pixels.png(w, h, unpremultiplied(rgba)))
        })
      @ui.PixelsFailed => menu_doing.image = ""
      @ui.PixelsComing => ()
    }
  }
}

///|
/// Pixels with their colours as they are (the host's are premultiplied by their alpha, a PNG's not).
pub fn unpremultiplied(rgba : FixedArray[Byte]) -> FixedArray[Byte] {
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
pub let image_copy_px : Int = 4096
