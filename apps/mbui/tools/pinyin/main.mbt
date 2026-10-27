// The keyboard's words (src/pinyin/words.txt), for the pinyin engine (src/pinyin): which words there are, how each is
// read (its syllables, without tones) and how often it is written (a cost: ten times the natural log of how much rarer
// than every word together it is, so a sentence's cost is its words' costs added). Made from three open sets, each
// under the MIT licence (scripts/pinyin-words fetches them at the commits it names):
//
//   jieba's dict.txt                    the words and how often each is written (fxsjy/jieba)
//   pinyin-data's pinyin.txt            every reading of each character (mozillazg/pinyin-data, from Unihan)
//   pinyin-data's kMandarin_8105.txt    the usual reading of each of the 8105 characters in common use
//   phrase-pinyin-data's pinyin.txt     how words are read where a character reads otherwise in them
//                                       (mozillazg/phrase-pinyin-data: 银行 yín háng)
//
// Only words of the 8105 characters in common use (通用规范汉字表) are kept: jieba also has traditional characters'
// and rare ones' words, which a simplified keyboard's person seldom means and which made the words three times as many.
//
// A word phrase-pinyin-data does not read is read character by character: by each one's usual reading, and also by
// its other readings at a cost (a character read otherwise in a word phrase-pinyin-data lacks), at most four ways.
// A character alone is every one of its readings, its usual one as often as jieba says and the others rarer.
//
//   pinyin <jieba dict.txt> <pinyin.txt> <kMandarin_8105.txt> <phrase pinyin.txt> <out words.txt>

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("pinyin: " + why)
  @sys.exit(1)
}

///|
/// A reading with its tone marks taken off and ü as v (lǜ → lv), or "" when it is none of Mandarin's syllables
/// written with letters (ḿ, ń, ê̄: an interjection's).
fn toneless(s : String) -> String {
  let b = StringBuilder::new()
  for c in s {
    let o : Char = match c {
      'ā' | 'á' | 'ǎ' | 'à' => 'a'
      'ē' | 'é' | 'ě' | 'è' => 'e'
      'ī' | 'í' | 'ǐ' | 'ì' => 'i'
      'ō' | 'ó' | 'ǒ' | 'ò' => 'o'
      'ū' | 'ú' | 'ǔ' | 'ù' => 'u'
      'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' | 'ü' => 'v'
      _ => c
    }
    if o < 'a' || o > 'z' {
      return ""
    }
    b.write_char(o)
  }
  let t = b.to_string()
  // (the syllables of a lone nasal: 呣 m, 嗯 n, ng, 哼 hm, hng)
  match t {
    "" | "m" | "n" | "ng" | "hm" | "hng" => ""
    _ => t
  }
}

