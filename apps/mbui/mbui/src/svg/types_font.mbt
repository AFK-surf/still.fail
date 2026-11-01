// svgtypes' font families and the `font` shorthand (font.rs).

///|
pub(all) enum FontFamily {
  FSerif
  FSansSerif
  FCursive
  FFantasy
  FMonospace
  FNamed(String)
} derive(Eq, Show, Debug)

///|
fn Stream::parse_font_families(self : Stream) -> Array[FontFamily]? {
  let families : Array[FontFamily] = []
  while !self.at_end() {
    self.skip_spaces()
    if self.at_end() {
      return None
    }
    let ch = self.cur()
    let family = if ch == 0x27 || ch == 0x22 {
      match self.parse_quoted_string() {
        Some(r) => FNamed(r)
        None => return None
      }
    } else {
      let idents : Array[String] = []
      while !self.at_end() && self.cur() != 0x2C {
        match self.parse_ident() {
          Some(i) => idents.push(i)
          None => return None
        }
        self.skip_spaces()
      }
      let joined = idents.join(" ")
      match joined {
        "serif" => FSerif
        "sans-serif" => FSansSerif
        "cursive" => FCursive
        "fantasy" => FFantasy
        "monospace" => FMonospace
        _ => FNamed(joined)
      }
    }
    families.push(family)
    if !self.at_end() {
      if self.cur() == 0x2C {
        self.pos += 1
      } else {
        break
      }
    }
  }
  Some(
    families.filter(fn(f) {
      match f {
        FNamed(s) => s != ""
        _ => true
      }
    }),
  )
}

///|
fn parse_font_families(text : String) -> Array[FontFamily]? {
  let s = Stream::new(text)
  let r = s.parse_font_families()
  s.skip_spaces()
  if !s.at_end() {
    return None
  }
  r
}

///|
priv struct FontShorthand {
  font_style : String?
  font_variant : String?
  font_weight : String?
  font_stretch : String?
  font_size : String
  font_family : String
}

///|
fn parse_font_shorthand(text : String) -> FontShorthand? {
  let s = Stream::new(text)
  s.skip_spaces()
  let mut prev_pos = s.pos
  let mut font_style : String? = None
  let mut font_variant : String? = None
  let mut font_weight : String? = None
  let mut font_stretch : String? = None
  for _ in 0..<4 {
    let ident = s.consume_ascii_ident()
    let mut stop = false
    match ident {
      "normal" => ()
      "small-caps" => font_variant = Some(ident)
      "italic" | "oblique" => font_style = Some(ident)
      "bold" | "bolder" | "lighter" | "100" | "200" | "300" | "400" | "500" | "600" | "700" | "800" | "900" =>
        font_weight = Some(ident)
      "ultra-condensed" | "extra-condensed" | "condensed" | "semi-condensed" | "semi-expanded" | "expanded"
      | "extra-expanded" | "ultra-expanded" => font_stretch = Some(ident)
      _ => {
        s.pos = prev_pos
        stop = true
      }
    }
    if stop {
      break
    }
    s.skip_spaces()
    prev_pos = s.pos
  }
  prev_pos = s.pos
  if s.at_end() {
    return None
  }
  if is_digit_b(s.cur()) {
    if s.parse_length() is None {
      return None
    }
  } else {
    match s.consume_ascii_ident() {
      "xx-small" | "x-small" | "small" | "medium" | "large" | "x-large" | "xx-large" | "larger" | "smaller" => ()
      _ => return None
    }
  }
  let font_size = s.slice_back(prev_pos)
  s.skip_spaces()
  if s.at_end() {
    return None
  }
  if s.cur() == 0x2F {
    s.pos += 1
    s.skip_spaces()
    if s.parse_length() is None {
      return None
    }
    s.skip_spaces()
  }
  if s.at_end() {
    return None
  }
  Some({ font_style, font_variant, font_weight, font_stretch, font_size, font_family: s.slice_tail() })
}
