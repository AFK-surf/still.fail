// A made-up library for trying the shelf and the reader without a station:
// books shaped as the media service sends them (chapters of blocks), with
// text generated here.

///|
struct Book {
  id : String
  title : String
  author : String
  chapters : Array[String]
}

///|
let library : Array[Book] = [
  { id: "b1", title: "灯塔看守人", author: "林舟", chapters: titles(24) },
  { id: "b2", title: "北方的雨季", author: "苏禾", chapters: titles(18) },
  { id: "b3", title: "The Clockmaker's Garden", author: "E. Hart", chapters: titles(
      12,
    ) },
  { id: "b4", title: "城南旧货铺", author: "陈默", chapters: titles(30) },
  { id: "b5", title: "星图与盐", author: "王珂", chapters: titles(9) },
  { id: "b6", title: "Notes on Small Boats", author: "M. Reyes", chapters: titles(
      15,
    ) },
  { id: "b7", title: "夏日的终点站", author: "林小雨", chapters: titles(21) },
]

///|
fn titles(n : Int) -> Array[String] {
  Array::makei(n, fn(i) { "第\{i + 1}章" })
}

///|
let zh_words : Array[String] = [
  "清晨", "海风", "灯塔", "旧码头", "她", "他们", "慢慢地", "推开", "窗户", "远处",
  "一盏灯", "亮了起来", "雨", "停了", "街角", "那家店", "还开着", "信", "没有寄出",
  "钟声", "从山那边", "传来", "影子", "很长", "路", "继续", "向北", "记得",
  "那一年", "冬天", "安静", "船", "靠岸", "等待", "答案", "地图", "折痕", "风",
]

///|
let en_words : Array[String] = [
  "the", "garden", "clock", "quietly", "turned", "morning", "light", "across",
  "an", "old", "bench", "she", "remembered", "letters", "never", "sent", "rain",
  "small", "boats", "harbor", "waited", "for", "evening", "and", "maps", "of",
  "forgotten", "streets", "slowly", "he", "kept", "counting", "bells",
]

///|
fn lcg(seed : Int) -> Int {
  (seed * 1103515245 + 12345) & 0x7FFFFFFF
}

///|
/// Chapter `index` of `book`, as the media service would send it.
fn chapter_blocks(book : Book, index : Int) -> Array[@ui.Block] {
  let english = book.id == "b3" || book.id == "b6"
  let mut seed = (@ui.stable_hash(book.id).to_int() & 0xFFFF) * 131 + index * 7919 + 1
  let out : Array[@ui.Block] = [Heading(book.chapters[index])]
  let paras = 14 + index % 9
  for p in 0..<paras {
    seed = lcg(seed)
    let sentences = 2 + seed % 4
    let sb = StringBuilder()
    for _ in 0..<sentences {
      seed = lcg(seed)
      let words = 6 + seed % 10
      for w in 0..<words {
        seed = lcg(seed)
        if english {
          let word = en_words[seed % en_words.length()]
          if w == 0 {
            sb.write_string(word.substring(start=0, end=1).to_upper())
            sb.write_string(word.substring(start=1))
          } else {
            sb.write_char(' ')
            sb.write_string(word)
          }
        } else {
          sb.write_string(zh_words[seed % zh_words.length()])
          if w == words / 2 {
            sb.write_string("，")
          }
        }
      }
      sb.write_string(if english { ". " } else { "。" })
    }
    out.push(Para(sb.to_string().trim_end(chars=" ").to_string()))
    if p == 6 && index % 4 == 1 {
      out.push(Rule)
    }
  }
  out
}
