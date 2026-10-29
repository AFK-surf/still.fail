// The keyboard's words, as the pinyin engine reads them: a trie by syllables, each node the words read as the
// syllables on the way to it, cheapest first. Made from words.txt (tools/pinyin says how), one reading a line:
//
//   zhong guo<TAB>中国 52<TAB>种过 140
//
// The syllables (toneless, ü as v) by spaces, then each word read so and its cost: ten times the natural log of how
// much rarer than all words together it is, so a sentence's cost is its words' costs added.

///|
/// The words, by their syllables.
pub struct Dict {
  /// each syllable by its number (in the order of their letters), and the number of each
  priv names : Array[String]
  priv ids : Map[String, Int]
  /// the trie's nodes (0 the root): each one's syllable, its children (together, by syllable) and its words
  priv syl : Array[Int]
  priv kid_start : Array[Int]
  priv kid_count : Array[Int]
  priv word_start : Array[Int]
  priv word_count : Array[Int]
  /// the words of all nodes, each node's together and cheapest first
  priv words : Array[String]
  priv costs : Array[Int]
}

///|
priv struct Reading {
  key : Array[Int]
  words : Array[(String, Int)]
}

///|
fn compare_keys(a : Array[Int], b : Array[Int]) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return a[i] - b[i]
    }
  }
  a.length() - b.length()
}

///|
fn parse_cost(s : StringView) -> Int {
  let mut n = 0
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
  }
  n
}

///|
/// The words in `text` (words.txt's lines).
pub fn Dict::parse(text : String) -> Dict {
  let lines : Array[(Array[String], Array[(String, Int)])] = []
  let names_seen : Map[String, Bool] = Map([])
  for line in text.split("\n") {
    let fields = line.split("\t").collect()
    if fields.length() < 2 {
      continue
    }
    let syls = fields[0].split(" ").map(fn(s) { s.to_string() }).collect()
    for s in syls {
      names_seen[s] = true
    }
    let ws : Array[(String, Int)] = []
    for f in fields[1:] {
      let parts = f.split(" ").collect()
      if parts.length() == 2 {
        ws.push((parts[0].to_string(), parse_cost(parts[1])))
      }
    }
    lines.push((syls, ws))
  }
  let names = names_seen.keys().collect()
  names.sort()
  let ids : Map[String, Int] = Map([])
  for i, n in names {
    ids[n] = i
  }
  let readings = lines.map(fn(l) {
    Reading::{ key: l.0.map(fn(s) { ids.get(s).unwrap() }), words: l.1 }
  })
  readings.sort_by(fn(a, b) { compare_keys(a.key, b.key) })
  let d = Dict::{
    names,
    ids,
    syl: [-1],
    kid_start: [0],
    kid_count: [0],
    word_start: [0],
    word_count: [0],
    words: [],
    costs: [],
  }
  d.build(0, readings, 0, readings.length(), 0)
  d
}

///|
/// Node `node`'s words and children from `readings[lo:hi]`, which all begin with its syllables (`depth` of them).
fn Dict::build(
  self : Dict,
  node : Int,
  readings : Array[Reading],
  lo : Int,
  hi : Int,
  depth : Int,
) -> Unit {
  let mut i = lo
  // (the reading that ends here sorts first: the shorter of two the one begins)
  self.word_start[node] = self.words.length()
  while i < hi && readings[i].key.length() == depth {
    for w in readings[i].words {
      self.words.push(w.0)
      self.costs.push(w.1)
    }
    i += 1
  }
  self.word_count[node] = self.words.length() - self.word_start[node]
  // the children, one for each next syllable, made together before any of their own
  let groups : Array[(Int, Int, Int)] = []
  while i < hi {
    let s = readings[i].key[depth]
    let start = i
    while i < hi && readings[i].key[depth] == s {
      i += 1
    }
    groups.push((s, start, i))
  }
  self.kid_start[node] = self.syl.length()
  self.kid_count[node] = groups.length()
  for g in groups {
    self.syl.push(g.0)
    self.kid_start.push(0)
    self.kid_count.push(0)
    self.word_start.push(0)
    self.word_count.push(0)
  }
  for k, g in groups {
    self.build(self.kid_start[node] + k, readings, g.1, g.2, depth + 1)
  }
}

///|
/// Node `node`'s child by syllable `s`, or -1.
fn Dict::kid(self : Dict, node : Int, s : Int) -> Int {
  let mut lo = self.kid_start[node]
  let mut hi = lo + self.kid_count[node]
  while lo < hi {
    let mid = (lo + hi) / 2
    let m = self.syl[mid]
    if m == s {
      return mid
    } else if m < s {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  -1
}

///|
/// The number of syllable `name`, or -1 when no word is read with it.
pub fn Dict::syllable(self : Dict, name : String) -> Int {
  self.ids.get(name).unwrap_or(-1)
}

///|
/// Syllable `id`'s letters.
pub fn Dict::syllable_name(self : Dict, id : Int) -> String {
  self.names[id]
}

///|
/// How many syllables words are read with.
pub fn Dict::syllables(self : Dict) -> Int {
  self.names.length()
}

///|
/// How many words (readings of words) there are.
pub fn Dict::size(self : Dict) -> Int {
  self.words.length()
}

///|
/// Whether `word` is one of the words, read as `syls`.
pub fn Dict::has_word(self : Dict, syls : Array[Int], word : String) -> Bool {
  let mut node = 0
  for s in syls {
    node = self.kid(node, s)
    if node < 0 {
      return false
    }
  }
  let start = self.word_start[node]
  for i in start..<(start + self.word_count[node]) {
    if self.words[i] == word {
      return true
    }
  }
  false
}
