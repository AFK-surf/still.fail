// A folder's names as a viewer reads them (web/ui viewer/names.ts): in their numbers' order (the playlist), and the
// subtitle beside a video. Plain functions over names (zdrive's Playlist.kt and SideSubtitles.kt, as Android had them).

///|
/// The playable names of a folder in the order a person would watch them: numbers as numbers (E2 before E10).
pub fn playlist_of(names : Array[String], playable : (String) -> Bool) -> Array[String] {
  let out : Array[String] = []
  for n in names {
    if playable(n) && !out.contains(n) {
      out.push(n)
    }
  }
  // an insertion sort: stable, and folders are short
  for i in 1..<out.length() {
    let x = out[i]
    let mut j = i - 1
    while j >= 0 && compare_natural(out[j], x) > 0 {
      out[j + 1] = out[j]
      j -= 1
    }
    out[j + 1] = x
  }
  out
}

///|
/// What follows `current` in `list`, or None at its end; one missing from the list still has a place by its name.
pub fn next_in(current : String, list : Array[String]) -> String? {
  match list.search(current) {
    Some(at) => list.get(at + 1)
    None => list.iter().find_first(fn(n) { compare_natural(n, current) > 0 })
  }
}

///|
/// What comes before `current` in `list`, or None at its start (or when it is not in it).
pub fn prev_in(current : String, list : Array[String]) -> String? {
  match list.search(current) {
    Some(at) if at > 0 => list.get(at - 1)
    _ => None
  }
}

///|
/// Names with their numbers compared as numbers: `E2` before `E10`.
pub fn compare_natural(a : String, b : String) -> Int {
  let x = a.to_array()
  let y = b.to_array()
  let mut i = 0
  let mut j = 0
  while i < x.length() && j < y.length() {
    let ca = x[i]
    let cb = y[j]
    if ca.is_ascii_digit() && cb.is_ascii_digit() {
      let sa = i
      let sb = j
      while i < x.length() && x[i].is_ascii_digit() {
        i += 1
      }
      while j < y.length() && y[j].is_ascii_digit() {
        j += 1
      }
      let na = digits(x, sa, i)
      let nb = digits(y, sb, j)
      if na.length() != nb.length() {
        return na.length() - nb.length()
      }
      let d = na.lexical_compare(nb)
      if d != 0 {
        return d
      }
    } else {
      let d = ca.to_ascii_lowercase().compare(cb.to_ascii_lowercase())
      if d != 0 {
        return d
      }
      i += 1
      j += 1
    }
  }
  let rest = (x.length() - i) - (y.length() - j)
  if rest != 0 {
    rest
  } else {
    a.lexical_compare(b)
  }
}

///|
/// The digits from `from` to `to`, their leading zeros gone.
fn digits(s : Array[Char], from : Int, to : Int) -> String {
  let mut k = from
  while k < to && s[k] == '0' {
    k += 1
  }
  String::from_array(s[k:to])
}

///|
/// Best first: `.srt` is what such files usually come with.
let subtitle_extensions : Array[String] = ["srt", "vtt", "ass", "ssa"]

///|
/// A name's extension, lower case ("" when it has none).
pub fn extension_of(name : String) -> String {
  match name.rev_find(".") {
    Some(i) => name.view(start_offset=i + 1).to_owned().to_lower()
    None => ""
  }
}

///|
/// Whether `name` is a subtitle this player reads (SubRip, WebVTT, ASS/SSA).
pub fn is_subtitle(name : String) -> Bool {
  subtitle_extensions.contains(extension_of(name))
}

///|
/// The subtitle beside the video `base`, out of the names in its folder (sideSubtitle): `<base>.<ext>` or `<stem>.<ext>` (E01.srt for E01.mp4)
/// first, then one with a tag between (`E01.zh.srt`), the whole name winning a tie.
pub fn side_subtitle(base : String, names : Array[String]) -> String? {
  let stem = match base.rev_find(".") {
    Some(i) => base.view(end_offset=i).to_owned()
    None => base
  }
  let stems = if stem == base { [base] } else { [base, stem] }
  let mut best : (String, Bool, Bool, Int, String)? = None
  for name in names {
    let lower = name.to_lower()
    let mut found = ""
    let mut has = false
    for s in stems {
      if !has && lower.has_prefix(s.to_lower() + ".") {
        found = s
        has = true
      }
    }
    if !has {
      continue
    }
    let ext = extension_of(name)
    let rank = match subtitle_extensions.search(ext) {
      Some(r) => r
      None => continue
    }
    let tag = name.view(start_offset=found.length()).to_owned()
    let exact = tag.length() == ext.length() + 1
    let full = found == base
    let better = match best {
      None => true
      Some((_, e, f, r, t)) =>
        if exact != e {
          exact
        } else if full != f {
          full
        } else if rank != r {
          rank < r
        } else {
          tag.lexical_compare(t) < 0
        }
    }
    if better {
      best = Some((name, exact, full, rank, tag))
    }
  }
  match best {
    Some((n, _, _, _, _)) => Some(n)
    None => None
  }
}
