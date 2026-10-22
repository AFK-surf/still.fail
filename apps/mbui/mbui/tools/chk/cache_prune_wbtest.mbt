///|
test "a rolling cache's kind" {
  assert_eq(
    kind_of("mbui-apk-09b758a048c406bf0db415ad3709264632d1cb5b"),
    Some("mbui-apk"),
  )
  assert_eq(
    kind_of("mbui-linux-store-lto-app-00b78fb4840fdc3e"),
    Some("mbui-linux-store-lto-app"),
  )
  assert_eq(
    kind_of(
      "gradle-home-v1|Linux-X64|check-android[2face68063188a806d63532a8cee1e9b]-09b758a048c406bf0db415ad3709264632d1cb5b",
    ),
    Some("gradle-home-v1|Linux-X64|check-android[2face68063188a806d63532a8cee1e9b]"),
  )
  assert_eq(kind_of("mbui-ios-build-39731343052-1"), Some("mbui-ios-build"))
  assert_eq(kind_of("warp-1.0.21"), None)
  assert_eq(kind_of("android-image-36-google_apis-x86_64-7"), None)
  assert_eq(kind_of("android-ndk-28.2.13676358-Linux-X64"), None)
  assert_true(is_gradle_part("gradle-transforms-v1-8bc0a5259a7f8a719cff172016a05c50"))
  assert_false(is_gradle_part("gradle-home-v1|Linux-X64|x[2face68063188a806d63532a8cee1e9b]-09b758a0"))
}

///|
test "a time of GitHub's in seconds" {
  assert_eq(iso_s("1970-01-01T00:00:00Z"), 0.0)
  assert_eq(iso_s("2026-10-22T05:37:59.731503Z"), 1792647479.0)
}
