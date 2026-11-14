// What a test reads of a chat's picture flying into its viewer and back, the same on a page of either kind: on a chat's
// page made as nodes the window's tree flies it, by its thumbnail's id (@ui's Tester::flight_of: the thumbnail the end
// that stays, the viewer's picture the end that moves); on the old page the viewer flies it itself (Viewer::flies), and
// what is read of it is the picture drawn last over the page (zoom_flight_wbtest's zf_pic).

///|
/// Where the picture viewer `v` shows was drawn on its flight in the frame drawn last (x, y, w, h) and its corners
/// there (top left, then round it); none where it does not fly.
fn pic_flight(t : @ui.Tester, v : Viewer) -> ((Double, Double, Double, Double), (Double, Double, Double, Double))? {
  match t.flight_of(v.thumb_id()) {
    Some(f) => Some(f)
    None => if v.flies { zf_pic(t).map(fn(p) { (p.at, p.corners) }) } else { None }
  }
}

///|
/// Whether the picture viewer `v` shows flies now (into the viewer or back).
fn pic_flies(t : @ui.Tester, v : Viewer) -> Bool {
  t.flight_of(v.thumb_id()) is Some(_) || v.flies
}

///|
/// When the flight of the picture viewer `v` shows ends (the Tester's clock).
fn pic_flight_end(t : @ui.Tester, v : Viewer) -> Double {
  match t.flight_end(v.thumb_id()) {
    Some(e) => e
    None => v.fly.end()
  }
}

///|
/// The picture drawn last over (`x`, `y`) in the frame drawn last, 60 wide at least and seen (a thumbnail at rest):
/// where what is seen of it is (x, y, w, h: cut to what it is drawn in) and its corners as it is cut (top left, then
/// round it); none where none is.
fn pic_at(t : @ui.Tester, x : Double, y : Double) -> ((Double, Double, Double, Double), (Double, Double, Double, Double))? {
  let pics = t.drawn_images()
  let clips = t.drawn_image_clips()
  let mut out = None
  for k, p in pics {
    if p[2] > 60.0 && p[8] > 0.5 && p[0] <= x && x <= p[0] + p[2] && p[1] <= y && y <= p[1] + p[3] {
      // (what is seen of it: its picture cut to what it is drawn in, a thumbnail covering its box)
      let (l, t0, r, b) = if clips[k].0.2 > clips[k].0.0 { clips[k].0 } else { (p[0], p[1], p[0] + p[2], p[1] + p[3]) }
      let most = fn(a : Double, b : Double) { if a > b { a } else { b } }
      let least = fn(a : Double, b : Double) { if a < b { a } else { b } }
      let (x0, y0) = (most(p[0], l), most(p[1], t0))
      let (x1, y1) = (least(p[0] + p[2], r), least(p[1] + p[3], b))
      out = Some(((x0, y0, x1 - x0, y1 - y0), clips[k].1))
    }
  }
  out
}

///|
/// Whether (`x`, `y`) is in rectangle `r` (x, y, w, h).
fn holds_point(x : Double, y : Double, r : (Double, Double, Double, Double)) -> Bool {
  r.0 <= x && x <= r.0 + r.2 && r.1 <= y && y <= r.1 + r.3
}
