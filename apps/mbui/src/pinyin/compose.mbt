// What is being typed, between the first key and the words given to the field: the keys, the words picked for the
// keys' start so far (中国 picked from zhongguoren, 人 still to pick), what to offer for the rest. The keyboard says
// each key and pick; what it gets back is the words to put in the field when all the keys have theirs.

///|
pub struct Composer {
  dict : Dict
  priv mut speller : Speller
  learned : Learned
  /// the keys typed (letters, and `'`)
  priv mut typed : String
  /// the words picked so far, each for the keys after the one before's
  priv picked : Array[Candidate]
  /// how many of the keys typed the picks use
  priv mut used : Int
  /// what was offered for the rest, until a key or pick changes it
  priv mut offered : Array[Candidate]?
}

///|
pub fn Composer::new(dict : Dict, scheme : Scheme, learned? : Learned = Learned::new()) -> Composer {
  {
    dict,
    speller: Speller::new(dict, scheme),
    learned,
    typed: "",
    picked: [],
    used: 0,
    offered: None,
  }
}

///|
pub fn Composer::scheme(self : Composer) -> Scheme {
  self.speller.scheme
}

///|
/// Syllables typed otherwise from now on (what is being typed let go).
pub fn Composer::set_scheme(self : Composer, scheme : Scheme) -> Unit {
  if scheme != self.speller.scheme {
    self.speller = Speller::new(self.dict, scheme)
    self.clear()
  }
}

///|
/// Whether anything is being typed (the keyboard's keys then act on it, not on the field).
pub fn Composer::active(self : Composer) -> Bool {
  self.typed != ""
}

///|
/// The keys typed, as typed.
pub fn Composer::keys(self : Composer) -> String {
  self.typed
}

///|
/// Everything typed let go.
pub fn Composer::clear(self : Composer) -> Unit {
  self.typed = ""
  self.picked.clear()
  self.used = 0
  self.offered = None
}

///|
/// Whether `c` is a key the scheme spells with: a letter, and `'` in full pinyin (not first).
pub fn Composer::takes(self : Composer, c : Char) -> Bool {
  if c >= 'a' && c <= 'z' {
    return true
  }
  c == '\'' && self.speller.scheme == Full && self.typed != ""
}

///|
/// A key typed (one `takes`).
pub fn Composer::press(self : Composer, c : Char) -> Unit {
  self.typed = self.typed + c.to_string()
  self.offered = None
}

///|
/// The last thing typed taken back: the last pick when there is one (its keys offered again), else the last key.
/// False when nothing was being typed (the field's to delete in then).
pub fn Composer::back(self : Composer) -> Bool {
  if self.picked.length() > 0 {
    let p = self.picked.pop().unwrap()
    self.used -= p.typed
    self.offered = None
    return true
  }
  if self.typed == "" {
    return false
  }
  self.typed = self.typed.view(end_offset=self.typed.length() - 1).to_string()
  self.offered = None
  true
}

///|
/// The keys after the ones picked for.
fn Composer::rest(self : Composer) -> String {
  self.typed.view(start_offset=self.used).to_owned()
}

///|
/// What to offer for the keys not yet picked for, best first.
pub fn Composer::candidates(self : Composer) -> Array[Candidate] {
  match self.offered {
    Some(c) => c
    None => {
      let c = self.dict.candidates(self.speller.spell(self.rest()), self.learned)
      self.offered = Some(c)
      c
    }
  }
}

///|
/// Candidate `i` picked. The words for the field when it uses the last of the keys (all the picks', learned from),
/// else None (what is offered now is for the keys after it).
pub fn Composer::pick(self : Composer, i : Int) -> String? {
  let c = self.candidates()
  if i < 0 || i >= c.length() {
    return None
  }
  self.picked.push(c[i])
  self.used += c[i].typed
  self.offered = None
  if self.used < self.typed.length() && self.rest().to_array().iter().any(fn(k) { k != '\'' }) {
    return None
  }
  let text = self.picked.map(fn(p) { p.text }).join("")
  self.learn()
  self.clear()
  Some(text)
}

///|
/// The picks just made learned: each word once more; a phrase of several picks (or a sentence picked whole) a word of
/// the person's own.
fn Composer::learn(self : Composer) -> Unit {
  let syls : Array[Int] = []
  let text = StringBuilder()
  for p in self.picked {
    for x in p.syls {
      syls.push(x)
    }
    text.write_string(p.text)
  }
  let whole = text.to_string()
  if self.picked.length() > 1 || !self.dict.has_word(self.picked[0].syls, self.picked[0].text) {
    if whole.char_length() <= phrase_most {
      self.learned.add_phrase(syls, whole)
      self.learned.picked(whole)
    }
  }
  for p in self.picked {
    self.learned.picked(p.text)
  }
}

///|
/// The longest phrase learned, in characters (longer is a sentence, seldom typed again).
let phrase_most : Int = 8

///|
/// What shows of what is being typed: the words picked, then the rest as the syllables read, `'` between them
/// ("中国ren'min"), or as typed when they read as no words.
pub fn Composer::preedit(self : Composer) -> String {
  let b = StringBuilder()
  for p in self.picked {
    b.write_string(p.text)
  }
  let rest = self.rest()
  if rest != "" {
    match self.dict.syllables_read(self.speller.spell(rest), self.learned) {
      Some(names) => b.write_string(names.join("'"))
      None => b.write_string(rest)
    }
  }
  b.to_string()
}

///|
/// The keys not picked for, as typed (the field's when the person ends with Enter: letters meant as letters), with the
/// words picked before them.
pub fn Composer::as_typed(self : Composer) -> String {
  let b = StringBuilder()
  for p in self.picked {
    b.write_string(p.text)
  }
  for c in self.rest() {
    if c != '\'' {
      b.write_char(c)
    }
  }
  b.to_string()
}
