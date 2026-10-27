// What the keyboard's keys do, apart from how it looks: Chinese by pinyin (src/pinyin's Composer: 小鹤双拼 or full
// pinyin), or letters as they are; a page of digits and signs; Shift. Each key says what goes to the field (`Out`):
// what the keyboard's view hands its host (Keyboard.java).

///|
/// What goes to the field.
pub(all) enum Out {
  /// these words put in at the caret
  Commit(String)
  /// what is before the caret, one character, taken out
  Delete
  /// the field's Enter (its action, or a new line)
  Enter
} derive(Eq, Show, Debug)

///|
pub(all) enum Page {
  Letters
  Signs
} derive(Eq, Show, Debug)

///|
pub(all) enum Shift {
  Off
  /// the next letter a capital
  Once
  /// every letter a capital, until Shift again
  Locked
} derive(Eq, Show, Debug)

///|
/// What a key is.
pub(all) enum Key {
  Letter(Char)
  /// full pinyin's syllable break (xi'an)
  Break
  ShiftKey
  Back
  /// to the page of digits and signs, or back to the letters
  PageKey
  /// Chinese or letters as they are
  Lang
  Space
  EnterKey
  /// words put in as they are (a digit, a sign)
  Words(String)
} derive(Eq, Show, Debug)

///|
pub struct Board {
  /// None until the words are read (and where there are none: letters only)
  composer : @pinyin.Composer?
  mut chinese : Bool
  mut page : Page
  mut shift : Shift
  /// when Shift was last tapped (two taps close together lock it)
  priv mut shift_at : Double
  /// what the field takes (Keyboard.java's kind: text, number, phone, password, email, url)
  mut kind : String
  /// what its Enter does (send, search, go, done, next, enter)
  mut action : String
}

///|
pub fn Board::new(composer : @pinyin.Composer?) -> Board {
  {
    composer,
    chinese: composer is Some(_),
    page: Letters,
    shift: Off,
    shift_at: -1000.0,
    kind: "text",
    action: "enter",
  }
}

///|
/// How close two taps of Shift are to lock it, in ms.
let shift_twice_ms : Double = 350.0

///|
/// Whether pinyin is being typed (the keys then act on it: Space picks, Back takes a key back).
pub fn Board::composing(self : Board) -> Bool {
  match self.composer {
    Some(c) => self.chinese && c.active()
    None => false
  }
}

///|
/// Whether the letters typed go to pinyin (Chinese, and not a field for a password, an address or a link).
fn Board::pinyin(self : Board) -> Bool {
  self.chinese &&
  self.composer is Some(_) &&
  !["password", "email", "url"].contains(self.kind)
}

///|
/// A field begun: what it takes and its Enter; anything being typed let go, the page its kind's.
pub fn Board::start(self : Board, kind : String, action : String) -> Unit {
  self.kind = kind
  self.action = action
  match self.composer {
    Some(c) => c.clear()
    None => ()
  }
  self.shift = Off
  self.page = if kind == "number" || kind == "phone" { Signs } else { Letters }
}

///|
/// Whatever is being typed put in the field as its best words (the first offered, picked until all the keys have
/// theirs), or nothing.
fn Board::flush(self : Board) -> Array[Out] {
  match self.composer {
    Some(c) if c.active() => {
      for _ in 0..<64 {
        if c.candidates().length() == 0 {
          let typed = c.as_typed()
          c.clear()
          return [Commit(typed)]
        }
        match c.pick(0) {
          Some(text) => return [Commit(text)]
          None => ()
        }
      }
      let typed = c.as_typed()
      c.clear()
      [Commit(typed)]
    }
    _ => []
  }
}

///|
/// A key tapped at `now` (ms).
pub fn Board::tap(self : Board, key : Key, now : Double) -> Array[Out] {
  match key {
    Letter(l) => {
      let capital = self.shift != Off
      if self.shift == Once {
        self.shift = Off
      }
      if self.pinyin() && !capital {
        let c = self.composer.unwrap()
        c.press(l)
        return []
      }
      let s = if capital { l.to_string().to_upper() } else { l.to_string() }
      self.flush() + [Commit(s)]
    }
    Break =>
      match self.composer {
        Some(c) if self.pinyin() && c.takes('\'') => {
          c.press('\'')
          []
        }
        _ => [Commit("'")]
      }
    ShiftKey => {
      self.shift = match self.shift {
        Off => if now - self.shift_at <= shift_twice_ms { Locked } else { Once }
        Once => if now - self.shift_at <= shift_twice_ms { Locked } else { Off }
        Locked => Off
      }
      self.shift_at = now
      []
    }
    Back => self.back()
    PageKey => {
      self.page = match self.page {
        Letters => Signs
        Signs => Letters
      }
      []
    }
    Lang => {
      let out = match self.composer {
        Some(c) if c.active() => {
          let typed = c.as_typed()
          c.clear()
          [Commit(typed)]
        }
        _ => []
      }
      self.chinese = !self.chinese && self.composer is Some(_)
      out
    }
    Space =>
      if self.composing() {
        self.flush()
      } else {
        [Commit(" ")]
      }
    EnterKey =>
      match self.composer {
        Some(c) if self.composing() => {
          let typed = c.as_typed()
          c.clear()
          [Commit(typed)]
        }
        _ => [Enter]
      }
    Words(w) => self.flush() + [Commit(w)]
  }
}

///|
/// Back: the last key of what is being typed taken back, else a character before the caret.
pub fn Board::back(self : Board) -> Array[Out] {
  match self.composer {
    Some(c) if self.composing() => {
      let _ = c.back()
      []
    }
    _ => [Delete]
  }
}

///|
/// Candidate `i` (of what is offered for the pinyin) picked: its words in the field once all the keys have theirs.
pub fn Board::pick(self : Board, i : Int) -> Array[Out] {
  match self.composer {
    Some(c) =>
      match c.pick(i) {
        Some(text) => [Commit(text)]
        None => []
      }
    None => []
  }
}
