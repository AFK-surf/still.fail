// What the person has picked: each word how many times (it comes earlier the more), and the phrases they made of
// several picks (中国 then 人民 picked once: 中国人民 a word of theirs after). Kept by the keyboard as text:
//
//   w<TAB>中国<TAB>3
//   p<TAB>zhong guo ren min<TAB>中国人民
//
// A phrase by its syllables' letters, so a newer set of words (other numbers for them) still reads it.

///|
pub struct Learned {
  priv counts : Map[String, Int]
  /// each phrase's syllables (numbers, by commas, after one: ",3,9") and its words
  priv phrases : Map[String, Array[String]]
  /// every start of a phrase's syllables, for the walk to go on past the words there are
  priv starts : Map[String, Int]
}

///|
pub fn Learned::new() -> Learned {
  { counts: Map([]), phrases: Map([]), starts: Map([]) }
}

///|
/// The most a word's picks take off its cost: e⁶ times more often.
let bonus_most : Int = 60

///|
/// What a word's picks take off its cost: the first a lot (a word picked once is meant), each after less.
pub fn Learned::bonus(self : Learned, word : String) -> Int {
  match self.counts.get(word) {
    Some(n) => {
      let b = 30 + 10 * n
      if b > bonus_most {
        bonus_most
      } else {
        b
      }
    }
    None => 0
  }
}

///|
/// What a phrase of the person's own costs: as a fairly common word's, less its picks.
fn Learned::phrase_cost(self : Learned, word : String) -> Int {
  100 - self.bonus(word)
}

///|
fn Learned::has_phrases(self : Learned) -> Bool {
  self.phrases.length() > 0
}

///|
fn Learned::begins(self : Learned, key : String) -> Bool {
  self.starts.contains(key)
}

///|
fn Learned::phrases_at(self : Learned, key : String) -> Array[String] {
  if key == "" {
    return []
  }
  self.phrases.get(key).unwrap_or([])
}

///|
fn key_of(syls : Array[Int]) -> String {
  let b = StringBuilder()
  for s in syls {
    b.write_string(",")
    b.write_string(s.to_string())
  }
  b.to_string()
}

///|
/// `word` picked once more.
pub fn Learned::picked(self : Learned, word : String) -> Unit {
  self.counts[word] = self.counts.get(word).unwrap_or(0) + 1
}

///|
/// A phrase of the person's own: `word`, read as `syls`.
pub fn Learned::add_phrase(self : Learned, syls : Array[Int], word : String) -> Unit {
  let key = key_of(syls)
  match self.phrases.get(key) {
    Some(ws) => if !ws.contains(word) { ws.push(word) }
    None => self.phrases[key] = [word]
  }
  for i in 1..=syls.length() {
    let k = key_of(syls[:i].to_array())
    self.starts[k] = self.starts.get(k).unwrap_or(0) + 1
  }
}

///|
/// All of it as text, to keep.
pub fn Learned::to_text(self : Learned, dict : Dict) -> String {
  let b = StringBuilder()
  let words = self.counts.keys().collect()
  words.sort()
  for w in words {
    b.write_string("w\t\{w}\t\{self.counts.get(w).unwrap()}\n")
  }
  let keys = self.phrases.keys().collect()
  keys.sort()
  for k in keys {
    let names = k
      .split(",")
      .filter(fn(s) { s != "" })
      .map(fn(s) { dict.syllable_name(string_to_int(s)) })
      .collect()
    for w in self.phrases.get(k).unwrap() {
      b.write_string("p\t\{names.join(" ")}\t\{w}\n")
    }
  }
  b.to_string()
}

///|
fn string_to_int(s : StringView) -> Int {
  let mut n = 0
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
  }
  n
}

///|
/// What `to_text` kept, read again for `dict` (a phrase with a syllable it has no word for left out).
pub fn Learned::parse(text : String, dict : Dict) -> Learned {
  let l = Learned::new()
  for line in text.split("\n") {
    let f = line.split("\t").map(fn(s) { s.to_string() }).collect()
    if f.length() == 3 && f[0] == "w" {
      l.counts[f[1]] = string_to_int(f[2])
    } else if f.length() == 3 && f[0] == "p" {
      let syls = f[1].split(" ").map(fn(s) { dict.syllable(s.to_string()) }).collect()
      if syls.length() > 0 && syls.iter().all(fn(s) { s >= 0 }) {
        l.add_phrase(syls, f[2])
      }
    }
  }
  l
}
