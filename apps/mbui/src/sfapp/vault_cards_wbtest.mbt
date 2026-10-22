// An agent's request for a vault item on its card (vault_approval.mbt; Vault.kt VaultApproval), and the secrets left in
// plain text from before security mode (settings/vault.mbt plain_left; Vault.kt PlainLeft).

///|
/// A source over the settings' fixture whose vault in ws1 holds `requests` (and holds keys here: `available`); the
/// calls made, by name and params.
fn vault_src(requests : Array[String], available : Bool, calls : Array[String]) -> Source {
  let base = fixture("settings")
  {
    ..base,
    topic: fn(name, params) {
      if name == "vaults" {
        {
          value: Some(
            Json::object({
              "available": Json::boolean(available),
              "requests": Json::array(requests.map(fn(r) { Json::object({ "id": Json::string(r) }) })),
            }),
          ),
          error: None,
          version: 1,
        }
      } else {
        (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push(name + " " + params.stringify())
      done(Ok(Json::null()))
    },
  }
}

///|
test "a vault request waiting on the viewer: its three answers in place of the card's; 仅本次 approves it once" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls)
  let t = @ui.Tester::new(fn(c) { c.box(w=Fill(1.0), fn() { vault_approval(c, src, "ws1", "r1", true) }) |> ignore }, w=390.0, h=844.0)
  t.draw()
  for w in ["仅本次", "本对话 1 小时内", "拒绝"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  t.tap_text("仅本次")
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\"}"])
}

///|
test "a vault request another's to decide, or on a device with no key: shown, not to be tapped; once decided, said so" {
  reset()
  let calls = []
  // another's
  let t = @ui.Tester::new(
    fn(c) { c.box(w=Fill(1.0), fn() { vault_approval(c, vault_src(["r1"], true, calls), "ws1", "r1", false) }) |> ignore },
    w=390.0,
    h=844.0,
  )
  t.draw()
  t.tap_text("仅本次")
  t.draw()
  assert_eq(calls.length(), 0)
  // a device with no key: the app's to approve
  reset()
  let t = @ui.Tester::new(
    fn(c) { c.box(w=Fill(1.0), fn() { vault_approval(c, vault_src(["r1"], false, calls), "ws1", "r1", true) }) |> ignore },
    w=390.0,
    h=844.0,
  )
  t.draw()
  assert_true(t.find("请在客户端批准") is Some(_))
  // no longer among the requests
  reset()
  let t = @ui.Tester::new(
    fn(c) { c.box(w=Fill(1.0), fn() { vault_approval(c, vault_src([], true, calls), "ws1", "r1", true) }) |> ignore },
    w=390.0,
    h=844.0,
  )
  t.draw()
  assert_true(t.find("此申请已处理") is Some(_))
  assert_true(t.find("仅本次") is None)
}

///|
test "secrets left in plain text from before security mode: how many, 加密 encrypting them into the vault" {
  let t = settings_tester("vault", mode="settings-vault-plain", shows="settings-vault-plain")
  shown_on_page(t, "2 条密钥尚未加密")
  assert_true(t.find("2 条密钥尚未加密") is Some(_))
  // (the button: the last words with 加密 in them, the title says it too)
  let (x, y) = t.find_last("加密").unwrap()
  t.tap(x, y)
  assert_true(t.find("2 条密钥尚未加密") is None)
}

///|
test "密钥: 默认最长授权 over the profiles' keys, its note and its three choices (Vault.kt DefaultLasts)" {
  let t = settings_tester("vault")
  shown_on_page(t, "默认最长授权")
  assert_true(t.find("默认最长授权") is Some(_))
  for words in ["仅一次", "1 小时", "直到对话归档", "每次使用都要你批准一次"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
}
