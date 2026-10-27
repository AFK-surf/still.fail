// A Slack app's icon, as still.fail draws it (the web's pages/SlackApp.tsx MAKERS, useBuddies, renderAvatar, toIcon,
// edgeColour; the Android app's SlackApp.kt): a picture to start from, still.fail's buddies (the core's `buddies`, their
// pictures the cloud's /avatars) or a model maker's mark, each on a colour of its own, drawn on its colour as the app's
// icon: 1024 pixels, a buddy as large as fits (92%), a maker's mark 560 across (white where it is drawn in one
// colour), a picture of the person's own its middle square; a JPEG as a data URL, what Slack takes (mbui/pixels makes
// it, the same bytes on every host). The phone's look (sfapp/settings app_look.mbt) and the desktop's (sfdesk
// slack_app.mbt) both draw from these.

///|
/// A picture to start from: a buddy (`mark` empty) or a model maker's mark (its drawable), on a colour of its own.
pub(all) struct AppAvatar {
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
pub let app_makers : Array[AppAvatar] = [
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
let buddy_list : @signals.Signal[Array[AppAvatar]?] = @signals.signal(None)

///|
let buddies_asked : Ref[Bool] = Ref(false)

///|
/// The cloud's address (the app's MBUI_CLOUD, else still.fail's own): where the buddies' pictures are.
pub fn avatars_base() -> String {
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
/// The buddies, asked of the core once (`ask`: its `buddies` call, answering id, label, bg each) once the frame is
/// built; none where it has none, or until it has answered.
pub fn app_buddies(c : @ui.Ctx, ask : ((Result[Json, Json]) -> Unit) -> Unit) -> Array[AppAvatar] {
  // (said by each build until it is asked: a build let go of asks nothing)
  if !buddies_asked.val {
    c.after_build("app-icon/buddies", fn() {
      if !buddies_asked.val {
        buddies_asked.val = true
        ask(fn(r) {
          buddy_list.set(Some(
            match r {
              Ok(Array(a)) =>
                a.map(fn(b) {
                  let word = fn(k : String) {
                    match b {
                      Object(m) =>
                        match m.get(k) {
                          Some(String(v)) => v
                          _ => ""
                        }
                      _ => ""
                    }
                  }
                  { id: word("id"), label: word("label"), bg: word("bg"), mark: "", mono: false }
                })
              _ => []
            },
          ))
        })
      }
    })
  }
  buddy_list.get().unwrap_or([])
}

///|
/// The buddies forgotten, as the app begins anew.
pub fn app_icons_reset() -> Unit {
  buddy_list.set(None)
  buddies_asked.val = false
}

///|
/// A colour as #RRGGBB says it (an app's background), None where it is not one.
pub fn hex_color(s : String) -> Int64? {
  if s.length() != 7 || !s.has_prefix("#") {
    return None
  }
  let mut v = 0L
  for i in 1..<7 {
    let ch = s.unsafe_get(i).to_int()
    let d = if ch >= 48 && ch <= 57 {
      ch - 48
    } else if ch >= 65 && ch <= 70 {
      ch - 55
    } else if ch >= 97 && ch <= 102 {
      ch - 87
    } else {
      return None
    }
    v = v * 16L + d.to_int64()
  }
  Some((v << 8) | 0xFFL)
}

///|
/// An icon as Slack takes it: a JPEG (90), and its data URL.
pub fn app_icon_jpeg(icon : @pixels.Canvas) -> (Bytes, String) {
  let jpeg = @pixels.jpeg(app_icon_px, app_icon_px, icon.pixels(), quality=90)
  (jpeg, "data:image/jpeg;base64," + @codec.base64(jpeg))
}

///|
/// The icon of `a` on `bg` (#RRGGBB; else its own colour) drawn from its picture's pixels (a buddy's: `w` × `h` of
/// `px`, premultiplied): None where a maker's mark is not known here.
pub fn app_avatar_icon(a : AppAvatar, bg : String, w : Int, h : Int, px : FixedArray[Byte]) -> @pixels.Canvas? {
  let icon = @pixels.Canvas::new(app_icon_px, app_icon_px)
  icon.fill(
    match hex_color(bg) {
      Some(v) => v
      None => hex_color(a.bg).unwrap_or(icon_fallback)
    },
  )
  let side = app_icon_px.to_double()
  if a.mark != "" {
    let white = 0xFFFFFFFFL
    match drawable_pixels(a.mark, mark_px, tint?=if a.mono { Some(white) } else { None }) {
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
pub fn app_own_icon(w : Int, h : Int, px : FixedArray[Byte]) -> @pixels.Canvas {
  let icon = @pixels.Canvas::new(app_icon_px, app_icon_px)
  icon.fill(0xFFFFFFFFL)
  let s = if w < h { w } else { h }
  let x = (w - s) / 2
  let y = (h - s) / 2
  icon.draw(w, h, px, (x, y, x + s, y + s), (0.0, 0.0, app_icon_px.to_double(), app_icon_px.to_double()))
  icon
}

///|
/// The ground where neither colour is one (SlackApp.kt parseColor's fallback).
pub let icon_fallback : Int64 = 0x7A2E0EFFL

///|
/// How large an icon is made (Slack wants 512 to 2000), a maker's mark in it, and how much of it a buddy takes.
pub let app_icon_px : Int = 1024

///|
let mark_px : Int = 560

///|
let buddy_share : Double = 0.92

///|
/// How large a picture of the person's own is read, before its middle is made the icon (Android reads it at least
/// 1024 on its shorter side).
pub let app_own_px : Int = 2048

