// svgtypes' paints (paint.rs), paint order (paint_order.rs), transform origins (transform_origin.rs,
// directional_position.rs) and enable-background (enable_background.rs).

///|
priv enum PaintFallback {
  FbNone
  FbCurrentColor
  FbColor(SColor)
}

///|
priv enum SPaint {
  PaintNone
  PaintInherit
  PaintCurrentColor
  PaintColor(SColor)
  PaintFuncIRI(String, PaintFallback?)
  PaintContextFill
  PaintContextStroke
}

///|
fn parse_paint(text : String) -> SPaint? {
  let text = text.trim(chars=" \t\n\r").to_string()
  match text {
    "none" => Some(PaintNone)
    "inherit" => Some(PaintInherit)
    "currentColor" => Some(PaintCurrentColor)
    "context-fill" => Some(PaintContextFill)
    "context-stroke" => Some(PaintContextStroke)
    _ => {
      let s = Stream::new(text)
      if s.starts_with("url(") {
        match s.parse_func_iri() {
          Some(link) => {
            s.skip_spaces()
            if !s.at_end() {
              match s.slice_tail() {
                "none" => Some(PaintFuncIRI(link, Some(FbNone)))
                "currentColor" => Some(PaintFuncIRI(link, Some(FbCurrentColor)))
                fallback =>
                  match parse_color_str(fallback) {
                    Some(c) => Some(PaintFuncIRI(link, Some(FbColor(c))))
                    None => None
                  }
              }
            } else {
              Some(PaintFuncIRI(link, None))
            }
          }
          None => None
        }
      } else {
        match parse_color_str(text) {
          Some(c) => Some(PaintColor(c))
          None => None
        }
      }
    }
  }
}

///|
pub(all) enum PaintOrderKind {
  OFill
  OStroke
  OMarkers
} derive(Eq, Show, Debug)

///|
fn default_paint_order() -> Array[PaintOrderKind] {
  [OFill, OStroke, OMarkers]
}

///|
fn parse_paint_order(text : String) -> Array[PaintOrderKind] {
  let order = default_paint_order()
  let s = Stream::new(text)
  let mut count = 0
  while !s.at_end() && count < 3 {
    s.skip_spaces()
    let name = s.consume_ascii_ident()
    s.skip_spaces()
    let kind = match name {
      "fill" => OFill
      "stroke" => OStroke
      "markers" => OMarkers
      _ => return default_paint_order()
    }
    let mut index = -1
    for i in count..<3 {
      if order[i] == kind {
        index = i - count
        break
      }
    }
    if index < 0 {
      return default_paint_order()
    }
    // rotate order[count..=count+index] right by one
    let last = order[count + index]
    let mut k = count + index
    while k > count {
      order[k] = order[k - 1]
      k -= 1
    }
    order[count] = last
    count += 1
  }
  s.skip_spaces()
  if !s.at_end() {
    return default_paint_order()
  }
  order
}

///|
priv enum DirPos {
  DTop
  DCenter
  DBottom
  DRight
  DLeft
} derive(Eq)

///|
fn Stream::parse_directional_position(self : Stream) -> DirPos? {
  self.skip_spaces()
  if self.starts_with("left") {
    self.pos += 4
    Some(DLeft)
  } else if self.starts_with("right") {
    self.pos += 5
    Some(DRight)
  } else if self.starts_with("top") {
    self.pos += 3
    Some(DTop)
  } else if self.starts_with("bottom") {
    self.pos += 6
    Some(DBottom)
  } else if self.starts_with("center") {
    self.pos += 6
    Some(DCenter)
  } else {
    None
  }
}

///|
fn dir_length(d : DirPos) -> Length {
  match d {
    DLeft | DTop => { number: 0.0, unit: Percent }
    DRight | DBottom => { number: 100.0, unit: Percent }
    DCenter => { number: 50.0, unit: Percent }
  }
}

///|
priv enum OriginPos {
  OLength(Length)
  ODir(DirPos)
}

///|
fn OriginPos::is_vertical(self : OriginPos) -> Bool {
  match self {
    OLength(_) => true
    ODir(d) => d == DCenter || d == DTop || d == DBottom
  }
}

///|
fn OriginPos::is_horizontal(self : OriginPos) -> Bool {
  match self {
    OLength(_) => true
    ODir(d) => d == DCenter || d == DLeft || d == DRight
  }
}

///|
fn OriginPos::length(self : OriginPos) -> Length {
  match self {
    OLength(l) => l
    ODir(d) => dir_length(d)
  }
}

///|
/// A transform-origin's x and y (the z is not kept).
fn parse_transform_origin(text : String) -> (Length, Length)? {
  let s = Stream::new(text)
  s.skip_spaces()
  if s.at_end() {
    return None
  }
  let part = fn() -> OriginPos? {
    let save = s.pos
    match s.parse_directional_position() {
      Some(d) => Some(ODir(d))
      None => {
        s.pos = save
        match s.parse_length() {
          Some(l) => Some(OLength(l))
          None => None
        }
      }
    }
  }
  let p1 = match part() {
    Some(p) => p
    None => return None
  }
  let mut second : OriginPos? = None
  let mut third : Length? = None
  if !s.at_end() {
    s.skip_spaces()
    s.parse_list_separator()
    second = match part() {
      Some(p) => Some(p)
      None => return None
    }
  }
  if !s.at_end() {
    s.skip_spaces()
    s.parse_list_separator()
    third = match s.parse_length() {
      Some(l) => Some(l)
      None => return None
    }
  }
  s.skip_spaces()
  if !s.at_end() {
    return None
  }
  match second {
    None =>
      if p1.is_horizontal() {
        Some((p1.length(), dir_length(DCenter)))
      } else {
        Some((dir_length(DCenter), p1.length()))
      }
    Some(p2) => {
      match third {
        Some(l) => if l.unit == Percent { return None }
        None => ()
      }
      let check = fn(p : OriginPos) {
        match p {
          OLength(_) => true
          ODir(d) => d == DCenter
        }
      }
      if check(p1) && check(p2) {
        Some((p1.length(), p2.length()))
      } else if p1.is_horizontal() && p2.is_vertical() {
        Some((p1.length(), p2.length()))
      } else if p1.is_vertical() && p2.is_horizontal() {
        Some((p2.length(), p1.length()))
      } else {
        None
      }
    }
  }
}

///|
priv enum EnableBackground {
  Accumulate
  EbNew
  EbNewWithRegion(Double, Double, Double, Double)
}

///|
fn parse_enable_background(text : String) -> EnableBackground? {
  let s = Stream::new(text)
  s.skip_spaces()
  if s.starts_with("accumulate") {
    s.pos += 10
    s.skip_spaces()
    if !s.at_end() {
      return None
    }
    Some(Accumulate)
  } else if s.starts_with("new") {
    s.pos += 3
    s.skip_spaces()
    if s.at_end() {
      return Some(EbNew)
    }
    match (s.parse_list_number(), s.parse_list_number(), s.parse_list_number(), s.parse_list_number()) {
      (Some(x), Some(y), Some(w), Some(h)) => {
        s.skip_spaces()
        if !s.at_end() || !(w > 0.0 && h > 0.0) {
          return None
        }
        Some(EbNewWithRegion(x, y, w, h))
      }
      _ => None
    }
  } else {
    None
  }
}
