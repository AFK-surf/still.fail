// Command lines: shlex.split, shlex.quote, subprocess.list2cmdline; JSON strings

///|
/// shlex.split(s, posix=…): words split at whitespace, quoted parts kept together (posix: the quotes and the
/// backslashes taken out; not: quotes kept, a backslash a character)
fn split_words(s : Bytes, posix? : Bool = !windows) -> Array[Bytes] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    while i < n && is_space(s[i]) {
      i += 1
    }
    if i >= n {
      break
    }
    let w = @buffer.new()
    let mut any = false
    while i < n && !is_space(s[i]) {
      let c = s[i]
      if c == b'\'' || c == b'"' {
        any = true
        if !posix {
          w.write_byte(c)
        }
        i += 1
        while i < n && s[i] != c {
          if posix && c == b'"' && s[i] == b'\\' && i + 1 < n &&
            (s[i + 1] == b'\\' || s[i + 1] == b'"' || s[i + 1] == b'$' || s[i + 1] == b'`' || s[i + 1] == b'\n') {
            w.write_byte(s[i + 1])
            i += 2
            continue
          }
          w.write_byte(s[i])
          i += 1
        }
        if i < n {
          if !posix {
            w.write_byte(c)
          }
          i += 1
        }
      } else if posix && c == b'\\' && i + 1 < n {
        w.write_byte(s[i + 1])
        any = true
        i += 2
      } else {
        w.write_byte(c)
        any = true
        i += 1
      }
    }
    if any {
      out.push(w.to_bytes())
    }
  }
  out
}

///|
fn split_words_s(s : String) -> Array[Bytes] {
  split_words(utf8(s))
}

///|
/// shlex.quote
fn quote(s : Bytes) -> Bytes {
  if s.length() == 0 {
    return b"''"
  }
  let safe = s.iter().all(fn(c) {
    is_ident(c) && c != b'$' ||
    c == b'@' ||
    c == b'%' ||
    c == b'+' ||
    c == b'=' ||
    c == b':' ||
    c == b',' ||
    c == b'.' ||
    c == b'/' ||
    c == b'-'
  })
  if safe {
    s
  } else {
    cat([b"'", replace_all(s, b"'", b"'\"'\"'"), b"'"])
  }
}

///|
fn quote_all(ws : Array[Bytes]) -> Bytes {
  let buf = @buffer.new()
  for i, w in ws {
    if i > 0 {
      buf.write_byte(b' ')
    }
    buf.write_bytes(quote(w))
  }
  buf.to_bytes()
}

///|
/// subprocess.list2cmdline: a Windows command line the C runtime splits back into these words
fn list2cmdline(ws : Array[Bytes]) -> Bytes {
  let buf = @buffer.new()
  for k, w in ws {
    if k > 0 {
      buf.write_byte(b' ')
    }
    let needq = w.length() == 0 || w.iter().any(fn(c) { c == b' ' || c == b'\t' })
    if needq {
      buf.write_byte(b'"')
    }
    let mut bs = 0
    for c in w {
      if c == b'\\' {
        bs += 1
      } else if c == b'"' {
        for _ in 0..<(bs * 2 + 1) {
          buf.write_byte(b'\\')
        }
        bs = 0
        buf.write_byte(b'"')
      } else {
        for _ in 0..<bs {
          buf.write_byte(b'\\')
        }
        bs = 0
        buf.write_byte(c)
      }
    }
    if needq {
      for _ in 0..<(bs * 2) {
        buf.write_byte(b'\\')
      }
      buf.write_byte(b'"')
    } else {
      for _ in 0..<bs {
        buf.write_byte(b'\\')
      }
    }
  }
  buf.to_bytes()
}

///|
/// json.dumps of a string (ensure_ascii: what is past ASCII as \u escapes)
fn json_dumps(s : Bytes) -> Bytes {
  let buf = @buffer.new()
  let hex = b"0123456789abcdef"
  let u = fn(cp : Int) {
    buf.write_bytes(b"\\u")
    for k in 0..<4 {
      buf.write_byte(hex[(cp >> (12 - 4 * k)) & 15])
    }
  }
  buf.write_byte(b'"')
  let st = str(s)
  for ch in st {
    let c = ch.to_int()
    if c == 0x22 {
      buf.write_bytes(b"\\\"")
    } else if c == 0x5C {
      buf.write_bytes(b"\\\\")
    } else if c == 0x0A {
      buf.write_bytes(b"\\n")
    } else if c == 0x0D {
      buf.write_bytes(b"\\r")
    } else if c == 0x09 {
      buf.write_bytes(b"\\t")
    } else if c == 0x08 {
      buf.write_bytes(b"\\b")
    } else if c == 0x0C {
      buf.write_bytes(b"\\f")
    } else if c < 0x20 {
      u(c)
    } else if c < 0x80 {
      buf.write_byte(c.to_byte())
    } else if c < 0x10000 {
      u(c)
    } else {
      let v = c - 0x10000
      u(0xD800 + (v >> 10))
      u(0xDC00 + (v & 0x3FF))
    }
  }
  buf.write_byte(b'"')
  buf.to_bytes()
}
