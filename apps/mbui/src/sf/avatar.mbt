// A person's round picture (Android's ui/Parts.kt Avatar, avatarColor, initial), wherever one is shown: the chat's
// bar and messages, the list's rows, the settings' people.

///|
/// The people's colours (Parts.kt AVATAR).
// kept across runs: a table, never written
let avatar_colors : Array[Int64] = [
  0x5877AEFFL, 0x248753FFL, 0xB9471FFFL, 0x8768ADFFL, 0x32818DFFL, 0x9A6F11FFL,
]

///|
/// A person's colour, by their id lowered (Parts.kt avatarColor: Java's hashCode, floorMod).
pub fn avatar_color(id : String) -> Int64 {
  let n = avatar_colors.length()
  let mut h = 0
  for i in 0..<id.length() {
    let k = id.at(i).to_int()
    h = h * 31 + (if k >= 65 && k <= 90 { k + 32 } else { k })
  }
  let m = h % n
  avatar_colors[if m < 0 { m + n } else { m }]
}

///|
/// The first letter of a name, upper case (Parts.kt initial); "?" for none.
pub fn initial(name : String) -> String {
  for ch in name {
    let k = ch.to_int()
    if k == 32 || k == 9 || k == 10 {
      continue
    }
    return if k >= 97 && k <= 122 {
      (k - 32).unsafe_to_char().to_string()
    } else {
      ch.to_string()
    }
  }
  "?"
}

///|
/// A face's disc: round, what it holds in its middle (its side and colour said where it is drawn).
// kept across runs: a value (no field of it changes)
let avatar_disc : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter")

///|
/// A face's initial: semibold, white on every theme (Parts.kt: Color.White), on one line (its size, half the face's,
/// said where it is drawn).
// kept across runs: a value (no field of it changes)
let avatar_letter : @ui.TextStyle = @ui.text_style(weight=Semibold, color=Data(face_ink), wrap=false)

///|
/// A person, round (Parts.kt Avatar): `picture` (an image's key, "" while it comes or without one) once it is decoded
/// at the size it is shown, at once, as Compose draws the bitmap it was handed; their initial on their colour until
/// then, and for good when it cannot be decoded (rememberPicture: null).
pub fn avatar(c : @ui.Ctx, id : String, name : String, picture : String, size : Double) -> Unit {
  // (its decode started here the first frame it is asked for)
  let decoded = picture != "" && c.image_ready(picture, size * c.scale)
  let half = size / 2.0
  let disc = avatar_disc.then(@ui.style(w=Fixed(size), h=Fixed(size), bg=Data(avatar_color(id))))
  // (in a page's bones, one disc: its colour and its letter someone's)
  let b = c.box(style=disc, fn() {
    if decoded {
      c.image(picture, w=Px(size), h=Px(size), radius=half, bg=0L, fade=false) |> ignore
    } else {
      // its initial half the face's size, as the side its caller asks (18 by a message, 46 on the settings' card)
      avatar_initial(c, name, half)
    }
  })
  c.bone_whole(b)
}

///|
/// A thing's mark (a repository, a project), a rounded square as an agent's tile is (agent_mark_corner): `picture` (a
/// data URL of its own, its favicon or touch icon) once decoded at the size it is shown; else its initial on a colour
/// of its own, by `id` (its repository's address), as a face's is.
pub fn tile_avatar(c : @ui.Ctx, id : String, name : String, picture : String, size : Double) -> Unit {
  let key = data_image(picture)
  let decoded = key != "" && c.image_ready(key, size * c.scale)
  let half = size / 2.0
  let corner = size * 0.3
  let ground = if decoded { transparent_ground } else { avatar_color(id) }
  let round = agent_mark_corner(size)
  let tile = avatar_disc.then(@ui.style(w=Fixed(size), h=Fixed(size), radius=round, bg=Data(ground)))
  let b = c.box(style=tile, fn() {
    if decoded {
      c.image(key, w=Px(size), h=Px(size), radius=corner, bg=0L, fade=false) |> ignore
    } else {
      avatar_initial(c, name, half)
    }
  })
  c.bone_whole(b)
}

///|
/// A face's or a tile's initial, `half` its side.
fn avatar_initial(c : @ui.Ctx, name : String, half : Double) -> Unit {
  c.text(initial(name), style=avatar_letter, size=half, line=half) |> ignore
}

///|
/// Under a picture that fills its tile: nothing.
let transparent_ground : Int64 = 0L
