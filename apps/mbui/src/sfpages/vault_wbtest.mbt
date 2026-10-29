// 密钥 (vault.mbt, vault_item.mbt, vault_dialogs.mbt) alone, at each width, with a finger and with a mouse: the
// request waiting as its card, how its secrets are kept a row each (encrypted, the longest a grant lasts, its choices
// through the presenters, the devices holding its key), 全部密钥 a row to its secrets' page; there its secrets, a row
// each of one list found by their words, and 添加 through the presenters.

///|
test "密钥, at each width and with either hand: the request's card, encrypted, the longest grant; its secrets a page under it, 添加 there asks what" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Vault, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("git push origin main") is Some(_), msg=at)
    // (what it keeps: a page under it, adding there)
    assert_true(t.find("部署机") is None, msg=at)
    assert_true(page_add(t) is None, msg=at)
    // how it is kept, a row each: encrypted, the longest grant the one now under it, the devices holding its key
    scrolled_to(t, w, "默认最长授权")
    for words in ["已加密", "仅你的设备可解密", "默认最长授权", "直到对话归档", "2 台设备已授权"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    // its choices, each with what it means, through the presenters (none of them on the page itself)
    assert_true(t.find("每次使用都要你批准一次") is None, msg=at)
    let (lx, ly) = t.find("默认最长授权").unwrap()
    t.tap(lx, ly)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    presented_in(t)
    assert_true(t.find("每次使用都要你批准一次") is Some(_), msg=at)
    @sf.close_presented()
    t.frame()
    // 全部密钥 pressed: its page, its secrets and 添加
    scrolled_to(t, w, "全部密钥")
    tap_words(t, "全部密钥")
    t.frame()
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(VaultItems), msg=at)
    scrolled_to(t, w, "部署机")
    assert_true(t.find("部署机") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    let (x, y, bw, bh) = page_add(t).unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    @sf.close_presented()
    t.frame()
  }
}

///|
test "全部密钥, at each width and with either hand: every secret a row of one list, its kind and what is worth knowing of it under its name; the profiles' accounts folded at its foot; found by any of their words" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(VaultItems, w, platform~)
    let at = "\{w} platform \{platform}"
    // (a secret: its kind, how an agent gets it, when and where it was last used)
    for words in ["GitHub token", "Token · 代理 · api.github.com · 昨天在「修 CI」用过", "SSH 密钥 · ssh-agent", "订阅和 API Key", "Claude 主账号、ChatGPT 团队、备用 key"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    // the accounts folded till their row (naming them) is pressed: no row of theirs
    assert_true(t.find("Claude 订阅 · 只在 Studio") is None, msg=at)
    scrolled_to(t, w, "订阅和 API Key")
    tap_words(t, "订阅和 API Key")
    t.frame()
    scrolled_to(t, w, "Claude 订阅 · 只在 Studio")
    for words in ["Claude 主账号", "Claude 订阅 · 只在 Studio"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    // found: 部署机 by its way, nothing else
    t.wheel(w / 2.0, 450.0, -3000.0)
    t.frame()
    let (fx, fy) = t.find("搜索名称、域名、变量名").unwrap()
    t.tap(fx + 4.0, fy + 4.0)
    t.frame()
    t.type_text("ssh")
    t.frame()
    assert_true(t.find("部署机") is Some(_), msg=at)
    for gone in ["GitHub token", "Claude", "订阅和 API Key"] {
      assert_true(t.find(gone) is None, msg="\{at}: \{gone}")
    }
    t.type_text("zz")
    t.frame()
    assert_true(t.find("没有找到「sshzz」") is Some(_), msg=at)
  }
}

///|
test "a secret's page, at each width and with either hand: what it is and where, its content masked, how agents use it, 编辑" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(VaultItem("v1", "it1"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("GitHub token") is Some(_), msg=at)
    assert_true(t.find("内容") is Some(_), msg=at)
    assert_true(t.query(Button, label="编辑") is Some(_), msg=at)
    scrolled_to(t, w, "代理 · 限 api.github.com")
    assert_true(t.find("代理 · 限 api.github.com") is Some(_), msg=at)
  }
}

///|
test "secrets left in plain text from before security mode: how many, 加密 encrypting them into the vault" {
  let t = setting_tester(Vault, 390.0, platform=2, mode="settings-vault-plain")
  scrolled_to(t, 390.0, "2 条密钥尚未加密")
  assert_true(t.find("2 条密钥尚未加密") is Some(_))
  // (its row pressed: 加密 where it says what it does, the last words with 加密 in them as the title says it too)
  let (x, y) = t.find_last("加密").unwrap()
  t.tap(x, y)
  assert_true(t.find("2 条密钥尚未加密") is None)
}

///|
test "密钥: 默认最长授权 a row over the profiles' keys, the one now under it; pressed, its three choices, each with what it means (Vault.kt DefaultLasts)" {
  let t = setting_tester(Vault, 390.0, platform=2)
  scrolled_to(t, 390.0, "默认最长授权")
  assert_true(t.find("直到对话归档") is Some(_))
  assert_true(t.find("每次使用都要你批准一次") is None)
  let (x, y) = t.find("默认最长授权").unwrap()
  t.tap(x, y)
  t.frame()
  presented_in(t)
  for words in ["仅一次", "1 小时", "每次使用都要你批准一次", "最长能选「本对话直到归档」，至多 30 天"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
}

///|
/// 添加 at the page's head (not a phone's bottom bar's, at the window's foot).
fn page_add(t : @ui.Tester) -> @ui.SemNode? {
  for s in t.all(Button, label="添加") {
    if s.rect.1 < 450.0 {
      return Some(s)
    }
  }
  None
}

///|
/// What was just presented, in: a sheet (with a finger short of the Large tier) at rest; a panel by what opened it or
/// a dialog (with a pointer) past its coming.
fn presented_in(t : @ui.Tester) -> Unit {
  let rest = @kit.sheet_rest("sf-present")
  t.run_for(if rest > t.time() { rest - t.time() } else { @ui.move_most_ms })
}
