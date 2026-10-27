// ＋'s recent photos (recent.mbt latest_photos), as the Android app's RecentPhotosTest checks Attach.kt's `latest`.

///|
let recent_now : Int64 = 1_792_245_000L

///|
fn photo(id : Int64, added : Int64, modified : Int64, taken : Int64) -> @hostapi.GalleryPhoto {
  { id, src: "content://media/external/images/media/\{id}", added, modified, taken, video: false }
}

///|
fn ranked(photos : Array[@hostapi.GalleryPhoto], n? : Int = 30) -> Array[Int64] {
  latest_photos(photos, recent_now, n).map(fn(p) { p.id })
}

///|
test "recent photos: newest first by their times" {
  let now = recent_now
  let photos = [photo(1, now - 3600, now - 3600, -1), photo(2, now - 60, now - 60, now - 60), photo(3, now - 600, -1, -1)]
  assert_eq(ranked(photos), [2L, 3L, 1L])
}

///|
test "recent photos: a time in milliseconds is the seconds it means" {
  // saved a year ago by an app that wrote when in milliseconds: behind a screenshot of a minute ago
  let now = recent_now
  let photos = [photo(1, (now - 31_536_000L) * 1000L, now - 31_536_000L, -1), photo(2, now - 60, now - 60, now - 60)]
  assert_eq(ranked(photos), [2L, 1L])
}

///|
test "recent photos: a time ahead of now is left out" {
  let now = recent_now
  let photos = [photo(1, now + 30L * 86_400L, now - 86_400L * 400L, -1), photo(2, now - 60, -1, -1)]
  assert_eq(ranked(photos), [2L, 1L])
}

///|
test "recent photos: when it came into the gallery ranks it" {
  // taken long ago, put in the gallery a moment ago (synced down): as new as when it came
  let now = recent_now
  let photos = [photo(1, now - 10, now - 10, now - 86_400L * 900L), photo(2, now - 60, now - 60, now - 60)]
  assert_eq(ranked(photos), [1L, 2L])
}

///|
test "recent photos: a picture just saved comes before those whose other times only say they are newer" {
  let now = recent_now
  // a screenshot of an hour ago whose time taken is written in the phone's time zone as if it were UTC (8 hours
  // ahead), an old photo the gallery wrote to a moment ago, a picture another app saved a minute ago
  let shot = photo(1, now - 3600, now - 3600, now + 7L * 3600L)
  let touched = photo(2, now - 86_400L * 400L, now - 5, now - 86_400L * 400L)
  let saved = photo(3, now - 60, now - 60, -1)
  assert_eq(ranked([shot, touched, saved]), [3L, 1L, 2L])
}

///|
test "recent photos: the same time by id, and no more than asked" {
  let now = recent_now
  let photos : Array[@hostapi.GalleryPhoto] = []
  for i in 1..=40 {
    photos.push(photo(i.to_int64(), now - 5, -1, -1))
  }
  photos.push(photo(99, -1, -1, -1))
  let want : Array[Int64] = []
  for i = 40; i >= 11; i = i - 1 {
    want.push(i.to_int64())
  }
  assert_eq(ranked(photos), want)
}

///|
/// The strip over `n` photos of the gallery (all of it read), across a phone, 添加 n 个 under it while some are chosen;
/// the tiles tapped to `tapped`.
fn strip_tester(n : Int, tapped : Array[Int]) -> @ui.Tester {
  recent_reset()
  recent.access.set(Whole)
  for i in 1..=n {
    recent.photos.push(photo(i.to_int64(), recent_now - i.to_int64(), -1, -1))
  }
  let t = @ui.Tester::new(
    fn(c) {
      recent_strip(c, fn(i) { tapped.push(i) })
      recent_adding(c, fn(_) {  }) |> ignore
    },
    platform=2,
  )
  t.draw()
  t
}

///|
/// Where tile `i` of the strip is (0 the camera): its start and top, the row 12 and 4 in, a tile 92 wide and 6 apart.
fn strip_tile(i : Int) -> (Double, Double) {
  (12.0 + i.to_double() * recent_step, 4.0)
}

///|
test "recent photos: a tap puts one in alone; its ring chooses it, then a tap anywhere on a tile, numbered in turn" {
  let tapped = []
  let t = strip_tester(4, tapped)
  let src = fn(i : Int) { recent.photos[i - 1].src }
  // none chosen: a tap on a photo is it alone
  let (x1, y1) = strip_tile(1)
  t.tap(x1 + 40.0, y1 + 90.0)
  assert_eq(tapped, [1])
  assert_eq(recent.chosen.length(), 0)
  // its ring in its top end corner chooses it
  let (x2, y2) = strip_tile(2)
  t.tap(x2 + recent_tile_w - 10.0, y2 + 10.0)
  assert_eq(recent.chosen.copy(), [src(2)])
  // some chosen: a tap anywhere on a tile chooses it, or not
  let (x3, y3) = strip_tile(3)
  t.tap(x3 + 40.0, y3 + 90.0)
  assert_eq(recent.chosen.copy(), [src(2), src(3)])
  assert_eq(tapped, [1])
  // each numbered in the order chosen, in its ring
  let ring_at = fn(i : Int) {
    let (x, _) = strip_tile(i)
    x + recent_tile_w - recent_mark_in(@sf.row_corner) - recent_mark_side
  }
  match (t.rect_of("1"), t.rect_of("2")) {
    (Some((a, _, aw, _)), Some((b, _, bw, _))) => {
      assert_true(a >= ring_at(2) && a + aw <= ring_at(2) + recent_mark_side)
      assert_true(b >= ring_at(3) && b + bw <= ring_at(3) + recent_mark_side)
    }
    _ => fail("the chosen are not numbered")
  }
  t.tap(x2 + 40.0, y2 + 90.0)
  assert_eq(recent.chosen.copy(), [src(3)])
  // the camera is still the camera
  let (x0, y0) = strip_tile(0)
  t.tap(x0 + 40.0, y0 + 60.0)
  assert_eq(tapped, [1, 0])
  recent_reset()
}

///|
test "recent photos: 添加 n 个 stands where the tiles under the strip were, while some are chosen" {
  let tapped = []
  let t = strip_tester(3, tapped)
  let (x1, y1) = strip_tile(1)
  t.tap(x1 + recent_tile_w - 10.0, y1 + 10.0)
  let (x2, y2) = strip_tile(2)
  t.tap(x2 + 40.0, y2 + 90.0)
  assert_eq(recent.chosen.length(), 2)
  // under the strip (4 over its tiles, 12 under), as high as the tiles: pressed, they go and none is chosen
  t.tap(195.0, 4.0 + recent_tile_h + 12.0 + recent_add_h / 2.0)
  assert_eq(recent.chosen.length(), 0)
  assert_eq(tapped, [])
  recent_reset()
}
