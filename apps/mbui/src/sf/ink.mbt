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
/// vitesse-light's colour (its tokenColors), each made to read on a code block's ground (4.5:1, WCAG's AA: its hue
/// and chroma, its lightness moved the least; a string's and a property's quotes as the words they hold, not faded,
/// docs/ui-panels.md 对比度).
fn Scope::light(self : Scope) -> Int64 {
  match self {
    Text => 0x393A34FFL
    Comment => 0x667266FFL
    Punct => 0x6F6F6FFFL
    Str => 0xA55B4BFFL
    Quote => 0xA55B4BFFL
    Num => 0x2E7889FFL
    Control => 0x1E754FFFL
    Storage => 0xA95757FFL
    Func => 0x4E7B2EFFL
    Var => 0x96652FFFL
    Constant => 0xA55D2AFFL
    TypeName => 0x137D71FFL
    Property => 0x836E00FFL
    PropertyQuote => 0x836E00FFL
    Added => 0x198034FFL
    Removed => 0xB31D28FFL
    Hunk => 0x6F42C1FFL
  }
}

///|
/// vitesse-dark's colour for the same (Shiki's `--shiki-dark` beside the light one), made to read as the light ones.
fn Scope::dark(self : Scope) -> Int64 {
  match self {
    Text => 0xDBD7CAEEL
    Comment => 0x869786FFL
    Punct => 0x939393FFL
    Str => 0xC98A7DFFL
    Quote => 0xC98A7DFFL
    Num => 0x52A096FFL
    Control => 0x5AA081FFL
    Storage => 0xD07B7AFFL
    Func => 0x80A665FFL
    Var => 0xBD976AFFL
    Constant => 0xC99076FFL
    TypeName => 0x5DA994FFL
    Property => 0xB8A965FFL
    PropertyQuote => 0xB8A965FFL
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
