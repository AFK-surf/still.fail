// A Style said as text, `css("row h=S7 px=S2 radius=Lg hovered{bg=Hover}")`: what `style(…)` says, read as the app
// starts. An app's named styles are constants (a top-level `let`), and moonc made each `style(…)` call ~5-10 KB of C
// in `moonbit_init` (a temporary, an assignment and a decref for every one of its ~38 optional parameters): ~1400 of
// them were ~11.8 MB of C in one function, built again on every build (2026-10-24: 38 s of Windows' MSVC, and most of
// its link). Said as text they are data, a string each, read here once.

///|
/// A Style from its text: items apart by spaces, each a property as `style(…)` names it with a token as
/// style_tokens.mbt (and node.mbt's Align, Justify) names it: `w=Full`, `px=S2`, `align=ACenter`, `bg=A(Fg, O35)`,
/// `w=Grow(1.0)`, `radius=Exact(3.5)`; `row` and `clip` alone are `=true`. A state's block is its name and the same
/// items in braces: `pressed{bg=Over(Card, A(Fg, O5))}` (narrow, dark, selected, hovered, focused, pressed, disabled).
/// A token is read as its property's type has it (`Full` a Len's in `w=`, a Radius's in `radius=`); a number as its
/// literal in code (the same Double: no more than 2^53 in its digits, and a power of ten of no more than 22, read
/// exactly). Whatever it does not know (a property, a token, a block) aborts naming the text: the constants are read
/// as the app starts, so a mistyped one fails every test at once.
pub fn css(text : String) -> Style {
  let r : Css = { s: text, i: 0 }
  let st : CssStates = {
    narrow: None,
    dark: None,
    selected: None,
    hovered: None,
    focused: None,
    pressed: None,
    disabled: None,
  }
  let base = r.patch(Some(st))
  {
    base,
    narrow: st.narrow,
    dark: st.dark,
    selected: st.selected,
    hovered: st.hovered,
    focused: st.focused,
    pressed: st.pressed,
    disabled: st.disabled,
  }
}

///|
/// The text being read and how far.
priv struct Css {
  s : String
  mut i : Int
}

///|
/// The state blocks read so far, at the top of a style's text.
priv struct CssStates {
  mut narrow : Patch?
  mut dark : Patch?
  mut selected : Patch?
  mut hovered : Patch?
  mut focused : Patch?
  mut pressed : Patch?
  mut disabled : Patch?
}

///|
fn[T] Css::fail(self : Css, what : String) -> T {
  abort("css: \{what} at \{self.i} in \"\{self.s}\"")
}

///|
/// The character it is at; NUL past the end.
fn Css::peek(self : Css) -> Char {
  if self.i < self.s.length() {
    self.s.code_unit_at(self.i).to_int().unsafe_to_char()
  } else {
    '\u{0}'
  }
}

///|
fn Css::space(self : Css) -> Unit {
  while self.i < self.s.length() {
    match self.peek() {
      ' ' | '\n' | '\t' => self.i += 1
      _ => break
    }
  }
}

///|
/// A name: a property's, a token's, a block's.
fn Css::name(self : Css) -> StringView {
  self.space()
  let a = self.i
  while self.i < self.s.length() {
    match self.peek() {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '_' => self.i += 1
      _ => break
    }
  }
  if self.i == a {
    self.fail("a name wanted")
  }
  self.s.view(start_offset=a, end_offset=self.i)
}

///|
fn Css::expect(self : Css, c : Char) -> Unit {
  self.space()
  if self.peek() != c {
    self.fail("\{c} wanted")
  }
  self.i += 1
}

