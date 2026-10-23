// Code in its colours: the core says what each piece of it is (client/core-ts/src/highlight.ts: `code.ink`, and a
// Markdown code block's `ink`), this paints each in the theme's colours, vitesse light and dark as the web's Shiki has
// them. Nothing here reads code: a language is only passed on.

///|
/// What vitesse colours a piece of code as.
priv enum Scope {
  Text
  Comment
  Punct
  Str
  /// a string's quotes
  Quote
  Num
  /// keyword, keyword.control, constant.language (true, None), entity.name.tag
  Control
  /// storage (function, const, class), keyword.operator, null, undefined
  Storage
  Func
  Var
  /// constant, variable.language (this, self), an option (-x)
  Constant
  TypeName
  /// property names, support (builtins as print, echo)
  Property
  PropertyQuote
  /// a diff's lines added and removed, a hunk's range (Shiki's own diff colours)
  Added
  Removed
  Hunk
} derive(Eq)

///|
/// vitesse-light's colour (its tokenColors).
fn Scope::light(self : Scope) -> Int64 {
  match self {
    Text => 0x393A34FFL
    Comment => 0xA0ADA0FFL
    Punct => 0x999999FFL
    Str => 0xB56959FFL
    Quote => 0xB5695977L
    Num => 0x2F798AFFL
    Control => 0x1E754FFFL
    Storage => 0xAB5959FFL
    Func => 0x59873AFFL
    Var => 0xB07D48FFL
    Constant => 0xA65E2BFFL
    TypeName => 0x2E8F82FFL
    Property => 0x998418FFL
    PropertyQuote => 0x99841877L
    Added => 0x22863AFFL
    Removed => 0xB31D28FFL
    Hunk => 0x6F42C1FFL
  }
}

///|
/// vitesse-dark's colour for the same (Shiki's `--shiki-dark` beside the light one).
fn Scope::dark(self : Scope) -> Int64 {
  match self {
    Text => 0xDBD7CAEEL
    Comment => 0x758575DDL
    Punct => 0x666666FFL
    Str => 0xC98A7DFFL
    Quote => 0xC98A7D77L
    Num => 0x4C9A91FFL
    Control => 0x4D9375FFL
    Storage => 0xCB7676FFL
    Func => 0x80A665FFL
    Var => 0xBD976AFFL
    Constant => 0xC99076FFL
    TypeName => 0x5DA994FFL
    Property => 0xB8A965FFL
    PropertyQuote => 0xB8A96577L
    Added => 0x85E89DFFL
    Removed => 0xFDAEB7FFL
    Hunk => 0xB392F0FFL
  }
}


///|
// The core's ink is a scope letter followed by a UTF-16 length (omitted for one). This only assigns colours to
// already classified runs; it does not interpret the code or its language.
fn core_ink(code : String, ink : String, dark : Bool) -> Array[@ui.Run] {
  let scopes : Array[Scope] = [Text,Comment,Punct,Str,Quote,Num,Control,Storage,Func,Var,Constant,TypeName,Property,PropertyQuote,Added,Removed,Hunk]
  let out = []
  let mut i = 0
  let mut at = 0
  while i < ink.length() && at < code.length() {
    let k = ink.at(i).to_int() - 97
    if k < 0 || k >= scopes.length() { break }
    i += 1
    let mut n = 0
    while i < ink.length() {
      let d = ink.at(i).to_int() - 48
      if d < 0 || d > 9 { break }
      n = imin(code.length(), n * 10 + d)
      i += 1
    }
    let end = imin(code.length(), at + (if n > 0 { n } else { 1 }))
    out.push(@ui.span(code.view(start_offset=at,end_offset=end).to_string(),mono=true,color=if dark {scopes[k].dark()}else{scopes[k].light()}))
    at = end
  }
  if at < code.length() { out.push(@ui.span(code.view(start_offset=at).to_string(),mono=true,color=if dark {Scope::Text.dark()}else{Scope::Text.light()})) }
  out
}

///|
/// `code` in the colours of its `ink` (as the core's `code.ink` answered it), as runs for @ui.Ctx::rich in the code
/// face.
pub fn ink_runs(code : String, ink : String, dark : Bool) -> Array[@ui.Run] {
  core_ink(code, ink, dark)
}

///|
/// The core's `code.ink` as the live client asks it: the code, its language, and what to do with its ink (None: the
/// code shown as it is). Bound once as the client starts (sfapp.use_core_markdown); a run without a core has the real
/// core's answers kept (`kept_call`).
pub let ink_read : Ref[((String, String, (String?) -> Unit) -> Unit)?] = Ref(None)

///|
/// The inks answered, by the language and the code; the latest kept, up to `inks_budget` of code.
let inks : Map[String, String?] = {}

///|
let inks_order : Array[String] = []

///|
let inks_used : Ref[Int] = Ref(0)

///|
let inks_budget : Int = 4000000

///|
let inks_asked : Map[String, Bool] = {}

///|
fn init {
  @ui.on_reset(fn() {
    inks.clear(); inks_order.clear(); inks_used.val = 0; inks_asked.clear(); ink_read.val = None
  })
}

///|
fn ink_keep(key : String, ink : String?) -> Unit {
  if !inks.contains(key) {
    inks_order.push(key)
    inks_used.val += key.length()
  }
  inks[key] = ink
  while inks_order.length() > 1 && inks_used.val > inks_budget {
    let old = inks_order[0]
    inks_order.remove(0) |> ignore
    inks_used.val -= old.length()
    inks.remove(old)
    inks_asked.remove(old)
  }
}

///|
/// What each piece of `code` in `lang` is (the core's `code.ink`), once the core has said: None while it is asked;
/// Some(None) for code shown as it is (plain text, Markdown, too long). Asked once by the language and the code.
pub fn code_ink(c : @ui.Ctx, code : String, lang : String) -> String?? {
  let key = lang + "\u{1}" + code
  match inks.get(key) {
    Some(ink) => return Some(ink)
    None => ()
  }
  match (ink_read.val, kept_call.val) {
    (Some(read), _) => {
      if !inks_asked.contains(key) {
        inks_asked[key] = true
        c.tell("ink/" + key, fn() { read(code, lang, fn(ink) { ink_keep(key, ink) }) })
      }
      None
    }
    (None, Some(kept)) => {
      let ink = match kept("code.ink", { "code": Json::string(code), "lang": Json::string(lang) }, None) {
        Some(Ok((Object(m), _))) =>
          match m.get("ink") {
            Some(String(s)) => Some(s)
            _ => None
          }
        _ => None
      }
      ink_keep(key, ink)
      Some(ink)
    }
    (None, None) => Some(None)
  }
}
