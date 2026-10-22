// A Slack app's look (still.fail's Android app, SlackApp.kt AppLook, AvatarGrid; the web's AppLook / AppFields): a
// picture picked from still.fail's buddies (the core's `buddies`, their pictures the cloud's /avatars, as the web has
// them) or the model makers' marks, or one of the person's own, drawn on its colour as the app's icon: 1024 pixels, a
// buddy as large as fits (92%), a maker's mark 560 across (white where it is drawn in one colour), a picture of their
// own its middle square; a JPEG as a data URL, what Slack takes (mbui/pixels makes it, the same bytes on every host).
// The colour follows what is picked until it is set by hand (and can go back to it).

///|
/// A picture to start from: a buddy (`mark` empty) or a model maker's mark (its drawable), on a colour of its own.
priv struct Avatar {
  id : String
  /// what it is called (a screen reader's), a catalog's key where it is said in words of the app's
  label : String
  bg : String
  mark : String
  mono : Bool
}

///|
/// The model makers' marks, each on its own colour (SlackApp.kt MAKER_AVATARS).
// kept across runs: a table of constants, never written
let maker_avatars : Array[Avatar] = [
  { id: "anthropic", label: "Anthropic", bg: "#D97757", mark: "maker_anthropic", mono: true },
  { id: "openai", label: "OpenAI", bg: "#0D0D0D", mark: "maker_openai", mono: true },
  { id: "gemini", label: "Gemini", bg: "#FFFFFF", mark: "maker_gemini", mono: false },
  { id: "deepseek", label: "DeepSeek", bg: "#FFFFFF", mark: "maker_deepseek", mono: false },
  { id: "qwen", label: "Qwen", bg: "#FFFFFF", mark: "maker_qwen", mono: false },
  { id: "zhipu", label: "android-settings.slack.zhipu", bg: "#FFFFFF", mark: "maker_zhipu", mono: false },
  { id: "kimi", label: "Kimi", bg: "#0D0D0D", mark: "maker_kimi", mono: true },
  { id: "minimax", label: "MiniMax", bg: "#FFFFFF", mark: "maker_minimax", mono: false },
  { id: "xai", label: "xAI", bg: "#0D0D0D", mark: "maker_xai", mono: true },
]

///|
/// The buddies as the core lists them (asked once), None until it has answered.
let buddy_list : Ref[Array[Avatar]?] = Ref(None)

///|
let buddies_asked : Ref[Bool] = Ref(false)

///|
/// A look being picked, by its form.
priv struct AppLook {
  /// what was picked: an avatar's id, or a picture of the person's own (its key, mem:…), "" neither
  mut picked : String
  mut upload : String
  /// the colour a picture of their own sits on best (its edge's)
  mut upload_bg : String
  /// the colour set by hand (the field typed in), not by what was picked
  mut colour_set : Bool
  /// the colour as last set here: the field's words other than it are typed
  mut color : String
  /// the picture being read to draw from: its source and how large it is read, "" none
  mut reading : String
  mut reading_px : Int
  mut reading_bg : String
  /// the icon made, as shown (its picture's key), "" none
  mut shown : String
  mut error : String
  /// the system's picker asked, not answered yet
  mut asking : Bool
  /// a new app's first avatar picked
  mut started : Bool
}

///|
let app_looks : Map[String, AppLook] = {}

///|
/// Icons made, to give each its own picture's key.
let icons_made : Ref[Int] = Ref(0)

///|
fn app_looks_reset() -> Unit {
  app_looks.clear()
  buddy_list.val = None
  buddies_asked.val = false
  icons_made.val = 0
}

///|
/// The cloud's address (the app's MBUI_CLOUD, else still.fail's own): where the buddies' pictures are.
fn cloud_base() -> String {
  match @ui.env("MBUI_CLOUD") {
    "" => "https://app.still.fail"
    o =>
      if o.has_suffix("/") {
        o.unsafe_substring(start=0, end=o.length() - 1)
      } else {
        o
      }
  }
}

