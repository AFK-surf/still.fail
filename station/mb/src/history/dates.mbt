///|
/// Date.parse of a timestamp as transcripts write it (ECMAScript's date time string format: a date, a time, `Z` or an
/// offset), its milliseconds; none for anything else (V8 reads some other forms too: no transcript writes them).
/// A date and time without an offset is read as UTC (JavaScript reads it in the machine's zone: no transcript writes
/// one).
pub fn date_parse(s : String) -> Double? {
  let n = s.length()
  let mut i = 0
  let digits = (count : Int) => {
    if i + count > n {
      return None
    }
    let mut v = 0
    for k in 0..<count {
      let c = s.unsafe_charcode_at(i + k)
      if c < '0' || c > '9' {
        return None
      }
      v = v * 10 + (c - '0')
    }
    i += count
    Some(v)
  }
  let mut sign = 1
  let year = if i < n && (s.unsafe_charcode_at(i) == '+' || s.unsafe_charcode_at(i) == '-') {
    sign = if s.unsafe_charcode_at(i) == '-' { -1 } else { 1 }
    i += 1
    guard digits(6) is Some(y) else { return None }
    if sign == -1 && y == 0 {
      return None
    }
    sign * y
  } else {
    guard digits(4) is Some(y) else { return None }
    y
  }
  let mut month = 1
  let mut day = 1
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut ms = 0.0
  let mut offset = 0
  if i < n && s.unsafe_charcode_at(i) == '-' {
    i += 1
    guard digits(2) is Some(m) else { return None }
    month = m
    if i < n && s.unsafe_charcode_at(i) == '-' {
      i += 1
      guard digits(2) is Some(d) else { return None }
      day = d
    }
  }
  if i < n && (s.unsafe_charcode_at(i) == 'T' || s.unsafe_charcode_at(i) == 't') {
    i += 1
    guard digits(2) is Some(h) else { return None }
    guard i < n && s.unsafe_charcode_at(i) == ':' else { return None }
    i += 1
    guard digits(2) is Some(mi) else { return None }
    hour = h
    minute = mi
    if i < n && s.unsafe_charcode_at(i) == ':' {
      i += 1
      guard digits(2) is Some(sec) else { return None }
      second = sec
      if i < n && s.unsafe_charcode_at(i) == '.' {
        i += 1
        let start = i
        let mut frac = 0
        let mut count = 0
        while i < n && s.unsafe_charcode_at(i) >= '0' && s.unsafe_charcode_at(i) <= '9' {
          if count < 3 {
            frac = frac * 10 + (s.unsafe_charcode_at(i) - '0')
            count += 1
          }
          i += 1
        }
        if i == start {
          return None
        }
        while count < 3 {
          frac *= 10
          count += 1
        }
        ms = frac.to_double()
      }
    }
    if i < n && (s.unsafe_charcode_at(i) == 'Z' || s.unsafe_charcode_at(i) == 'z') {
      i += 1
    } else if i < n && (s.unsafe_charcode_at(i) == '+' || s.unsafe_charcode_at(i) == '-') {
      let sg = if s.unsafe_charcode_at(i) == '-' { -1 } else { 1 }
      i += 1
      guard digits(2) is Some(oh) else { return None }
      guard i < n && s.unsafe_charcode_at(i) == ':' else { return None }
      i += 1
      guard digits(2) is Some(om) else { return None }
      if oh > 23 || om > 59 {
        return None
      }
      offset = sg * (oh * 60 + om)
    }
  }
  if i != n {
    return None
  }
  let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let lengths = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  if month < 1 || month > 12 || day < 1 || day > lengths[month - 1] {
    return None
  }
  if minute > 59 || second > 59 || hour > 24 || (hour == 24 && (minute > 0 || second > 0 || ms > 0.0)) {
    return None
  }
  let (yy, mm) = if month <= 2 { (year - 1, month + 9) } else { (year, month - 3) }
  let era = if yy >= 0 { yy / 400 } else { (yy - 399) / 400 }
  let yoe = yy - era * 400
  let doy = (153 * mm + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era.to_double() * 146_097.0 + doe.to_double() - 719_468.0
  let t = (days * 86_400.0 + hour.to_double() * 3600.0 + minute.to_double() * 60.0 + second.to_double() - offset.to_double() * 60.0) *
    1000.0 +
    ms
  if t.abs() > 8.64e15 {
    None
  } else {
    Some(t)
  }
}
