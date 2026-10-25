// A QR code the core made (qr.ts: its dark modules row by row, `1` dark), drawn as the web's QrCode.tsx draws it: on
// white whatever the theme, four modules of quiet zone round it, whole pixels a module. A Feishu bot made by scanning
// (the phone's and the desktop's new connect) shows it.

///|
/// `code` (the core's: `size` modules a side, `rows` of them) `size` across, its corner the field's, named `label` for
/// a screen reader.
pub fn qr_code(c : @ui.Ctx, code : Json?, size : Double, label : String) -> Unit {
  let (n0, rows) = match code {
    Some(Object(m)) =>
      (
        match m.get("size") {
          Some(Number(v, ..)) => v.to_int()
          _ => 0
        },
        match m.get("rows") {
          Some(Array(a)) =>
            a.filter_map(fn(r) {
              match r {
                String(s) => Some(s)
                _ => None
              }
            })
          _ => []
        },
      )
    _ => (0, [])
  }
  let n = n0 + qr_quiet * 2
  let cell = (size / n.to_double()).floor()
  let start = (size - cell * n.to_double()) / 2.0 + cell * qr_quiet.to_double()
  let b = c.box(style=qr_box.then(@ui.style(w=Fixed(size), h=Fixed(size), bg=Data(qr_white))), label~, fn() {
    for y, row in rows {
      // each row's dark runs, laid over the white
      let mut x = 0
      while x < row.length() {
        if row.unsafe_get(x).to_int() != 49 {
          x += 1
          continue
        }
        let mut end = x
        while end + 1 < row.length() && row.unsafe_get(end + 1).to_int() == 49 {
          end += 1
        }
        let (rx, ry, rw) = (start + x.to_double() * cell, start + y.to_double() * cell, (end - x + 1).to_double() * cell)
        c.layer(fn() {
          c.box(style=@ui.style(w=Fixed(rw), h=Fixed(cell), bg=Data(qr_black)), tx=rx, ty=ry, fn() {  }) |> ignore
        })
        |> ignore
        x = end + 1
      }
    }
  })
  // (a picture of the code, its colours its own whatever the theme: a screen reader's image, as no mark of the page)
  c.semantics(b, Image, label~)
}

///|
let qr_quiet : Int = 4

///|
let qr_white : Int64 = 0xFFFFFFFFL

///|
let qr_black : Int64 = 0x000000FFL

///|
// kept across runs: a value (no field of it changes)
let qr_box : @ui.Style = @ui.css("radius=Xl clip")