///|
/// 10^e, for e of 0 … 22: the powers of ten a Double holds exactly.
fn css_pow10(e : Int) -> Double {
  match e {
    0 => 1.0e0
    1 => 1.0e1
    2 => 1.0e2
    3 => 1.0e3
    4 => 1.0e4
    5 => 1.0e5
    6 => 1.0e6
    7 => 1.0e7
    8 => 1.0e8
    9 => 1.0e9
    10 => 1.0e10
    11 => 1.0e11
    12 => 1.0e12
    13 => 1.0e13
    14 => 1.0e14
    15 => 1.0e15
    16 => 1.0e16
    17 => 1.0e17
    18 => 1.0e18
    19 => 1.0e19
    20 => 1.0e20
    21 => 1.0e21
    22 => 1.0e22
    _ => abort("css: 10^\{e} is not exact")
  }
}

///|
/// A number, as moonc reads its literal: its digits an integer m (`_` left out), its point and exponent a power of
/// ten e; with m at most 2^53 and e within ±22 both are Doubles exactly and m·10^e (or m/10^-e) is one rounding, the
/// nearest Double, which is what the literal is (Clinger's fast path). One past that aborts rather than be near.
fn Css::num(self : Css) -> Double {
  self.space()
  let neg = self.peek() == '-'
  if neg {
    self.i += 1
  }
  let most = 9007199254740992L // 2^53
  let mut m = 0L
  let mut e = 0
  let mut digits = false
  let mut point = false
  while self.i < self.s.length() {
    let c = self.peek()
    match c {
      '0'..='9' => {
        m = m * 10L + (c.to_int() - 48).to_int64()
        if m > most {
          self.fail("a number with more digits than read exactly")
        }
        if point {
          e -= 1
        }
        digits = true
      }
      '_' => ()
      '.' if !point => point = true
      _ => break
    }
    self.i += 1
  }
  if !digits {
    self.fail("a number wanted")
  }
  if self.peek() == 'e' || self.peek() == 'E' {
    self.i += 1
    let eneg = self.peek() == '-'
    if eneg || self.peek() == '+' {
      self.i += 1
    }
    let mut x = 0
    let a = self.i
    while self.peek() >= '0' && self.peek() <= '9' && x < 1000 {
      x = x * 10 + (self.peek().to_int() - 48)
      self.i += 1
    }
    if self.i == a {
      self.fail("an exponent wanted")
    }
    e += if eneg { -x } else { x }
  }
  let v = if e >= 0 && e <= 22 {
    m.to_double() * css_pow10(e)
  } else if e < 0 && e >= -22 {
    m.to_double() / css_pow10(-e)
  } else {
    self.fail("a number with a power of ten not read exactly")
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// An Int64: decimal or `0x` hex (a colour's rrggbbaa).
fn Css::int64(self : Css) -> Int64 {
  self.space()
  let neg = self.peek() == '-'
  if neg {
    self.i += 1
  }
  let hex = self.peek() == '0' &&
    self.i + 1 < self.s.length() &&
    (self.s.code_unit_at(self.i + 1).to_int() == 'x'.to_int() ||
    self.s.code_unit_at(self.i + 1).to_int() == 'X'.to_int())
  if hex {
    self.i += 2
  }
  let base = if hex { 16L } else { 10L }
  let mut m = 0L
  let mut digits = false
  while self.i < self.s.length() {
    let c = self.peek()
    let d = match c {
      '0'..='9' => c.to_int() - 48
      'a'..='f' if hex => c.to_int() - 87
      'A'..='F' if hex => c.to_int() - 55
      '_' => {
        self.i += 1
        continue
      }
      _ => break
    }
    if m > (9223372036854775807L - d.to_int64()) / base {
      self.fail("a number past an Int64")
    }
    m = m * base + d.to_int64()
    digits = true
    self.i += 1
  }
  if !digits {
    self.fail("a number wanted")
  }
  if neg {
    -m
  } else {
    m
  }
}

///|
/// `(v)`, a constructor's one Double.
fn Css::arg(self : Css) -> Double {
  self.expect('(')
  let v = self.num()
  self.expect(')')
  v
}

///|
fn Css::arg_int64(self : Css) -> Int64 {
  self.expect('(')
  let v = self.int64()
  self.expect(')')
  v
}

///|
fn Css::bool(self : Css) -> Bool {
  let n = self.name()
  match n {
    "true" => true
    "false" => false
    _ => self.fail("no Bool \{n}")
  }
}

///|
fn Css::len(self : Css) -> Len {
  let n = self.name()
  match n {
    "Hug" => Hug
    "Cut" => Cut
    "Full" => Full
    "Grow" => Grow(self.arg())
    "Fixed" => Fixed(self.arg())
    "Pct" => Pct(self.arg())
    "S0" => S0
    "SPx" => SPx
    "S0_5" => S0_5
    "S1" => S1
    "S1_25" => S1_25
    "S1_5" => S1_5
    "S2" => S2
    "S2_5" => S2_5
    "S3" => S3
    "S3_5" => S3_5
    "S4" => S4
    "S4_5" => S4_5
    "S5" => S5
    "S6" => S6
    "S7" => S7
    "S8" => S8
    "S9" => S9
    "S10" => S10
    "S11" => S11
    "S12" => S12
    "S14" => S14
    "S16" => S16
    "S20" => S20
    "S24" => S24
    "S28" => S28
    "S32" => S32
    "S36" => S36
    "S40" => S40
    "S44" => S44
    "S48" => S48
    "S52" => S52
    "S56" => S56
    "S60" => S60
    "S64" => S64
    "S72" => S72
    "S80" => S80
    "S96" => S96
    _ => self.fail("no Len \{n}")
  }
}

///|
fn Css::space_token(self : Css) -> Space {
  let n = self.name()
  match n {
    "S0" => S0
    "SPx" => SPx
    "S0_5" => S0_5
    "S1" => S1
    "S1_25" => S1_25
    "S1_5" => S1_5
    "S2" => S2
    "S2_5" => S2_5
    "S3" => S3
    "S3_5" => S3_5
    "S4" => S4
    "S4_5" => S4_5
    "S5" => S5
    "S6" => S6
    "S7" => S7
    "S8" => S8
    "S9" => S9
    "S10" => S10
    "S11" => S11
    "S12" => S12
    "S14" => S14
    "S16" => S16
    "S20" => S20
    "S24" => S24
    "S28" => S28
    "S32" => S32
    "S36" => S36
    "S40" => S40
    "S44" => S44
    "S48" => S48
    "S52" => S52
    "S56" => S56
    "S60" => S60
    "S64" => S64
    "S72" => S72
    "S80" => S80
    "S96" => S96
    // det-ok(style-exact, style-literal): what a style's text says, counted at the text (detlint's css)
    "Exact" => Exact(self.arg())
    _ => self.fail("no Space \{n}")
  }
}

///|
fn Css::align(self : Css) -> Align {
  let n = self.name()
  match n {
    "AStart" => AStart
    "ACenter" => ACenter
    "AEnd" => AEnd
    "AStretch" => AStretch
    _ => self.fail("no Align \{n}")
  }
}

///|
fn Css::justify(self : Css) -> Justify {
  let n = self.name()
  match n {
    "JStart" => JStart
    "JCenter" => JCenter
    "JEnd" => JEnd
    "JBetween" => JBetween
    _ => self.fail("no Justify \{n}")
  }
}

///|
fn Css::radius(self : Css) -> Radius {
  let n = self.name()
  match n {
    "Sharp" => Sharp
    "Sm" => Sm
    "Base" => Base
    "Md" => Md
    "Lg" => Lg
    "Xl" => Xl
    "Xl1_5" => Xl1_5
    "Xl2" => Xl2
    "Xl3" => Xl3
    "Xl4" => Xl4
    "Full" => Full
    "Inner" => Inner
    "InnerOr" => {
      self.expect('(')
      let own = self.radius()
      self.expect(')')
      InnerOr(own)
    }
    "Around" => Around
    // det-ok(style-exact, style-literal): what a style's text says, counted at the text (detlint's css)
    "Exact" => Exact(self.arg())
    _ => self.fail("no Radius \{n}")
  }
}

///|
fn Css::stroke(self : Css) -> Stroke {
  let n = self.name()
  match n {
    "B0" => B0
    "B0_5" => B0_5
    "B1" => B1
    "B1_5" => B1_5
    "B2" => B2
    "B4" => B4
    "B8" => B8
    _ => self.fail("no Stroke \{n}")
  }
}

///|
fn Css::shadow(self : Css) -> Shadow {
  let n = self.name()
  match n {
    "NoShadow" => NoShadow
    "Sm" => Sm
    "Base" => Base
    "Md" => Md
    "Lg" => Lg
    "Xl" => Xl
    "Cast" => {
      self.expect('(')
      let blur = self.num()
      self.expect(',')
      let y = self.num()
      self.expect(',')
      let c = self.int64()
      self.expect(')')
      Cast(blur, y, c)
    }
    _ => self.fail("no Shadow \{n}")
  }
}

///|
fn Css::opacity(self : Css) -> Opacity {
  let n = self.name()
  match n {
    "O0" => O0
    "O5" => O5
    "O10" => O10
    "O15" => O15
    "O20" => O20
    "O25" => O25
    "O30" => O30
    "O35" => O35
    "O40" => O40
    "O45" => O45
    "O50" => O50
    "O55" => O55
    "O60" => O60
    "O65" => O65
    "O70" => O70
    "O75" => O75
    "O80" => O80
    "O85" => O85
    "O90" => O90
    "O95" => O95
    "O100" => O100
    // det-ok(style-exact, style-literal): what a style's text says, counted at the text (detlint's css)
    "Exact" => Exact(self.arg())
    _ => self.fail("no Opacity \{n}")
  }
}

///|
fn Css::color(self : Css) -> Color {
  let n = self.name()
  match n {
    "Clear" => Clear
    "Bg" => Bg
    "Surface" => Surface
    "Raised" => Raised
    "Card" => Card
    "Fg" => Fg
    "Muted" => Muted
    "Subtle" => Subtle
    "Faint" => Faint
    "Line" => Line
    "Border" => Border
    "Accent" => Accent
    "AccentText" => AccentText
    "AccentBg" => AccentBg
    "OnAccent" => OnAccent
    "Primary" => Primary
    "OnPrimary" => OnPrimary
    "Positive" => Positive
    "Danger" => Danger
    "DangerBg" => DangerBg
    "OnDanger" => OnDanger
    "Neutral" => Neutral
    "Hover" => Hover
    "Selected" => Selected
    "Focus" => Focus
    "Scrim" => Scrim
    "Link" => Link
    "ShadowC" => ShadowC
    "Warn" => Warn
    "Tint" => Tint
    "TintStrong" => TintStrong
    "Floating" => Floating
    "Veil" => Veil
    "VeilDeep" => VeilDeep
    "OnVeil" => OnVeil
    "Theater" => Theater
    "Lifted" => Lifted
    "Wash" => Wash
    "Sidebar" => Sidebar
    "ListGround" => ListGround
    "FieldHover" => FieldHover
    "A" => {
      self.expect('(')
      let c = self.color()
      self.expect(',')
      let o = self.opacity()
      self.expect(')')
      A(c, o)
    }
    "Over" => {
      self.expect('(')
      let a = self.color()
      self.expect(',')
      let b = self.color()
      self.expect(')')
      Over(a, b)
    }
    // det-ok(style-exact, style-literal): what a style's text says, counted at the text (detlint's css)
    "Exact" => Exact(self.arg_int64())
    "Data" => Data(self.arg_int64())
    _ => self.fail("no Color \{n}")
  }
}

///|
/// The items up to the end (`states` given: the top, where the state blocks are) or up to a block's `}`.
fn Css::patch(self : Css, states : CssStates?) -> Patch {
  let mut row : Bool? = None
  let mut w : Len? = None
  let mut h : Len? = None
  let mut min_w : Len? = None
  let mut max_w : Len? = None
  let mut min_h : Len? = None
  let mut max_h : Len? = None
  let mut p : Space? = None
  let mut px : Space? = None
  let mut py : Space? = None
  let mut pl : Space? = None
  let mut pr : Space? = None
  let mut pt : Space? = None
  let mut pb : Space? = None
  let mut m : Space? = None
  let mut mx : Space? = None
  let mut my : Space? = None
  let mut ml : Space? = None
  let mut mr : Space? = None
  let mut mt : Space? = None
  let mut mb : Space? = None
  let mut gap : Space? = None
  let mut align : Align? = None
  let mut justify : Justify? = None
  let mut bg : Color? = None
  let mut radius : Radius? = None
  let mut border : Stroke? = None
  let mut border_color : Color? = None
  let mut dashed : Bool? = None
  let mut shadow : Shadow? = None
  let mut clip : Bool? = None
  let mut opacity : Opacity? = None
  while true {
    self.space()
    if self.i >= self.s.length() {
      if states is None {
        self.fail("a block not closed")
      }
      break
    }
    if self.peek() == '}' {
      if states is Some(_) {
        self.fail("a } closing no block")
      }
      self.i += 1
      break
    }
    let key = self.name()
    match self.peek() {
      '{' => {
        self.i += 1
        guard states is Some(st) else { self.fail("a block in a block") }
        let b = Some(self.patch(None))
        match key {
          "narrow" => st.narrow = b
          "dark" => st.dark = b
          "selected" => st.selected = b
          "hovered" => st.hovered = b
          "focused" => st.focused = b
          "pressed" => st.pressed = b
          "disabled" => st.disabled = b
          _ => self.fail("no state \{key}")
        }
      }
      '=' => {
        self.i += 1
        match key {
          "row" => row = Some(self.bool())
          "w" => w = Some(self.len())
          "h" => h = Some(self.len())
          "min_w" => min_w = Some(self.len())
          "max_w" => max_w = Some(self.len())
          "min_h" => min_h = Some(self.len())
          "max_h" => max_h = Some(self.len())
          "p" => p = Some(self.space_token())
          "px" => px = Some(self.space_token())
          "py" => py = Some(self.space_token())
          "pl" => pl = Some(self.space_token())
          "pr" => pr = Some(self.space_token())
          "pt" => pt = Some(self.space_token())
          "pb" => pb = Some(self.space_token())
          "m" => m = Some(self.space_token())
          "mx" => mx = Some(self.space_token())
          "my" => my = Some(self.space_token())
          "ml" => ml = Some(self.space_token())
          "mr" => mr = Some(self.space_token())
          "mt" => mt = Some(self.space_token())
          "mb" => mb = Some(self.space_token())
          "gap" => gap = Some(self.space_token())
          "align" => align = Some(self.align())
          "justify" => justify = Some(self.justify())
          "bg" => bg = Some(self.color())
          "radius" => radius = Some(self.radius())
          "border" => border = Some(self.stroke())
          "border_color" => border_color = Some(self.color())
          "dashed" => dashed = Some(self.bool())
          "shadow" => shadow = Some(self.shadow())
          "clip" => clip = Some(self.bool())
          "opacity" => opacity = Some(self.opacity())
          _ => self.fail("no property \{key}")
        }
      }
      _ =>
        match key {
          "row" => row = Some(true)
          "clip" => clip = Some(true)
          "dashed" => dashed = Some(true)
          _ => self.fail("\{key} with no value")
        }
    }
    // an item ends at a space, a block's end or the text's
    match self.peek() {
      ' ' | '\n' | '\t' | '}' => ()
      _ if self.i >= self.s.length() => ()
      _ => self.fail("an item not ended by a space")
    }
  }
  {
    row,
    w,
    h,
    min_w,
    max_w,
    min_h,
    max_h,
    p,
    px,
    py,
    pl,
    pr,
    pt,
    pb,
    m,
    mx,
    my,
    ml,
    mr,
    mt,
    mb,
    gap,
    align,
    justify,
    bg,
    radius,
    border,
    border_color,
    dashed,
    shadow,
    clip,
    opacity,
  }
}
