// A Feishu connect (FeishuConnect.kt over the core's `connectFlow`'s Feishu path): the platform picked first (Slack
// or 飞书, while the station has the Feishu connect), then the model and mode, then a bot made by scanning a QR code
// in Feishu (`connect.flow.register`) or an app of one's own (its App ID and Secret, `connect.flow.verify`), the
// connect added (`connect.flow.create`); on its page, its app (the App ID, the secret replaced: `feishu.putSecret`).

///|
/// The wizard's steps drawn here; the rest are Slack's (new_connect_page).
// kept across runs: a table of constants, never written
let feishu_steps_drawn : Array[String] = ["platform", "feishuBind", "feishuWay", "feishuScan", "feishuApp", "done"]

///|
/// The new connects whose page has already gone on to the connect added (by form).
let feishu_made : Map[String, Bool] = Map([])

///|
/// What was typed into an app of one's own's fields (by form and field), echoed at once: the draft is the core's.
let feishu_typed : Map[String, String] = Map([])

///|
/// One of the Feishu steps (FeishuSteps); `bind`: the model and mode pickers, as Slack's last step has them; `next`:
/// a step's button at its end. Its connect added (step `done`), its page replaces this one.
fn feishu_steps(
  c : @ui.Ctx,
  core : Core,
  station : String,
  form : String,
  view : Json?,
  edit : (Array[(String, Json)]) -> Unit,
  go : (String) -> Unit,
  bind : () -> Unit,
  next : (String, String, Bool, () -> Unit) -> Unit,
  busy : Bool,
) -> Unit {
  let t = @sf.theme()
  let step = text(view, "step")
  let f = field(view, "feishu")
  let flow = fn(action : String) { flow_act(core, station, form, action, fn(_) {  }) }
  let edit_feishu = fn(k : String, v : Json) { edit([("feishu", obj([(k, v)]))]) }
  if step == "done" {
    match opt_text(f, "connect") {
      Some(id) if !feishu_made.contains(form) => {
        feishu_made[form] = true
        (core.say)(tr("web-mobile.connects.feishu.added"))
        (core.pop)()
        (core.push)(Connect(station, id))
      }
      _ => ()
    }
  }
  guard f is Some(Object(_)) else { return }
  match step {
    "platform" => {
      let platform = opt_text(view, "platform").unwrap_or("slack")
      let feishu = strings(view, "platforms").contains("feishu")
      c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, fn() {
        if pick_row(
            c,
            "flow-platform/slack",
            "Slack",
            sub=tr("web-mobile.connects.feishu.slackNote"),
            checked=platform == "slack",
            mark=fn() { @sf.slack_mark(c, 20.0) |> ignore },
          ) {
          edit([("platform", str("slack"))])
        }
        if pick_row(
            c,
            "flow-platform/feishu",
            tr("web-mobile.connects.feishu.name"),
            sub=tr(if feishu { "web-mobile.connects.feishu.feishuNote" } else { "web-mobile.connects.feishu.update" }),
            checked=platform == "feishu",
            enabled=feishu,
            mark=fn() { @sf.feishu_mark(c, 20.0) |> ignore },
          ) {
          edit([("platform", str("feishu"))])
        }
      })
      |> ignore
      next("flow-platform-next", tr("android-settings.flow.next"), true, fn() {
        go(if platform == "feishu" && feishu { "feishuBind" } else { "team" })
      })
    }
    "feishuBind" => {
      bind()
      next("flow-feishu-bind", tr("android-settings.flow.next"), flag(view, "canCreate"), fn() { go("feishuWay") })
    }
    "feishuWay" => {
      let way = text(f, "way")
      c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, fn() {
        if pick_row(c, "flow-feishu-scan", tr("web-mobile.connects.feishu.scan"), sub=tr("web-mobile.connects.feishu.scanNote"), checked=way != "app") {
          edit_feishu("way", str("scan"))
        }
        if pick_row(c, "flow-feishu-app", tr("web-mobile.connects.feishu.app"), sub=tr("web-mobile.connects.feishu.appNote"), checked=way == "app") {
          edit_feishu("way", str("app"))
        }
      })
      |> ignore
      next("flow-feishu-way", tr("android-settings.flow.next"), true, fn() {
        if way == "app" {
          go("feishuApp")
        } else {
          flow("register")
        }
      })
    }
    "feishuApp" => feishu_own_app(c, form, f, edit_feishu, next, flow)
    // scanning, or its connect added (its page on the way)
    _ =>
      if step == "feishuScan" || field(f, "registration") is Some(Object(_)) {
        let r = field(f, "registration")
        let waiting = text(r, "state") == "waiting"
        let failed = flag(f, "failed")
        let error = opt_text(f, "error")
        c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
          if flag(f, "creating") || (text(r, "state") == "done" && error is None && opt_text(f, "connect") is None) {
            spinner(c, inline=true)
          }
          match opt_text(f, "stateText") {
            Some(s) =>
              c.text(s, size=14.0, color=if failed || error is Some(_) { t.p.red } else { t.p.muted }, w=Fill(1.0), line=20.0)
              |> ignore
            None => ()
          }
        })
        |> ignore
        if waiting {
          // C.link: the accent's ink in the light, the accent itself in the dark
          let link = if t.dark { t.p.accent } else { t.p.accent_text }
          if tap_text(c, "flow-feishu-open", tr("web-mobile.connects.feishu.openInFeishu"), color=link, size=14.0) {
            (core.open_link)(text(r, "url"))
          }
          match field(f, "qr") {
            Some(Object(_)) as code =>
              c.box(w=Fill(1.0), pady=4.0, align=ACenter, fn() { feishu_qr(c, code, 220.0) }) |> ignore
            _ => ()
          }
          c.text(tr("web-mobile.connects.feishu.scanHint"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
        }
        match error {
          Some(e) => c.text(e, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
          None => ()
        }
        if failed {
          next("flow-feishu-qr", tr("web-mobile.connects.feishu.newQr"), true, fn() { flow("register") })
        } else if error is Some(_) {
          next("flow-feishu-retry", tr("web-mobile.connects.feishu.retry"), !flag(f, "creating"), fn() { flow("create") })
        }
        ignore(busy)
      }
  }
}

