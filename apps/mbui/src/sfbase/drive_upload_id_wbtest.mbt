///|
/// A file going up into `dir` of root `root` of station `station`.
fn up_of(station : String, root : String, dir : String, name : String, bytes : Bytes, serial : Int) -> DvUpload {
  {
    serial,
    station,
    root,
    dir,
    name: @signals.signal(name),
    bytes,
    sent: @signals.signal(0),
    state: @signals.signal("waiting"),
    error: @signals.signal(""),
    replace: false,
    id: "",
  }
}

///|
test "an upload's id is the same where the station's folder is another path on its machine" {
  let st = "ws/station-key"
  // the same folder lent, its path on one machine and on another (and as a recording says it)
  let here = dv_upload_id(up_of(st, "/tmp/mbui-e2e-501/home/e2e-115455", "", "e2e-photo.jpg", b"photo", 1))
  let there = dv_upload_id(up_of(st, "/test-station/home/e2e-115455", "", "e2e-photo.jpg", b"photo", 1))
  assert_eq(here, there)
  assert_eq(here.length(), 32)
}

///|
test "an upload's id still tells apart where it goes, what it is and its place" {
  let st = "ws/station-key"
  let one = dv_upload_id(up_of(st, "/r", "a", "f.txt", b"one", 1))
  assert_true(one != dv_upload_id(up_of(st, "/r", "b", "f.txt", b"one", 1)), msg="another folder")
  assert_true(one != dv_upload_id(up_of(st, "/r", "a", "g.txt", b"one", 1)), msg="another name")
  assert_true(one != dv_upload_id(up_of(st, "/r", "a", "f.txt", b"two", 1)), msg="other bytes")
  assert_true(one != dv_upload_id(up_of(st, "/r", "a", "f.txt", b"one", 2)), msg="another place among the uploads")
  assert_true(one != dv_upload_id(up_of("ws/other", "/r", "a", "f.txt", b"one", 1)), msg="another station")
}
