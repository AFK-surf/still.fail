// What a message's link and file offer, held with a finger or right clicked with a mouse (c.menu_asked, the rich
// text's held link): one menu for both, the presenters' (@sf.menu: a sheet with a finger short of Large, else a small
// panel at the pointer). A link: open it, copy it; a file: quote it, a picture also copied (read whole, onto the
// clipboard as a PNG).
// What a choice does is done in the frame after it, by the list that offered it (menus_frame).

///|
/// What a menu's choice left to do: a link to open, words to copy, a picture to copy.
priv struct MenuDoing {
  /// (told: the list that offered it built again to do it)
  open : @signals.Signal[String]
  copy : @signals.Signal[String]
  image : @signals.Signal[String]
  offered : @signals.Signal[String]
  /// the file whose menu a finger held opened (its box's id, 0 none), and that menu (the presenters' serial)
  held_for : @signals.Signal[Int]
  // (plain: the next hold's number, read only as one starts)
  mut held_serial : Int
}

///|
let menu_doing : MenuDoing = {
  open: @signals.signal("", same=fn(a, b) { a == b }),
  copy: @signals.signal("", same=fn(a, b) { a == b }),
  image: @signals.signal("", same=fn(a, b) { a == b }),
  offered: @signals.signal("", same=fn(a, b) { a == b }),
  held_for: @signals.signal(0, same=fn(a, b) { a == b }),
  held_serial: -1,
}

///|
/// The picture whose menu was last opened ("" none).
pub fn offered_image() -> String {
  menu_doing.offered.get()
}

///|
fn menus_reset() -> Unit {
  menu_doing.open.set("")
  menu_doing.copy.set("")
  menu_doing.image.set("")
  menu_doing.offered.set("")
  menu_doing.held_for.set(0)
  menu_doing.held_serial = -1
}

///|
/// Whether a finger held file `id` (its box's id) for its menu and that menu is up (lifted meanwhile: @sf.lift_over).
fn file_held_open(id : Int) -> Bool {
  menu_doing.held_for.get() == id && @sf.presented_drawn_of(menu_doing.held_serial)
}

///|
/// A link in a message held or right clicked: its menu at the pointer.
fn link_held(c : @ui.Ctx, href : String) -> Unit {
  // (the press is the link's menu's, not a passage's pick)
  pk.taken_at.set(c.press().frame)
  let (x, y, _) = c.pointer()
  // held by a finger, felt as it opens
  @sf.menu_held(c, "link") |> ignore
  @sf.link_menu(
    href,
    from=@sf.at_point(x, y),
    fn() { menu_doing.open.set(href) },
    fn() { menu_doing.copy.set(href) },
  )
}

///|
/// A file in a message (box `id`; a picture's image `src`, else "") held or right clicked: its menu there, as a
/// passage's (pick.mbt): 引用 into the chat's draft (`quote`, where it is a message's), then what else it offers
/// (`more`: a video's 加载), then a picture's copy.
fn file_menu(
  c : @ui.Ctx,
  id : Int,
  src : String,
  quote? : (() -> Unit)? = None,
  more? : Array[@sf.MenuItem?] = [],
) -> Unit {
  match c.menu_asked(id) {
    Some((x, y)) => {
      menu_doing.offered.set(src)
      // held with a finger: the press is the menu's (lifting it opens nothing), felt
      let held = @sf.menu_held(c, "file")
      if held {
        // (the press is the file's menu's, not a passage's pick)
        pk.taken_at.set(c.press().frame)
      }
      let items : Array[@sf.MenuItem?] = []
      match quote {
        Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
        None => ()
      }
      items.append(more)
      if src != "" && src != "!" {
        items.push(Some(@sf.menu_item_of(@sf.t("desktop.contextMenu.copyImage"), fn() { menu_doing.image.set(src) }, icon="copy")))
      }
      if items.length() > 0 {
        @sf.menu(items, from=@sf.at_point(x, y))
        menu_doing.held_for.set(if held { id } else { 0 })
        menu_doing.held_serial = @sf.last_presented()
      }
    }
    _ => ()
  }
}

///|
/// What a menu's choice left, done: a link opened by the system once the frame is built, words copied, a picture read
/// whole and put on the clipboard (as Electron's copyImage: decoded, as PNG) once it is read.
fn menus_frame(c : @ui.Ctx) -> Unit {
  // (taken when it is opened, not while the frame is built: a frame built again lets go of what its earlier builds
  // said, Ctx::after_build)
  if menu_doing.open.get() != "" {
    let href = menu_doing.open.get()
    c.after_build("menu-open", fn() {
      menu_doing.open.set("")
      @ui.open_url(href) |> ignore
    })
  }
  if menu_doing.copy.get() != "" {
    c.copy_text(menu_doing.copy.get())
    menu_doing.copy.set("")
    say(c, @sf.t("common.link.copied"))
  }
  if menu_doing.image.get() != "" {
    match c.image_pixels(menu_doing.image.get(), image_copy_px) {
      @ui.PixelsRead(w, h, rgba) =>
        c.after_build("menu-copy-image", fn() {
          menu_doing.image.set("")
          @ui.clipboard_set_png(@pixels.png(w, h, unpremultiplied(rgba)))
        })
      @ui.PixelsFailed => menu_doing.image.set("")
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