///|
/// An app of one's own (OwnApp): its App ID and Secret (Lark or not), verified, then the connect added with it.
fn feishu_own_app(
  c : @ui.Ctx,
  form : String,
  f : Json?,
  edit_feishu : (String, Json) -> Unit,
  next : (String, String, Bool, () -> Unit) -> Unit,
  flow : (String) -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.text(tr("web-mobile.connects.feishu.appHint"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
  // each field filled from the draft once, what is typed sent as it changes
  let field_of = fn(part : String, placeholder : String, secret : Bool) {
    let key = "feishu-app/" + form + "/" + part
    if !new_filled.contains(key) {
      new_filled[key] = true
      field_of(key).set(text(f, part))
    }
    let words = field_box(c, key, placeholder, mono=!secret, secret~)
    if words != feishu_typed.get(key).unwrap_or(text(f, part)) {
      feishu_typed[key] = words
      edit_feishu(part, str(words))
    }
  }
  c.text("App ID", size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
  field_of("appId", "cli_…", false)
  c.text("App Secret", size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
  field_of("appSecret", "", true)
  let lark = flag(f, "lark")
  let lid = c.id("feishu-app/" + form + "/lark")
  if hit(c, lid) {
    edit_feishu("lark", Json::boolean(!lark))
  }
  c.box(dir=Row, w=Fill(1.0), padx=14.0, pady=10.0, radius=14.0, bg=t.p.chip, gap=12.0, align=ACenter, id=lid, fn() {
    c.box(w=Fill(1.0), fn() {
      c.text(tr("web-mobile.connects.feishu.lark"), size=14.0, weight=600, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
      c.text(tr("web-mobile.connects.feishu.larkNote"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
    })
    |> ignore
    switch(c, "feishu-app/" + form + "/lark", lark)
  })
  |> ignore
  let identity = field(f, "identity")
  if flag(f, "verified") && identity is Some(Object(_)) {
    let bot = text(identity, "botName")
    let words = match opt_text(field(identity, "tenant"), "name") {
      Some(tenant) => fill("web-mobile.connects.feishu.verified", [("bot", bot), ("tenant", tenant)])
      None => fill("web-mobile.connects.feishu.verifiedBot", [("bot", bot)])
    }
    // C.greenInk: darker than the green in the light
    c.text(words, size=12.0, color=if t.dark { t.p.green } else { 0x287A4DFFL }, w=Fill(1.0), line=17.0) |> ignore
  }
  for e in strings(f, "errors") {
    c.text(e, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
  }
  match opt_text(f, "error") {
    Some(e) => c.text(e, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
    None => ()
  }
  if flag(f, "verified") {
    next("flow-feishu-create", tr("android-settings.flow.create"), !flag(f, "creating"), fn() { flow("create") })
  } else {
    next("flow-feishu-verify", tr("web-mobile.connects.feishu.verify"), flag(f, "canVerify"), fn() { flow("verify") })
  }
}

///|
/// A QR code the core made (its dark modules row by row, `1` dark), on white whatever the theme, four modules of
/// quiet zone around, whole pixels a module (Qr).
fn feishu_qr(c : @ui.Ctx, code : Json?, size : Double) -> Unit {
  let rows = strings(code, "rows")
  let quiet = 4
  let n = count(code, "size") + quiet * 2
  let cell = (size / n.to_double()).floor()
  let start = (size - cell * n.to_double()) / 2.0 + cell * quiet.to_double()
  c.box(w=Px(size), h=Px(size), radius=12.0, bg=0xFFFFFFFFL, clip=true, fn() {
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
          c.box(w=Px(rw), h=Px(cell), bg=0x000000FFL, tx=rx, ty=ry, fn() {  }) |> ignore
        })
        |> ignore
        x = end + 1
      }
    }
  })
  |> ignore
}

///|
/// A Feishu connect's app on its page: its App ID, its secret (masked) replaced from here.
fn feishu_section(c : @ui.Ctx, core : Core, station : String, cv : Json?) -> Unit {
  let t = @sf.theme()
  let f = field(cv, "feishu")
  list_card(c, fn() {
    list_row(c, fn() { row_lines(c, "App ID", text(f, "appId")) }) |> ignore
    if list_row(c, key="feishu-secret", fn() {
        row_lines(c, "App Secret", match text(f, "appSecret") {
          "" => "••••••••"
          s => s
        })
        c.text(tr("web-mobile.connects.feishu.replaceShort"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
      }) {
      open_feishu_secret(core, station, cv)
    }
  })
}

///|
/// A Feishu connect's App Secret replaced (openFeishuSecret): verified by its station before it is kept (so the sheet
/// waits), then it reconnects.
fn open_feishu_secret(_core : Core, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  vault_serial.val += 1
  let key = "feishu-secret/" + vault_serial.val.to_string()
  let error : Ref[String] = Ref("")
  open_sheet(0.5, fn(c, core) {
    let t = @sf.theme()
    let busy = is_doing(core, ["feishu.putSecret"], [("station", station), ("id", id)])
    sheet_head(c, tr("web-mobile.connects.feishu.replace"))
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      c.text(tr("web-mobile.connects.feishu.replaceNote"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
      c.text("App Secret", size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
      let secret = field_box(c, key, text(field(cv, "feishu"), "appSecret"), secret=true).trim(chars=" \n").to_owned()
      if error.val != "" {
        c.text(error.val, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      }
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if button(c, "feishu-secret-cancel", tr("common.cancel"), false) {
          close_sheet()
        }
        if button(c, "feishu-secret-save", tr("android-settings.tokens.save"), true, busy~, enabled=secret != "") {
          error.val = ""
          // a secret the station refused said under the field, the sheet kept
          (core.call)(
            "feishu.putSecret",
            obj([("station", str(station)), ("id", str(id)), ("appSecret", str(secret))]),
            fn(r) {
              match r {
                Ok(_) => {
                  (core.say)(tr("web-mobile.connects.feishu.secretSaved"))
                  close_sheet()
                }
                Err(e) => error.val = error_text(e)
              }
            },
          )
        }
      })
      |> ignore
    })
    |> ignore
  })
}
