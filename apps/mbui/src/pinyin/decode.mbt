// From the keys spelled (spell.mbt) to words: every word the lattice reads from a place, the cheapest sentence over
// all of it (the words' costs added, Viterbi), and what the person picks offered first.

///|
/// One thing to pick: its words, how much of what was typed it uses (from the place it was asked from), its syllables
/// and its cost.
pub struct Candidate {
  text : String
  typed : Int
  syls : Array[Int]
  cost : Int
} derive(Show)

///|
/// A word reached in the lattice: where it ends, its trie node (or -1: the person's own phrase alone), the syllables
/// on the way and what its steps add to its cost (syllables only begun: Step).
priv struct Reach {
  end : Int
  node : Int
  key : String
  syls : Array[Int]
  extra : Int
}

///|
/// Every word read from place `from` on, as `f` is told.
fn Dict::walk(
  self : Dict,
  sp : Spelled,
  learned : Learned,
  from : Int,
  f : (Reach) -> Unit,
) -> Unit {
  let syls : Array[Int] = []
  let own = learned.has_phrases()
  fn go(at : Int, node : Int, key : String, extra : Int) -> Unit {
    if at >= sp.length() {
      return
    }
    for step in sp.steps[at] {
      for s in step.syls {
        let kid = if node >= 0 { self.kid(node, s) } else { -1 }
        let k = if own { key + "," + s.to_string() } else { "" }
        let mine = own && learned.begins(k)
        if kid < 0 && !mine {
          continue
        }
        syls.push(s)
        let e = extra + step.cost
        f({ end: step.end, node: kid, key: k, syls: syls.copy(), extra: e })
        go(step.end, kid, k, e)
        let _ = syls.pop()
      }
    }
  }
  go(from, 0, "", 0)
}

///|
/// The words at a place reached, each with its cost there (the person's picks taken in).
fn Dict::words_at(self : Dict, r : Reach, learned : Learned) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  let extra = r.extra
  if r.node >= 0 {
    let start = self.word_start[r.node]
    for i in start..<(start + self.word_count[r.node]) {
      out.push((self.words[i], self.costs[i] - learned.bonus(self.words[i]) + extra))
    }
  }
  for w in learned.phrases_at(r.key) {
    out.push((w, learned.phrase_cost(w) + extra))
  }
  out
}

///|
/// The cheapest word at a place reached, and its cost.
fn Dict::best_at(self : Dict, r : Reach, learned : Learned) -> (String, Int)? {
  let extra = r.extra
  let mut best : (String, Int)? = None
  if r.node >= 0 {
    let start = self.word_start[r.node]
    for i in start..<(start + self.word_count[r.node]) {
      // (cheapest first: once a word's cost less the most a pick takes off is no better, no later one is)
      match best {
        Some(b) => if self.costs[i] - bonus_most + extra >= b.1 { break }
        None => ()
      }
      let c = self.costs[i] - learned.bonus(self.words[i]) + extra
      match best {
        Some(b) => if c < b.1 { best = Some((self.words[i], c)) }
        None => best = Some((self.words[i], c))
      }
    }
  }
  for w in learned.phrases_at(r.key) {
    let c = learned.phrase_cost(w) + extra
    match best {
      Some(b) => if c < b.1 { best = Some((w, c)) }
      None => best = Some((w, c))
    }
  }
  best
}

///|
/// The cheapest sentence over all the keys, as one candidate, or None when they are no words.
pub fn Dict::sentence(self : Dict, sp : Spelled, learned : Learned) -> Candidate? {
  let n = sp.length()
  if n == 0 {
    return None
  }
  let inf = 1 << 30
  let best : Array[Int] = Array::make(n + 1, inf)
  // (how each place was best reached: from where, by which word, as which syllables)
  let back : Array[(Int, String, Array[Int])] = Array::make(n + 1, (-1, "", []))
  best[0] = 0
  for i in 0..<n {
    if best[i] == inf {
      continue
    }
    self.walk(sp, learned, i, fn(r) {
      match self.best_at(r, learned) {
        Some((w, c)) =>
          if best[i] + c < best[r.end] {
            best[r.end] = best[i] + c
            back[r.end] = (i, w, r.syls)
          }
        None => ()
      }
    })
  }
  if best[n] == inf {
    return None
  }
  let words : Array[String] = []
  let syls : Array[Array[Int]] = []
  let mut at = n
  while at > 0 {
    let (from, w, s) = back[at]
    words.push(w)
    syls.push(s)
    at = from
  }
  words.rev_in_place()
  syls.rev_in_place()
  let all : Array[Int] = []
  for s in syls {
    for x in s {
      all.push(x)
    }
  }
  Some({ text: words.join(""), typed: sp.typed_at[n], syls: all, cost: best[n] })
}

///|
/// What to offer for the keys spelled: the cheapest sentence over them all first (when it is more than one word), then
/// every word read from their start, the ones using the most keys first and the cheapest first among those; each text
/// once, at most `most`.
pub fn Dict::candidates(
  self : Dict,
  sp : Spelled,
  learned : Learned,
  most? : Int = 200,
) -> Array[Candidate] {
  let found : Array[Candidate] = []
  self.walk(sp, learned, 0, fn(r) {
    for w in self.words_at(r, learned) {
      found.push({ text: w.0, typed: sp.typed_at[r.end], syls: r.syls, cost: w.1 })
    }
  })
  found.sort_by(fn(a, b) {
    if a.typed != b.typed {
      b.typed - a.typed
    } else {
      a.cost - b.cost
    }
  })
  let out : Array[Candidate] = []
  let seen : Map[String, Bool] = Map([])
  match self.sentence(sp, learned) {
    Some(s) =>
      if found.length() == 0 || found[0].text != s.text {
        // (a sentence that is a word read whole is that word, found below)
        let whole = found.iter().any(fn(c) { c.text == s.text && c.typed == s.typed })
        if !whole {
          out.push(s)
          seen[s.text] = true
        }
      }
    None => ()
  }
  for c in found {
    if out.length() >= most {
      break
    }
    if !seen.contains(c.text) {
      seen[c.text] = true
      out.push(c)
    }
  }
  out
}

///|
/// The syllables the cheapest reading of the keys spelled has, as their letters ("zhong guo"; a step only begun as the
/// syllable its word took: zg as zhong guo), or None when they are no words.
pub fn Dict::syllables_read(self : Dict, sp : Spelled, learned : Learned) -> Array[String]? {
  match self.sentence(sp, learned) {
    Some(s) => Some(s.syls.map(fn(id) { self.syllable_name(id) }))
    None => None
  }
}