///|
/// The buddies, asked of the core once (`buddies`: id, label, bg each) once the frame is built; none where it has
/// none.
fn buddies(c : @ui.Ctx, core : Core) -> Array[Avatar] {
  // (said by each build until it is asked: a build let go of asks nothing)
  if !buddies_asked.val {
    c.after_build("settings/buddies", fn() {
      if !buddies_asked.val {
        buddies_asked.val = true
        ask_buddies(core)
      }
    })
  }
  buddy_list.val.unwrap_or([])
}

///|
fn ask_buddies(core : Core) -> Unit {
  (core.call)("buddies", obj([]), fn(r) {
      buddy_list.val = Some(
        match r {
          Ok(Array(a)) =>
            a.map(fn(b) {
              { id: text(Some(b), "id"), label: text(Some(b), "label"), bg: text(Some(b), "bg"), mark: "", mono: false }
            })
          _ => []
        },
      )
  })
}

///|
/// The icon of `a` on `bg` (#RRGGBB; else its own colour) drawn from its picture's pixels (a buddy's: `w` × `h` of
/// `px`, premultiplied): None where a maker's mark is not known here.
fn avatar_icon(a : Avatar, bg : String, w : Int, h : Int, px : FixedArray[Byte]) -> @pixels.Canvas? {
  let icon = @pixels.Canvas::new(icon_px, icon_px)
  icon.fill(
    match hex_color(bg) {
      Some(v) => v
      None => hex_color(a.bg).unwrap_or(icon_fallback)
    },
  )
  let side = icon_px.to_double()
  if a.mark != "" {
    let white = 0xFFFFFFFFL
    match @sf.drawable_pixels(a.mark, mark_px, tint?=if a.mono { Some(white) } else { None }) {
      Some((mw, mh, mp)) => {
        let x = (side - mw.to_double()) / 2.0
        let y = (side - mh.to_double()) / 2.0
        icon.draw(mw, mh, mp, (0, 0, mw, mh), (x, y, x + mw.to_double(), y + mh.to_double()), premultiplied=false)
      }
      None => return None
    }
  } else {
    // as large as fits, what of it is drawn
    let (x0, y0, x1, y1) = @pixels.drawn_box(w, h, px)
    let bw = (x1 - x0).to_double()
    let bh = (y1 - y0).to_double()
    let k = side * buddy_share / (if bw > bh { bw } else { bh })
    let (dw, dh) = (bw * k, bh * k)
    icon.draw(w, h, px, (x0, y0, x1, y1), ((side - dw) / 2.0, (side - dh) / 2.0, (side + dw) / 2.0, (side + dh) / 2.0))
  }
  Some(icon)
}

///|
/// A picture of the person's own as an icon: its middle square, on white where it is clear.
fn own_icon(w : Int, h : Int, px : FixedArray[Byte]) -> @pixels.Canvas {
  let icon = @pixels.Canvas::new(icon_px, icon_px)
  icon.fill(0xFFFFFFFFL)
  let s = if w < h { w } else { h }
  let x = (w - s) / 2
  let y = (h - s) / 2
  icon.draw(w, h, px, (x, y, x + s, y + s), (0.0, 0.0, icon_px.to_double(), icon_px.to_double()))
  icon
}

///|
/// The ground where neither colour is one (SlackApp.kt parseColor's fallback).
let icon_fallback : Int64 = 0x7A2E0EFFL

///|
/// How large an icon is made (Slack wants 512 to 2000), a maker's mark in it, and how much of it a buddy takes.
let icon_px : Int = 1024

///|
let mark_px : Int = 560

///|
let buddy_share : Double = 0.92

///|
/// An icon made: its picture shown in the look, and as it goes to Slack (`on_icon`).
fn icon_made(l : AppLook, icon : @pixels.Canvas, on_icon : (String?, String) -> Unit) -> Unit {
  let jpeg = @pixels.jpeg(icon_px, icon_px, icon.pixels(), quality=90)
  icons_made.val += 1
  l.shown = "mem:slack-icon/\{icons_made.val}"
  @ui.add_image(l.shown, jpeg)
  l.error = ""
  on_icon(Some("data:image/jpeg;base64," + @codec.base64(jpeg)), "")
}

///|
/// A look's icon could not be made: what it says.
fn icon_failed(l : AppLook, words : String, on_icon : (String?, String) -> Unit) -> Unit {
  l.reading = ""
  l.error = words
  on_icon(None, words)
}

