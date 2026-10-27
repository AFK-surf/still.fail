// How keys are syllables: the scheme's, before any word. Each spells the keys typed as a lattice: from each place in
// them, the steps on (a syllable, or a few it may be when not all its keys are typed) and where each ends. The words
// (decode.mbt) walk it the same whatever the scheme.

///|
/// How syllables are typed.
pub(all) enum Scheme {
  /// each syllable's letters (中国 zhongguo), a syllable's first letters alone for it (zg), `'` between two where
  /// they would read otherwise (xi'an)
  Full
  /// 小鹤双拼: each syllable two keys, its initial's and its final's (中国 vsgo); a last key alone its initial
  Xiaohe
} derive(Eq, Show, Debug)

///|
/// One step through the keys: from where it starts to `end`, as one of `syls`, and what taking it so adds to a word's
/// cost: nothing for a syllable typed whole, `begun_cost` for one only begun (an initial alone, or the last keys typed
/// so far), `begun_whole_cost` for the last keys taken as the start of a longer syllable though they are one already
/// (xian as xiang's start: the person more likely means xian).
pub struct Step {
  end : Int
  syls : Array[Int]
  cost : Int
}

///|
let begun_cost : Int = 5

///|
let begun_whole_cost : Int = 25

///|
/// The keys typed, spelled: the steps from each place in them (`steps[i]`), places counted in the keys a syllable is
/// typed with (`'` is none), and the place in what was typed each is (`typed_at`, one more than the places: the end).
pub struct Spelled {
  steps : Array[Array[Step]]
  typed_at : Array[Int]
}

///|
pub fn Spelled::length(self : Spelled) -> Int {
  self.steps.length()
}

///|
/// What a scheme reads keys as, for one set of words' syllables.
pub struct Speller {
  scheme : Scheme
  /// Full: each syllable's letters and every start of them, the syllables they begin
  priv starts : Map[String, Array[Int]]
  priv whole : Map[String, Int]
  /// Xiaohe: each two keys' syllables, and each key's alone (its initial's)
  priv pairs : Map[String, Array[Int]]
  priv singles : Map[String, Array[Int]]
}

///|
/// A syllable's initial: zh, ch, sh, one consonant, or "" (a, o, e, er, ai…).
fn initial_of(s : String) -> String {
  if s.has_prefix("zh") || s.has_prefix("ch") || s.has_prefix("sh") {
    return s.view(end_offset=2).to_owned()
  }
  let c = s.view(end_offset=1).to_owned()
  match c {
    "a" | "o" | "e" => ""
    _ => c
  }
}

///|
/// 小鹤双拼's finals, by key.
fn xiaohe_finals(k : Char) -> Array[String] {
  match k {
    'q' => ["iu"]
    'w' => ["ei"]
    'e' => ["e"]
    'r' => ["uan", "van"]
    't' => ["ue", "ve"]
    'y' => ["un", "vn"]
    'u' => ["u"]
    'i' => ["i"]
    'o' => ["o", "uo"]
    'p' => ["ie"]
    'a' => ["a"]
    's' => ["iong", "ong"]
    'd' => ["ai"]
    'f' => ["en"]
    'g' => ["eng"]
    'h' => ["ang"]
    'j' => ["an"]
    'k' => ["uai", "ing"]
    'l' => ["iang", "uang"]
    'z' => ["ou"]
    'x' => ["ia", "ua"]
    'c' => ["ao"]
    'v' => ["ui", "v"]
    'b' => ["in"]
    'n' => ["iao"]
    'm' => ["ian"]
    _ => []
  }
}

///|
/// 小鹤双拼's initial, by key: v, i and u are zh, ch and sh; a, o and e begin a syllable without one (None).
fn xiaohe_initial(k : Char) -> String? {
  match k {
    'v' => Some("zh")
    'i' => Some("ch")
    'u' => Some("sh")
    'a' | 'o' | 'e' => None
    _ => Some(k.to_string())
  }
}

///|
/// The syllables 小鹤双拼's keys `a` and `b` are: initial and final; without an initial (a, o, e first) the key
/// itself twice for a lone vowel (aa a), the two keys' letters (ai, an, ou, er) or the second key's final when it
/// begins with the first (ah ang, eg eng).
fn xiaohe_pair(a : Char, b : Char) -> Array[String] {
  let out : Array[String] = []
  match xiaohe_initial(a) {
    Some(i) => for f in xiaohe_finals(b) { out.push(i + f) }
    None => {
      if a == b {
        out.push(a.to_string())
      }
      out.push(a.to_string() + b.to_string())
      for f in xiaohe_finals(b) {
        if f.view(end_offset=1).to_owned() == a.to_string() {
          out.push(f)
        }
      }
    }
  }
  out
}

