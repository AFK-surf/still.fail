// Where the keys are: WeChat's keyboard's (微信输入法 4.0.0, its 26 keys: assets/keyboard/output/S2ChineseQwertyKeyboard
// and S9DoublePinQwertyKeyboard, measured on its screen), in its units (pixels of a keyboard 1080 wide), scaled to
// the keyboard's width. A key's cell tiles its row (a finger between two keys has the nearer one); what is drawn is
// the key inside it.

///|
/// The width WeChat's keyboard is laid out for: every place below is in these units.
pub let unit_width : Double = 1080.0

///|
/// The bar's height (what is being typed and its candidates, or the bar's own buttons).
pub let bar_h : Double = 160.0

///|
/// The keyboard's height without the system's bars at its foot: the bar and four rows of keys.
pub let board_h : Double = 788.0

///|
/// Where each row's keys begin, how high they are, and how far apart rows are.
let row_top : Double = 172.0

///|
let row_step : Double = 158.0

///|
let key_h : Double = 130.0

///|
/// A letter's key's width and the step from one to the next.
let key_w : Double = 92.0

///|
let key_step : Double = 107.0

///|
/// How a key is drawn: a letter's (light), one of the keys beside them (grey), Enter while it does the field's action
/// (green).
pub(all) enum Look {
  Light
  Grey
  Green
} derive(Eq, Show, Debug)

///|
/// One key: what it is, its words (and a small one over them: 。 over ，), how it is drawn, where it is drawn and its
/// cell, all in units.
pub struct Cap {
  key : Key
  label : String
  small : String
  look : Look
  x : Double
  y : Double
  w : Double
  h : Double
  cell_x : Double
  cell_y : Double
  cell_w : Double
  cell_h : Double
}

///|
/// What Enter says for the field's action.
fn enter_label(action : String) -> String {
  match action {
    "send" => "发送"
    "search" => "搜索"
    "go" => "前往"
    "done" => "完成"
    "next" => "下一项"
    _ => "换行"
  }
}

///|
/// The keys of `board` as it is now.
pub fn caps(board : Board) -> Array[Cap] {
  let out : Array[Cap] = []
  let zh = board.chinese
  let full = match board.composer {
    Some(c) => zh && c.scheme() == @pinyin.Full
    None => false
  }
  // (WeChat's: capitals on the keys while it types Chinese; as they go in otherwise)
  let capital = board.shift != Off || zh
  // a row's keys, each (key, words, small words, look, x, width); the first and last cells reach the keyboard's edges,
  // the others meet halfway between their keys
  fn row(r : Int, keys : Array[(Key, String, String, Look, Double, Double)]) {
    let y = row_top + r.to_double() * row_step
    let cy = y - (row_step - key_h) / 2.0
    for i, k in keys {
      let left = if i == 0 { 0.0 } else { (keys[i - 1].4 + keys[i - 1].5 + k.4) / 2.0 }
      let right = if i == keys.length() - 1 {
        unit_width
      } else {
        (k.4 + k.5 + keys[i + 1].4) / 2.0
      }
      out.push({
        key: k.0,
        label: k.1,
        small: k.2,
        look: k.3,
        x: k.4,
        y,
        w: k.5,
        h: key_h,
        cell_x: left,
        cell_y: cy,
        cell_w: right - left,
        cell_h: row_step,
      })
    }
  }
  fn letters(s : String, from : Double) -> Array[(Key, String, String, Look, Double, Double)] {
    s
    .to_array()
    .mapi(fn(i, l) {
      let words = if capital { l.to_string().to_upper() } else { l.to_string() }
      (Letter(l), words, "", Light, from + i.to_double() * key_step, key_w)
    })
  }
  fn signs(s : Array[String], from : Double) -> Array[(Key, String, String, Look, Double, Double)] {
    s.mapi(fn(i, x) { (Words(x), x, "", Light, from + i.to_double() * key_step, key_w) })
  }
  let composing = board.composing()
  let enter : (Key, String, String, Look, Double, Double) = if composing {
    (EnterKey, "确定", "", Grey, 854.0, 213.0)
  } else if board.action == "enter" {
    (EnterKey, "换行", "", Grey, 854.0, 213.0)
  } else {
    (EnterKey, enter_label(board.action), "", Green, 854.0, 213.0)
  }
  let comma = if zh { "，" } else { "," }
  let stop = if zh { "。" } else { "." }
  let foot : Array[(Key, String, String, Look, Double, Double)] = [
    (PageKey, if board.page == Letters { "123" } else if zh { "拼音" } else { "ABC" }, "", Grey, 13.0, 199.0),
    (Words(comma), comma, stop, Light, 227.0, 92.0),
    (Space, "", "", Light, 334.0, 386.0),
    (Lang, if zh { "中" } else { "英" }, if zh { "英" } else { "中" }, Light, 735.0, 104.0),
    enter,
  ]
  let back : (Key, String, String, Look, Double, Double) = (Back, "⌫", "", Grey, 937.0, 130.0)
  match board.page {
    Letters => {
      row(0, letters("qwertyuiop", 13.0))
      row(1, letters("asdfghjkl", 66.0))
      let first : (Key, String, String, Look, Double, Double) = if full && composing {
        (Break, "'词", "", Grey, 13.0, 130.0)
      } else {
        (ShiftKey, if board.shift == Locked { "⇪" } else { "⇧" }, "", Grey, 13.0, 130.0)
      }
      row(2, [first] + letters("zxcvbnm", 173.0) + [back])
    }
    Signs => {
      row(0, signs(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], 13.0))
      row(
        1,
        signs(
          if zh {
            ["-", "/", "：", "；", "（", "）", "@", "“", "”"]
          } else {
            ["-", "/", ":", ";", "(", ")", "@", "\"", "'"]
          },
          66.0,
        ),
      )
      let mid = if zh {
        ["…", "～", "、", "？", "！", "《", "》"]
      } else {
        ["?", "!", "*", "#", "+", "=", "&"]
      }
      row(2, [(Words("%"), "%", "", Grey, 13.0, 130.0)] + signs(mid, 173.0) + [back])
    }
  }
  row(3, foot)
  out
}

///|
/// The key whose cell holds (x, y) in units, or -1 (over the bar, or past the rows).
pub fn cap_at(caps : Array[Cap], x : Double, y : Double) -> Int {
  for i, c in caps {
    if x >= c.cell_x && x < c.cell_x + c.cell_w && y >= c.cell_y && y < c.cell_y + c.cell_h {
      return i
    }
  }
  -1
}
