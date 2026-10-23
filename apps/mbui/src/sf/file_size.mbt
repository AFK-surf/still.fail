// A file's size as people read it (web/ui fileSize.ts): 512 B, 38 KB, 4.2 MB, 1.25 GB.

///|
/// `bytes` in words: whole bytes under a KB, whole KB under a MB, a MB to one place, a GB to two (fileSize).
pub fn file_size(bytes : Double) -> String {
  let kb = 1024.0
  if bytes < kb {
    "\{bytes.to_int()} B"
  } else if bytes < kb * kb {
    "\{(bytes / kb).round().to_int()} KB"
  } else if bytes < kb * kb * kb {
    to_fixed(bytes / kb / kb, 1) + " MB"
  } else {
    to_fixed(bytes / kb / kb / kb, 2) + " GB"
  }
}

///|
/// `x` (not below 0) to one or two places, as JavaScript's `toFixed` writes it (4.0 is "4.0").
pub fn to_fixed(x : Double, places : Int) -> String {
  let scale = if places == 2 { 100.0 } else { 10.0 }
  let n = (x * scale).round().to_int()
  let whole = n / scale.to_int()
  let part = n % scale.to_int()
  let digits = if places == 2 && part < 10 { "0\{part}" } else { "\{part}" }
  "\{whole}.\{digits}"
}