///|
/// The look of the app being made or changed (`key` its form's): its icon, its colour `color` (#RRGGBB), `set_color`
/// told each change, `on_icon` the icon made (a data URL, or None and why not). `fresh`: a new app, which starts as
/// the general helper.
fn app_look(
  c : @ui.Ctx,
  core : Core,
  key : String,
  color : String,
  set_color : (String) -> Unit,
  on_icon : (String?, String) -> Unit,
  fresh : Bool,
) -> Unit {
  let t = @sf.theme()
  let l = match app_looks.get(key) {
    Some(l) => l
    None => {
      let l = {
        picked: "",
        upload: "",
        upload_bg: "",
        colour_set: false,
        color,
        reading: "",
        reading_px: 0,
        reading_bg: "",
        shown: "",
        error: "",
        asking: false,
        started: false,
      }
      field_of(key + "/color").set(color)
      app_looks[key] = l
      l
    }
  }
  let all = buddies(c, core) + maker_avatars
  let colour = fn(bg : String) {
    l.color = bg
    field_of(key + "/color").set(bg)
    set_color(bg)
  }
  // an avatar drawn on `bg`: a mark at once, a buddy once its picture is read
  let draw = fn(a : Avatar, bg : String) {
    if a.mark != "" {
      l.reading = ""
      match avatar_icon(a, bg, 0, 0, FixedArray::make(0, b'\x00')) {
        Some(icon) => icon_made(l, icon, on_icon)
        None => icon_failed(l, tr("android-settings.slack.drawFailed"), on_icon)
      }
    } else {
      l.reading = cloud_base() + "/avatars/" + a.id + ".webp"
      l.reading_px = icon_px
      l.reading_bg = bg
    }
  }
  let pick = fn(a : Avatar) {
    l.picked = a.id
    l.upload = ""
    let bg = if l.colour_set { l.color } else { a.bg }
    colour(bg)
    draw(a, bg)
  }
  // a new app starts as the general helper, else the first, on its colour
  if fresh && !l.started && all.length() > maker_avatars.length() {
    l.started = true
    pick(all.iter().find_first(fn(a) { a.id == "general-helper" }).unwrap_or(all[0]))
  }
  // what is being read, read: drawn
  if l.reading != "" {
    match c.image_pixels(l.reading, l.reading_px) {
      PixelsComing => ()
      PixelsFailed =>
        icon_failed(
          l,
          tr(if l.upload != "" { "android-settings.slack.imageFailed" } else { "android-settings.slack.drawFailed" }),
          on_icon,
        )
      PixelsRead(w, h, px) => {
        l.reading = ""
        if l.upload != "" {
          let icon = own_icon(w, h, px)
          l.upload_bg = @pixels.edge_colour(icon_px, icon_px, icon.pixels())
          icon_made(l, icon, on_icon)
          if !l.colour_set {
            colour(l.upload_bg)
          }
        } else {
          match all.iter().find_first(fn(a) { a.id == l.picked }) {
            Some(a) =>
              match avatar_icon(a, l.reading_bg, w, h, px) {
                Some(icon) => icon_made(l, icon, on_icon)
                None => icon_failed(l, tr("android-settings.slack.drawFailed"), on_icon)
              }
            None => ()
          }
        }
      }
    }
  }
  // a picture of their own, from the system's picker
  let open_picker = fn() {
    if l.asking {
      return
    }
    let asked = (core.pick_picture)(fn(bytes) {
      l.asking = false
      match bytes {
        Some(b) => {
          icons_made.val += 1
          l.upload = "mem:slack-icon/own/\{icons_made.val}"
          @ui.add_image(l.upload, b)
          l.picked = ""
          l.reading = l.upload
          l.reading_px = own_px
        }
        None => ()
      }
    })
    l.asking = asked
    if !asked {
      icon_failed(l, tr("android-settings.slack.imageFailed"), on_icon)
    }
  }
  // typed in its field: set by hand
  let typed = field_of(key + "/color").text().trim(chars=" ").to_owned().to_upper()
  if typed != l.color {
    l.color = typed
    l.colour_set = true
    set_color(typed)
    if hex_color(typed) is Some(_) {
      match all.iter().find_first(fn(a) { a.id == l.picked }) {
        Some(a) => draw(a, typed)
        None => ()
      }
    }
  }
  c.box(style=look_column, fn() {
    c.text(tr("android-settings.slack.icon"), style=look_label) |> ignore
    c.box(style=look_row, fn() {
      let preview = c.id(key + "/preview")
      let ground = look_preview.then(@ui.style(bg=Data(hex_color(l.color).unwrap_or(t.p.chip))))
      let shown = c.box(style=ground, id=preview, fn() {
        if l.shown != "" {
          c.image(l.shown, w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L, fade=false) |> ignore
        } else {
          @sf.icon(c, "image-upload", size=20.0, color=t.p.muted) |> ignore
          c.text(tr(if fresh { "android-settings.slack.upload" } else { "android-settings.slack.keep" }), style=look_small)
          |> ignore
        }
      })
      c.semantics(shown, Button, id=preview, label=tr("android-settings.slack.icon"))
      if hit(c, preview) {
        open_picker()
      }
      c.box(style=look_notes, fn() {
        c.text(tr("android-settings.slack.iconNote"), style=look_note) |> ignore
        if tap_text(c, key + "/upload", tr("android-settings.slack.uploadImage"), size=14.0) {
          open_picker()
        }
      })
      |> ignore
    })
    |> ignore
    avatar_grid(c, key, all, l.picked, pick)
    c.text(tr("android-settings.slack.background"), style=look_label) |> ignore
    c.box(style=look_colour_row, fn() {
      c.box(style=look_swatch.then(@ui.style(bg=Data(hex_color(l.color).unwrap_or(t.p.chip)))), fn() {  }) |> ignore
      c.box(style=look_colour_field, fn() { field_box(c, key + "/color", "#RRGGBB", mono=true) |> ignore }) |> ignore
      // what was picked's own colour, after one set by hand
      let recommended = if l.picked != "" {
        all.iter().find_first(fn(a) { a.id == l.picked }).map(fn(a) { a.bg })
      } else if l.upload != "" && l.upload_bg != "" {
        Some(l.upload_bg)
      } else {
        None
      }
      match recommended {
        Some(r) if l.colour_set && r.to_upper() != l.color.to_upper() =>
          if tap_text(c, key + "/recommended", tr("android-settings.slack.recommended"), size=14.0) {
            l.colour_set = false
            colour(r)
            match all.iter().find_first(fn(a) { a.id == l.picked }) {
              Some(a) => draw(a, r)
              None => ()
            }
          }
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// How large a picture of the person's own is read, before its middle is made the icon (Android reads it at least
/// 1024 on its shorter side).
let own_px : Int = 2048

///|
/// The avatars in a full grid, tiles at least 48 across, 10 apart; the picked one ringed in the accent
/// (SlackApp.kt AvatarGrid).
fn avatar_grid(c : @ui.Ctx, key : String, all : Array[Avatar], picked : String, pick : (Avatar) -> Unit) -> Unit {
  let gid = c.id(key + "/grid")
  // (as wide as it was laid out last; the window before it has been)
  let width = match c.rect_of(gid) {
    Some((_, _, w, _)) if w > 0.0 => w
    _ => c.width
  }
  let gap = 10.0
  let fit = ((width + gap) / (48.0 + gap)).floor().to_int()
  let columns = if fit < 1 { 1 } else { fit }
  let room = (width - gap * (columns - 1).to_double()) / columns.to_double()
  let side = if room > 0.0 { room } else { 0.0 }
  c.box(style=grid_column, id=gid, fn() {
    let mut i = 0
    while i < all.length() {
      let row = all[i:if i + columns < all.length() { i + columns } else { all.length() }].to_array()
      c.box(style=grid_row, fn() {
        for a in row {
          let on = a.id == picked
          let tile = c.id(key + "/avatar/" + a.id)
          let ground = @ui.style(bg=Data(hex_color(a.bg).unwrap_or(icon_fallback)), w=Fixed(side), h=Fixed(side))
          let face = fn() {
            if a.mark != "" {
              @sf.drawable(c, a.mark, side * mark_share, tint?=if a.mono { Some(0xFFFFFFFFL) } else { None }) |> ignore
            } else {
              let thumb = c.image(cloud_base() + "/avatars/" + a.id + ".thumb.webp", w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L)
              c.look(thumb, @ui.look(scale=thumb_scale))
            }
          }
          let node = if on {
            c.box(style=avatar_ring.then(@ui.style(w=Fixed(side), h=Fixed(side))), id=tile, fn() {
              c.box(style=avatar_in_ring.then(@ui.style(bg=Data(hex_color(a.bg).unwrap_or(icon_fallback)))), face) |> ignore
            })
          } else {
            c.box(style=avatar_tile.then(ground), id=tile, face)
          }
          c.semantics(
            node,
            Button,
            id=tile,
            label=if a.label.has_prefix("android-") { tr(a.label) } else { a.label },
            selected=on,
          )
          if hit(c, tile) {
            pick(a)
          }
        }
      })
      |> ignore
      i = i + columns
    }
  })
  |> ignore
}

///|
/// A mark 55% across its tile, a buddy's picture drawn 1.18 times its tile (SlackApp.kt AvatarGrid).
let mark_share : Double = 0.55

///|
let thumb_scale : Double = 1.18

///|
/// The look, its parts 10 apart (SlackApp.kt AppLook).
// kept across runs: a value (no field of it changes)
let look_column : @ui.Style = @ui.style(w=Full, gap=S2_5)

///|
/// A label over a part (FormLabel: 13, semibold, ink).
// kept across runs: a value (no field of it changes)
let look_label : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, w=Full)

///|
/// The icon and what to do with it, 14 apart.
// kept across runs: a value (no field of it changes)
let look_row : @ui.Style = @ui.style(row=true, w=Full, gap=S3_5, align=ACenter)

///|
/// The icon as it is: 72 square, rounded 18, on its colour (a tap: a picture of their own).
// kept across runs: a value (no field of it changes)
let look_preview : @ui.Style = @ui.style(
  w=@sf.app_icon_side,
  h=@sf.app_icon_side,
  radius=Xl2,
  clip=true,
  align=ACenter,
  justify=JCenter,
)

///|
/// 上传 / 保持当前 under the upload mark (11, muted).
// kept across runs: a value (no field of it changes)
let look_small : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false)

///|
/// What to do, 4 apart, the rest of the row.
// kept across runs: a value (no field of it changes)
let look_notes : @ui.Style = @ui.style(w=@sf.grow, gap=S1)

///|
// kept across runs: a value (no field of it changes)
let look_note : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
/// Why its icon was not made or not taken (13, red), under the look.
// kept across runs: a value (no field of it changes)
let look_error : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, w=Full)

///|
/// The colour: its swatch (44, rounded 12), its field, back to what was picked's own, 10 apart.
// kept across runs: a value (no field of it changes)
let look_colour_row : @ui.Style = @ui.style(row=true, w=Full, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let look_swatch : @ui.Style = @ui.style(w=S11, h=S11, radius=Xl)

///|
// kept across runs: a value (no field of it changes)
let look_colour_field : @ui.Style = @ui.style(w=@sf.grow)

///|
/// The grid's rows and tiles, 10 apart.
// kept across runs: a value (no field of it changes)
let grid_column : @ui.Style = @ui.style(w=Full, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let grid_row : @ui.Style = @ui.style(row=true, gap=S2_5)

///|
/// A tile, rounded 12, what is on it in its middle.
// kept across runs: a value (no field of it changes)
let avatar_tile : @ui.Style = @ui.style(radius=Xl, clip=true, align=ACenter, justify=JCenter)

///|
/// The picked one: a ring 2 wide in the accent, the tile 4 in, the two concentric (Android's 14 and 9 are off this
/// scale: 8 inside, the ring round it).
// kept across runs: a value (no field of it changes)
let avatar_ring : @ui.Style = @ui.style(p=S1, border=B2, border_color=Accent, radius=Around)

///|
// kept across runs: a value (no field of it changes)
let avatar_in_ring : @ui.Style = @ui.style(w=Full, h=Full, radius=Lg, clip=true, align=ACenter, justify=JCenter)