///|
let letters : String = "abcdefghijklmnopqrstuvwxyz"

///|
pub fn Speller::new(dict : Dict, scheme : Scheme) -> Speller {
  let starts : Map[String, Array[Int]] = Map([])
  let whole : Map[String, Int] = Map([])
  let pairs : Map[String, Array[Int]] = Map([])
  let singles : Map[String, Array[Int]] = Map([])
  fn add(m : Map[String, Array[Int]], k : String, id : Int) {
    match m.get(k) {
      Some(a) => if !a.contains(id) { a.push(id) }
      None => m[k] = [id]
    }
  }
  match scheme {
    Full =>
      for id in 0..<dict.syllables() {
        let name = dict.syllable_name(id)
        whole[name] = id
        for n in 1..<name.length() {
          add(starts, name.view(end_offset=n).to_owned(), id)
        }
      }
    Xiaohe => {
      for a in letters {
        for b in letters {
          for s in xiaohe_pair(a, b) {
            let id = dict.syllable(s)
            if id >= 0 {
              add(pairs, a.to_string() + b.to_string(), id)
            }
          }
        }
      }
      for id in 0..<dict.syllables() {
        let name = dict.syllable_name(id)
        let i = initial_of(name)
        for k in letters {
          let ok = match xiaohe_initial(k) {
            Some(ki) => ki == i
            None => i == "" && name.view(end_offset=1).to_owned() == k.to_string()
          }
          if ok {
            add(singles, k.to_string(), id)
          }
        }
      }
    }
  }
  { scheme, starts, whole, pairs, singles }
}

///|
/// Whether `s` is an initial typed alone in the middle of full pinyin (zg 中国): a consonant's letter, or zh, ch, sh.
fn initial_alone(s : String) -> Bool {
  match s {
    "zh" | "ch" | "sh" => true
    "a" | "o" | "e" | "i" | "u" | "v" => false
    _ => s.length() == 1
  }
}

///|
/// The longest syllable's letters.
let syllable_most : Int = 6

///|
/// `typed` (letters, and `'` where the scheme takes it), spelled.
pub fn Speller::spell(self : Speller, typed : String) -> Spelled {
  let keys = StringBuilder()
  let typed_at : Array[Int] = []
  // (a place a `'` is before: no step goes over it)
  let breaks : Array[Bool] = []
  let mut broken = false
  for i, c in typed.to_array() {
    if c == '\'' {
      broken = true
      continue
    }
    typed_at.push(i)
    breaks.push(broken)
    broken = false
    keys.write_char(c)
  }
  typed_at.push(typed.length())
  breaks.push(broken)
  let k = keys.to_string()
  let n = k.length()
  let steps : Array[Array[Step]] = Array::makei(n, fn(_) { [] })
  match self.scheme {
    Full =>
      for i in 0..<n {
        let mut j = i + 1
        while j <= n && j - i <= syllable_most {
          if j > i + 1 && breaks[j - 1] {
            break
          }
          let s = k.view(start_offset=i, end_offset=j).to_owned()
          match self.whole.get(s) {
            Some(id) => steps[i].push({ end: j, syls: [id], cost: 0 })
            None => ()
          }
          if j == n || initial_alone(s) {
            match self.starts.get(s) {
              Some(ids) => {
                let cost = if self.whole.contains(s) { begun_whole_cost } else { begun_cost }
                steps[i].push({ end: j, syls: ids, cost })
              }
              None => ()
            }
          }
          j += 1
        }
      }
    Xiaohe =>
      for i in 0..<n {
        if (i % 2) != 0 {
          continue
        }
        if i + 2 <= n {
          match self.pairs.get(k.view(start_offset=i, end_offset=i + 2).to_owned()) {
            Some(ids) => steps[i].push({ end: i + 2, syls: ids, cost: 0 })
            None => ()
          }
        } else {
          match self.singles.get(k.view(start_offset=i, end_offset=i + 1).to_owned()) {
            Some(ids) => steps[i].push({ end: i + 1, syls: ids, cost: begun_cost })
            None => ()
          }
        }
      }
  }
  { steps, typed_at }
}
