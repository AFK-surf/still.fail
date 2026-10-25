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
