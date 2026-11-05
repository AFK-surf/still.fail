// What a message's link and file offer, held with a finger or right clicked with a mouse (c.menu_asked, the rich
// text's held link): one menu for both, the presenters' (@sf.menu: a sheet with a finger short of Large, else a small
// panel at the pointer). A link: open it, copy it; a file: quote or download it, a picture also copied (read whole, onto the
// clipboard as a PNG).
// A choice acts at its event; an image's copy finishes when its decode is told.

///|
/// What a menu has offered, and which file was held for it.
priv struct MenuDoing {
  mut offered : String
  /// the file whose menu a finger held opened (its box's id, 0 none), and that menu (the presenters' serial)
  mut held_for : Int
  mut held_serial : Int
}

///|
let menu_doing : MenuDoing = {
  offered: "",
  held_for: 0,
  held_serial: -1,
}

///|
/// The picture whose menu was last opened ("" none).
pub fn offered_image() -> String {
  menu_doing.offered
}

///|
fn menus_reset() -> Unit {
  match copying_image.val { Some(stop) => stop(); None => () }
  copying_image.val = None
  menu_doing.offered = ""
  menu_doing.held_for = 0
  menu_doing.held_serial = -1
}

///|
/// Whether a finger held file `id` (its box's id) for its menu and that menu is up (lifted meanwhile: @sf.lift_over).
fn file_held_open(id : Int) -> Bool {
  menu_doing.held_for == id && @sf.presented_drawn_of(menu_doing.held_serial)
}

///|
/// A link in a message held or right clicked: its menu at the pointer.
fn link_held(c : @ui.Ctx, href : String) -> Unit {
  // (the press is the link's menu's, not a passage's pick)
  pk.taken_at = c.press().frame
  let (x, y, _) = c.pointer()
  // held by a finger, felt as it opens
  @sf.menu_held(c, "link") |> ignore
  @sf.link_menu(
    href,
    from=@sf.at_point(x, y),
    fn() { @ui.open_url(href) |> ignore },
    fn() { copy_menu_link(href) },
  )
}

///|
/// A link of words drawn by the window's tree held still (a finger's: felt as it opens) or right clicked, the piece of
/// line under it at `at` (in the window): its menu there, as link_held's.
fn link_held_node(href : String, at : (Double, Double, Double, Double)) -> Unit {
  if !@sf.pointer_rests() {
    @ui.haptic(LongPress)
  }
  let (x, y, w, h) = at
  @sf.link_menu(href, from=@sf.Beside::At(x, y, w, h), fn() { @ui.open_url(href) |> ignore }, fn() { copy_menu_link(href) })
}

///|
/// A file in a message (box `id`; a picture's image `src`, else "") held or right clicked: its menu there, as a
/// passage's (pick.mbt): 引用 into the chat's draft (`quote`, where it is a message's), then what else it offers
/// (`more`: 下载 and a video's 加载), then a picture's copy.
fn file_menu(
  c : @ui.Ctx,
  id : Int,
  src : String,
  quote? : (() -> Unit)? = None,
  more? : Array[@sf.MenuItem?] = [],
) -> Unit {
  match c.menu_asked(id) {
    Some((x, y)) => {
      menu_doing.offered = src
      // held with a finger: the press is the menu's (lifting it opens nothing), felt
      let held = @sf.menu_held(c, "file")
      if held {
        // (the press is the file's menu's, not a passage's pick)
        pk.taken_at = c.press().frame
      }
      let items : Array[@sf.MenuItem?] = []
      match quote {
        Some(q) => items.push(Some(@sf.menu_item_of(@sf.t("web-main.chat.quote"), q, icon="quote")))
        None => ()
      }
      items.append(more)
      if src != "" && src != "!" {
        items.push(Some(@sf.menu_item_of(@sf.t("desktop.contextMenu.copyImage"), fn() { copy_menu_image(src) }, icon="copy")))
      }
      if items.length() > 0 {
        @sf.menu(items, from=@sf.at_point(x, y))
        menu_doing.held_for = if held { id } else { 0 }
        menu_doing.held_serial = @sf.last_presented()
      }
    }
    _ => ()
  }
}

///|
/// The link copied as the menu choice is pressed, with the same notice as the old frame's.
fn copy_menu_link(href : String) -> Unit {
  let c = @ui.current()
  c.copy_text(href)
  say(c, @sf.t("common.link.copied"))
}

///|
// kept across runs: only the most recent menu copy is pending; reset stops it
let copying_image : Ref[(() -> Unit)?] = Ref(None)

///|
/// Ask for a picture at copy size at the choice's event. The watch follows that source's decode, so the host's answer
/// finishes the copy even if no frame is drawn; a later copy or a new run cancels it.
fn copy_menu_image(src : String) -> Unit {
  match copying_image.val { Some(stop) => stop(); None => () }
  copying_image.val = None
  let live = Ref(true)
  let reading = Ref(false)
  let again = Ref(false)
  let refresh : Ref[() -> Unit] = Ref(fn() {  })
  // The choice's menu may go away before the decode. This operation belongs to the copy, not to that menu's nodes.
  let owner = @signals.set_owner(None)
  let watch = @signals.watch(fn() { (refresh.val)() })
  @signals.set_owner(owner) |> ignore
  let stop = fn() {
    if live.val {
      live.val = false
      watch.stop()
      refresh.val = fn() {  }
    }
  }
  copying_image.val = Some(stop)
  refresh.val = fn() {
    if !live.val { return }
    if reading.val { again.val = true; return }
    reading.val = true
    while live.val {
      again.val = false
      match watch.read(fn() { @ui.current().image_pixels(src, image_copy_px) }) {
        @ui.PixelsRead(w, h, rgba) => {
          stop()
          copying_image.val = None
          @ui.clipboard_set_png(@pixels.png(w, h, unpremultiplied(rgba)))
        }
        @ui.PixelsFailed => { stop(); copying_image.val = None }
        @ui.PixelsComing => ()
      }
      if !again.val { break }
    }
    reading.val = false
  }
  (refresh.val)()
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
