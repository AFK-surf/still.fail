// svgtypes' filter value lists (filter_functions.rs): the CSS filter functions and url()s of a `filter`.

///|
priv enum FilterValue {
  FvBlur(Length)
  FvDropShadow(SColor?, Length, Length, Length)
  FvBrightness(Double)
  FvContrast(Double)
  FvGrayscale(Double)
  /// in degrees
  FvHueRotate(Double)
  FvInvert(Double)
  FvOpacity(Double)
  FvSepia(Double)
  FvSaturate(Double)
  FvUrl(String)
}

///|
/// A filter's list; None at its first error (FilterValueListParser yields it and stops).
fn parse_filter_values(text : String) -> Array[FilterValue?] {
  let s = Stream::new(text)
  let out : Array[FilterValue?] = []
  while true {
    s.skip_spaces()
    if s.at_end() {
      break
    }
    if s.starts_with("none") {
      s.pos += 4
      s.skip_spaces()
      if !s.at_end() {
        out.push(None)
      }
      break
    }
    let v = parse_filter_next(s)
    out.push(v)
    if v is None {
      break
    }
  }
  out
}

///|
fn is_sign_negative(x : Double) -> Bool {
  x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
}

///|
fn parse_filter_next(s : Stream) -> FilterValue? {
  let name = s.consume_ascii_ident()
  s.skip_spaces()
  if !s.consume_byte(0x28) {
    return None
  }
  s.skip_spaces()
  let value = match name {
    "blur" =>
      if s.is_curr(0x29) {
        FvBlur(Length::zero())
      } else {
        match parse_filter_positive_length(s) {
          Some(v) => FvBlur(v)
          None => return None
        }
      }
    "drop-shadow" =>
      match parse_drop_shadow_func(s) {
        Some(v) => v
        None => return None
      }
    "hue-rotate" =>
      if s.is_curr(0x29) {
        FvHueRotate(0.0)
      } else {
        match parse_filter_angle(s) {
          Some(v) => FvHueRotate(v)
          None => return None
        }
      }
    "brightness" | "contrast" | "grayscale" | "invert" | "opacity" | "saturate" | "sepia" => {
      let v = match parse_generic_color_func(s) {
        Some(v) => v
        None => return None
      }
      match name {
        "brightness" => FvBrightness(v)
        "contrast" => FvContrast(v)
        "grayscale" => FvGrayscale(v)
        "invert" => FvInvert(v)
        "opacity" => FvOpacity(v)
        "saturate" => FvSaturate(v)
        _ => FvSepia(v)
      }
    }
    "url" => {
      if !s.consume_byte(0x23) {
        return None
      }
      let link = s.consume_bytes(fn(c) { c != 0x20 && c != 0x29 })
      if link == "" {
        return None
      }
      FvUrl(link)
    }
    _ => return None
  }
  s.skip_spaces()
  if !s.consume_byte(0x29) {
    return None
  }
  s.skip_spaces()
  Some(value)
}

///|
fn parse_drop_shadow_func(s : Stream) -> FilterValue? {
  if s.is_curr(0x29) {
    return None
  }
  let mut color : SColor? = None
  let mut is_current_color = false
  match s.try_parse_color() {
    Some(c) => {
      color = Some(c)
      s.skip_spaces()
    }
    None =>
      if s.starts_with("currentColor") {
        is_current_color = true
        s.pos += 12
        s.skip_spaces()
      }
  }
  let dx = match parse_filter_length(s) {
    Some(v) => v
    None => return None
  }
  s.skip_spaces()
  let dy = match parse_filter_length(s) {
    Some(v) => v
    None => return None
  }
  s.skip_spaces()
  let mut std_dev = Length::zero()
  match parse_filter_positive_length(s) {
    Some(v) => {
      std_dev = v
      s.skip_spaces()
    }
    None => ()
  }
  if color is None && !is_current_color {
    match s.try_parse_color() {
      Some(c) => {
        color = Some(c)
        s.skip_spaces()
      }
      None => if s.starts_with("currentColor") { s.pos += 12 }
    }
  }
  Some(FvDropShadow(color, dx, dy, std_dev))
}

///|
fn parse_generic_color_func(s : Stream) -> Double? {
  if s.is_curr(0x29) {
    Some(1.0)
  } else {
    match s.parse_number_or_percent() {
      Some(v) => if is_sign_negative(v) { None } else { Some(v) }
      None => None
    }
  }
}

///|
fn parse_filter_length(s : Stream) -> Length? {
  match s.parse_length() {
    Some(v) => if v.unit == Percent { None } else { Some(v) }
    None => None
  }
}

///|
fn parse_filter_positive_length(s : Stream) -> Length? {
  match s.parse_length() {
    Some(v) => if is_sign_negative(v.number) || v.unit == Percent { None } else { Some(v) }
    None => None
  }
}

///|
/// A filter's angle in degrees: a bare number only where it is 0.
fn parse_filter_angle(s : Stream) -> Double? {
  s.skip_spaces()
  let n = match s.parse_number() {
    Some(n) => n
    None => return None
  }
  if s.starts_with("deg") {
    s.pos += 3
    Some(n)
  } else if s.starts_with("grad") {
    s.pos += 4
    Some(n * 180.0 / 200.0)
  } else if s.starts_with("rad") {
    s.pos += 3
    Some(n * (180.0 / 3.141592653589793))
  } else if s.starts_with("turn") {
    s.pos += 4
    Some(n * 360.0)
  } else if n == 0.0 {
    Some(n)
  } else {
    None
  }
}
