///|
/// A video's parts read by the host itself (Android's player past the app's GL thread, 2026-11-01: a 4K film stalled,
/// each 4 MB part waiting on the thread that draws it): the call the app's own reader makes, every part's offset and
/// length left to each read, streamed, with the size its folder says.
test "direct_part: the app's part call, its offset and length each read's own" {
  let p = drive_params("ws1/st1", "r", "a.mp4")
  drive_keep(p, "played", 5.0, 9000.0)
  p["offset"] = Json::number(4096.0)
  p["length"] = Json::number(1024.0)
  let said = @json.parse(direct_part("drive.read", p, 9000.0)) catch { _ => panic() }
  assert_eq(
    said,
    {
      "call": "drive.read",
      "params": {
        "station": "ws1/st1",
        "root": "r",
        "path": "a.mp4",
        "keep": "played",
        "mtime": 5.0,
        "size": 9000.0,
        "stream": true,
      },
      "size": 9000.0,
    },
  )
  // (the part's own params untouched: the app's reader goes on with them)
  assert_eq(p.get("offset"), Some(Json::number(4096.0)))
}