///|
fn parse_int(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return -1
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
fn read(path : String) -> String {
  match @sys.read_text(path) {
    Some(t) => t
    None => {
      fail("\{path} not there")
      ""
    }
  }
}

///|
/// A line's text before its comment (`#`), trimmed.
fn uncommented(line : String) -> String {
  let b = StringBuilder::new()
  for c in line {
    if c == '#' {
      break
    }
    b.write_char(c)
  }
  b.to_string().trim(chars=" \t\r").to_string()
}

///|
/// pinyin-data's lines (`U+4E2D: zhōng,zhòng  # 中`): each character's readings, toneless, in their order, each once.
fn char_readings(text : String) -> Map[Char, Array[String]] {
  let out : Map[Char, Array[String]] = {}
  for raw in text.split("\n") {
    let line = uncommented(raw.to_string())
    if !line.has_prefix("U+") {
      continue
    }
    let parts = line.split(":").map(fn(p) { p.to_string() }).collect()
    if parts.length() != 2 {
      continue
    }
    let hex = parts[0].view(start_offset=2).to_string()
    let mut code = 0
    for c in hex {
      let d = if c >= '0' && c <= '9' {
        c.to_int() - '0'.to_int()
      } else if c >= 'A' && c <= 'F' {
        c.to_int() - 'A'.to_int() + 10
      } else {
        c.to_int() - 'a'.to_int() + 10
      }
      code = code * 16 + d
    }
    let ch = Char::from_int(code)
    let rs : Array[String] = []
    for r in parts[1].split(",") {
      let t = toneless(r.trim(chars=" \t").to_string())
      if t != "" && !rs.contains(t) {
        rs.push(t)
      }
    }
    if rs.length() > 0 {
      out[ch] = rs
    }
  }
  out
}

///|
/// phrase-pinyin-data's lines (`银行: yín háng`): each word's readings (a word read two ways is on two lines).
fn phrase_readings(text : String) -> Map[String, Array[Array[String]]] {
  let out : Map[String, Array[Array[String]]] = {}
  for raw in text.split("\n") {
    let line = uncommented(raw.to_string())
    let parts = line.split(":").map(fn(p) { p.to_string() }).collect()
    if parts.length() != 2 {
      continue
    }
    let word = parts[0].trim(chars=" \t").to_string()
    let syls : Array[String] = []
    let mut ok = true
    for r in parts[1].split(" ") {
      let s = r.to_string()
      if s == "" {
        continue
      }
      let t = toneless(s)
      if t == "" {
        ok = false
      }
      syls.push(t)
    }
    if !ok || syls.length() != word.char_length() {
      continue
    }
    match out.get(word) {
      Some(rs) => if !rs.contains(syls) { rs.push(syls) }
      None => out[word] = [syls]
    }
  }
  out
}

///|
/// The cost of a character read otherwise than usually, alone or in a word phrase-pinyin-data does not read: e³ times
/// rarer.
let other_reading : Int = 30

///|
/// The most ways a word phrase-pinyin-data does not read is read, by its characters' readings.
let ways_most : Int = 4

///|
/// The rarest word kept (jieba's count): jieba's least common words are mostly names and fragments.
let count_least : Int = 5

///|
/// The ways `word` is read character by character, each with its added cost: by the usual readings first, then
/// one character at a time read otherwise, at most `ways_most`.
fn composed(
  word : String,
  usual : Map[Char, String],
  all : Map[Char, Array[String]],
) -> Array[(Array[String], Int)] {
  let chars = word.to_array()
  let base : Array[String] = []
  for c in chars {
    match usual.get(c) {
      Some(r) => base.push(r)
      None =>
        match all.get(c) {
          Some(rs) => base.push(rs[0])
          None => return []
        }
    }
  }
  let out : Array[(Array[String], Int)] = [(base, 0)]
  for i, c in chars {
    match all.get(c) {
      Some(rs) =>
        for r in rs {
          if out.length() >= ways_most {
            return out
          }
          if r != base[i] {
            let other = base.copy()
            other[i] = r
            out.push((other, other_reading))
          }
        }
      None => ()
    }
  }
  out
}

///|
fn main {
  let argv = @env.args()
  if argv.length() != 6 {
    @sys.eprintln(
      "pinyin <jieba dict.txt> <pinyin.txt> <kMandarin_8105.txt> <phrase pinyin.txt> <out words.txt>",
    )
    @sys.exit(2)
  }
  let all = char_readings(read(argv[2]))
  let usual : Map[Char, String] = {}
  for c, rs in char_readings(read(argv[3])) {
    usual[c] = rs[0]
  }
  let phrases = phrase_readings(read(argv[4]))
  // jieba's words and counts, Han alone
  let counts : Map[String, Int] = {}
  let mut total = 0.0
  for raw in read(argv[1]).split("\n") {
    let parts = raw.to_string().split(" ").map(fn(p) { p.to_string() }).collect()
    if parts.length() < 2 {
      continue
    }
    let word = parts[0]
    let n = parse_int(parts[1])
    if n <= 0 || word == "" || !word.to_array().iter().all(fn(c) { usual.contains(c) }) {
      continue
    }
    total += n.to_double()
    let keep = n >= count_least || word.char_length() == 1 || phrases.contains(word)
    if keep {
      counts[word] = n
    }
  }
  // the characters in common use and the words phrase-pinyin-data reads, though jieba never saw them: once
  for c, _ in usual {
    let w = c.to_string()
    if !counts.contains(w) {
      counts[w] = 1
    }
  }
  for w, _ in phrases {
    if !counts.contains(w) && w.to_array().iter().all(fn(c) { usual.contains(c) }) {
      counts[w] = 1
    }
  }
  // each reading's words, with their costs
  let by_key : Map[String, Array[(String, Int)]] = {}
  fn put(key : String, word : String, cost : Int) {
    match by_key.get(key) {
      Some(ws) => {
        for i, w in ws {
          if w.0 == word {
            if cost < w.1 {
              ws[i] = (word, cost)
            }
            return
          }
        }
        ws.push((word, cost))
      }
      None => by_key[key] = [(word, cost)]
    }
  }
  for word, n in counts {
    let cost = (-10.0 * @math.ln(n.to_double() / total)).round().to_int()
    let chars = word.to_array()
    if chars.length() == 1 {
      let c = chars[0]
      let first = match usual.get(c) {
        Some(r) => r
        None =>
          match all.get(c) {
            Some(rs) => rs[0]
            None => ""
          }
      }
      match all.get(c) {
        Some(rs) =>
          for r in rs {
            put(r, word, if r == first { cost } else { cost + other_reading })
          }
        None => if first != "" { put(first, word, cost) }
      }
      continue
    }
    match phrases.get(word) {
      Some(rs) => for syls in rs { put(syls.join(" "), word, cost) }
      None =>
        for way in composed(word, usual, all) {
          put(way.0.join(" "), word, cost + way.1)
        }
    }
  }
  let keys = by_key.keys().collect()
  keys.sort()
  let out = StringBuilder::new()
  let mut n = 0
  for key in keys {
    let ws = by_key.get(key).unwrap()
    ws.sort_by(fn(a, b) {
      if a.1 != b.1 {
        a.1 - b.1
      } else {
        a.0.compare(b.0)
      }
    })
    out.write_string(key)
    for w in ws {
      out.write_string("\t\{w.0} \{w.1}")
      n += 1
    }
    out.write_char('\n')
  }
  if !@sys.write_text(argv[5], out.to_string()) {
    fail("could not write \{argv[5]}")
  }
  @sys.eprintln("pinyin: \{n} words in \{keys.length()} readings")
}
