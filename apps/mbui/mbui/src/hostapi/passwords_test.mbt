///|
test "a login is for a site: its own host, a host under it, or one it is under; not one that only ends alike" {
  assert_true(@hostapi.login_for_host("https://github.com/login", "github.com"))
  assert_true(@hostapi.login_for_host("github.com", "github.com"))
  assert_true(@hostapi.login_for_host("https://google.com", "accounts.google.com"))
  assert_true(@hostapi.login_for_host("https://accounts.google.com:443/x?y#z", "google.com"))
  assert_true(@hostapi.login_for_host("HTTPS://GitHub.com", "github.com"))
  assert_false(@hostapi.login_for_host("https://notgithub.com", "github.com"))
  assert_false(@hostapi.login_for_host("", "github.com"))
}

///|
test "op's answers: a site's logins from its list, a login's account and password from its fields" {
  let listed = "[{\"id\":\"a\",\"title\":\"GitHub\",\"additional_information\":\"zzj\",\"urls\":[{\"href\":\"https://github.com\"}]},{\"id\":\"b\",\"title\":\"GitLab\",\"urls\":[{\"href\":\"https://gitlab.com\"}]},{\"id\":\"c\",\"title\":\"No site\"}]"
  assert_eq(@hostapi.logins_for(listed, "github.com"), [{ id: "a", title: "GitHub", username: "zzj" }])
  assert_eq(@hostapi.logins_for("not json", "github.com"), [])
  let got = "[{\"id\":\"username\",\"label\":\"username\",\"value\":\"zzj\"},{\"id\":\"password\",\"label\":\"password\",\"purpose\":\"PASSWORD\",\"value\":\"s3cret\"}]"
  assert_eq(@hostapi.login_fields(got), ("zzj", "s3cret"))
  assert_eq(@hostapi.login_fields("{\"label\":\"password\",\"value\":\"only\"}"), ("", "only"))
}

///|
test "a passkey's parts between the host's hex and the wire's base64url, both ways" {
  assert_eq(@hostapi.b64url_of_hex(""), "")
  assert_eq(@hostapi.b64url_of_hex("0909"), "CQk")
  assert_eq(@hostapi.b64url_of_hex("010203"), "AQID")
  assert_eq(@hostapi.b64url_of_hex("fbff"), "-_8")
  assert_eq(@hostapi.b64url_of_hex("FBFF"), "-_8")
  assert_eq(@hostapi.b64url_of_hex("0g"), "")
  assert_eq(@hostapi.b64url_of_hex("abc"), "")
  assert_eq(@hostapi.hex_of_b64url("CQk"), "0909")
  assert_eq(@hostapi.hex_of_b64url("AQID"), "010203")
  assert_eq(@hostapi.hex_of_b64url("-_8="), "fbff")
  assert_eq(@hostapi.hex_of_b64url("a+b"), "")
}
