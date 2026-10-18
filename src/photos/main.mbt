// Photos over made-up days (src/gallery, as src/coredemo has it over the
// core): a few pictures over and over (macOS's desktop pictures natively,
// JPEGs made from them on the web), some of them videos, 60 days back from
// a fixed one.

///|
fn days_in(y : Int, m : Int) -> Int {
  match m {
    2 => if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn two(v : Int) -> String {
  if v < 10 {
    "0\{v}"
  } else {
    "\{v}"
  }
}

///|
let days : Array[@gallery.Day] = {
  let out = []
  let mut y = 2026
  let mut m = 10
  let mut d = 18
  let mut n = 0
  for k in 0..<60 {
    // some days have none
    if k % 5 != 3 {
      let items = []
      for j in 0..<(1 + (k * 7 + 3) % 11) {
        let video = n % 9 == 4
        let item : @gallery.Item = {
          id: "\{n}",
          video,
          time: "\{two(9 + j % 12)}:\{two((j * 13 + k) % 60)}",
          // the pictures' own sizes: not known here
          w: 0.0,
          h: 0.0,
          thumbhash: "",
          duration: if video { Some((17 + n * 7 % 300).to_double()) } else { None },
        }
        items.push(item)
        n = n + 1
      }
      let day : @gallery.Day = { day: "\{y}-\{two(m)}-\{two(d)}", items }
      out.push(day)
    }
    d = d - 1
    if d == 0 {
      m = m - 1
      if m == 0 {
        m = 12
        y = y - 1
      }
      d = days_in(y, m)
    }
  }
  out
}

///|
fn picture_of(it : @gallery.Item) -> String {
  let mut n = 0
  for ch in it.id {
    n = n * 10 + (ch.to_int() - 48)
  }
  picture(n)
}

///|
let source : @gallery.Source = {
  days: fn() { Some(Ok(days)) },
  thumb: picture_of,
  large: picture_of,
  older: fn() {  },
}

///|
fn main {
  @ui.run("照片", fn(c) { @gallery.view(c, source) })
}
